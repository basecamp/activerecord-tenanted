# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    # instance methods common to both Tenant and Subtenant
    module TenantCommon # :nodoc:
      extend ActiveSupport::Concern

      prepended do
        attr_reader :tenant

        before_save :ensure_tenant_context_safety
      end

      def cache_key
        tenant ? "#{tenant}/#{super}" : super
      end

      def inspect
        return super unless tenant

        super.sub(/\A#<\S+ /, "\\0tenant: #{tenant.inspect}, ")
      end

      def to_global_id(options = {})
        super(options.merge(tenant: tenant))
      end

      def to_signed_global_id(options = {})
        super(options.merge(tenant: tenant))
      end

      def association(name)
        super.tap do |assoc|
          if assoc.reflection.polymorphic? || assoc.reflection.klass.tenanted?
            ensure_tenant_context_safety
          end
        end
      end

      alias to_gid to_global_id
      alias to_sgid to_signed_global_id

      private
        # I would prefer to do this in an `after_initialize` callback, but some associations are
        # created before those callbacks are invoked (for example, a `belongs_to` association) and
        # we need to be able to ensure tenant context safety on all associations.
        def init_internals
          @tenant = self.class.current_tenant
          super
        end

        def ensure_tenant_context_safety
          self_tenant = self.tenant
          current_tenant = self.class.current_tenant

          if current_tenant.nil?
            raise NoTenantError, "Cannot connect to a tenanted database while untenanted (#{self.class})"
          elsif self_tenant != current_tenant
            raise WrongTenantError,
                  "#{self.class} model belongs to tenant #{self_tenant.inspect}, " \
                  "but current tenant is #{current_tenant.inspect}"
          end
        end
    end

    module Tenant
      extend ActiveSupport::Concern

      # This is a sentinel value used to indicate that the class is not currently tenanted.
      #
      # It's the default value returned by `current_shard` when the class is not tenanted. The
      # `current_tenant` method's job is to recognizes that sentinel value and return `nil`, because
      # Active Record itself does not recognize `nil` as a valid shard value.
      UNTENANTED_SENTINEL = Class.new do # :nodoc:
        def inspect
          "ActiveRecord::Tenanted::Tenant::UNTENANTED_SENTINEL"
        end

        def to_s
          "(untenanted)"
        end
      end.new.freeze

      CONNECTION_POOL_CREATION_LOCK = Thread::Mutex.new # :nodoc:

      class_methods do
        def tenanted?
          true
        end

        def current_tenant
          shard = current_shard
          shard != UNTENANTED_SENTINEL ? shard : nil
        end

        def current_tenant=(tenant_name)
          case tenant_name
          when nil
            tenant_name = UNTENANTED_SENTINEL
          when UNTENANTED_SENTINEL
            # no-op
          else
            tenant_name = tenant_name.to_s
          end

          run_callbacks :set_current_tenant do
            connection_class_for_self.connecting_to(shard: tenant_name, role: ActiveRecord.writing_role)
          end
        end

        def tenant_exist?(tenant_name)
          tenanted_root_config.new_tenant_config(tenant_name).config_adapter.database_ready?
        end

        def with_tenant(tenant_name, prohibit_shard_swapping: true, &block)
          tenant_name = tenant_name.to_s unless tenant_name == UNTENANTED_SENTINEL

          if tenant_name == current_tenant
            run_callbacks :with_tenant, &block
          else
            connection_class_for_self.connected_to(shard: tenant_name, role: ActiveRecord.writing_role) do
              run_callbacks :with_tenant do
                prohibit_shard_swapping(prohibit_shard_swapping) do
                  log_tenant_tag(tenant_name, &block)
                end
              end
            end
          end
        end

        def create_tenant(tenant_name, if_not_exists: false, &block)
          created_db = false
          base_config = tenanted_root_config
          adapter = base_config.new_tenant_config(tenant_name).config_adapter

          adapter.acquire_ready_lock do
            unless adapter.database_exist?
              adapter.create_database

              # Disable schema version checks during tenant creation and migration
              # This prevents PendingMigrationError when the tenant schema is first being set up
              Thread.current[:ar_tenanted_skip_schema_check] = true
              begin
                with_tenant(tenant_name) do
                  connection_pool(schema_version_check: false)
                  ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant(tenant_name)
                end
              ensure
                Thread.current[:ar_tenanted_skip_schema_check] = false
              end

              created_db = true
            end
          rescue
            adapter.drop_database
            raise
          end

          raise TenantExistsError unless created_db || if_not_exists

          with_tenant(tenant_name) do
            yield if block_given?
          end
        end

        def destroy_tenant(tenant_name)
          ActiveRecord::Base.logger.info "  DESTROY [tenant=#{tenant_name}] Destroying tenant database"

          with_tenant(tenant_name, prohibit_shard_swapping: false) do
            if retrieve_connection_pool(strict: false)
              remove_connection
            end
          end

          tenanted_root_config.new_tenant_config(tenant_name).config_adapter.drop_database
        end

        def tenants
          # DatabaseConfigurations::BaseConfig#tenants returns all tenants whose database files
          # exist, but some of those may be getting initially migrated, so we perform an additional
          # filter on readiness with `tenant_exist?`.
          tenanted_root_config.tenants.select { |t| tenant_exist?(t) }
        end

        def with_each_tenant(**options, &block)
          tenants.each { |tenant| with_tenant(tenant, **options) { yield tenant } }
        end

        # This method is really only intended to be used for testing.
        def without_tenant(&block) # :nodoc:
          with_tenant(ActiveRecord::Tenanted::Tenant::UNTENANTED_SENTINEL, prohibit_shard_swapping: false, &block)
        end

        def connection_pool(schema_version_check: true) # :nodoc:
          if current_tenant
            pool = retrieve_connection_pool(strict: false)

            if pool.nil?
              CONNECTION_POOL_CREATION_LOCK.synchronize do
                # re-check now that we have the lock
                pool = retrieve_connection_pool(strict: false)

                if pool.nil?
                  # Check thread-local override for schema version check during tenant creation
                  skip_check = Thread.current[:ar_tenanted_skip_schema_check]
                  effective_schema_check = skip_check ? false : schema_version_check
                  _create_tenanted_pool(schema_version_check: effective_schema_check)
                  pool = retrieve_connection_pool(strict: true)
                end
              end
            end

            pool
          else
            Tenanted::UntenantedConnectionPool.new(tenanted_root_config, self)
          end
        end

        def tenanted_root_config # :nodoc:
          ActiveRecord::Base.configurations.resolve(tenanted_config_name.to_sym)
        end

        def _create_tenanted_pool(schema_version_check: true) # :nodoc:
          # ensure all classes use the same connection pool
          return superclass._create_tenanted_pool(schema_version_check: schema_version_check) unless connection_class?

          tenant = current_tenant
          db_config = tenanted_root_config.new_tenant_config(tenant)

          unless db_config.config_adapter.database_exist?
            raise TenantDoesNotExistError, "The database for tenant #{tenant.inspect} does not exist."
          end
          pool = establish_connection(db_config)

          if schema_version_check
            pending_migrations = pool.migration_context.open.pending_migrations
            raise ActiveRecord::PendingMigrationError.new(pending_migrations: pending_migrations) if pending_migrations.any?
          end

          pool
        end

        private
          def retrieve_connection_pool(strict:)
            role = current_role
            shard = current_tenant
            connection_handler.retrieve_connection_pool(connection_specification_name, role:, shard:, strict:).tap do |pool|
              if pool
                tenanted_connection_pools[[ shard, role ]] = pool
                reap_connection_pools
              end
            end
          end

          def reap_connection_pools
            while tenanted_connection_pools.size > tenanted_root_config.max_connection_pools
              info, _ = *tenanted_connection_pools.pop
              shard, role = *info

              connection_handler.remove_connection_pool(connection_specification_name, role:, shard:)
              Rails.logger.info "  REAPED [tenant=#{shard} role=#{role}] Tenanted connection pool reaped to limit total connection pools"
            end
          end

          def log_tenant_tag(tenant_name, &block)
            if Rails.application.config.active_record_tenanted.log_tenant_tag
              Rails.logger.tagged("tenant=#{tenant_name}", &block)
            else
              yield
            end
          end
      end

      prepended do
        self.default_shard = ActiveRecord::Tenanted::Tenant::UNTENANTED_SENTINEL

        prepend TenantCommon
        extend ActiveSupport::Callbacks

        cattr_accessor :tenanted_config_name
        cattr_accessor(:tenanted_connection_pools) { LRU.new }

        define_callbacks :with_tenant
        define_callbacks :set_current_tenant
      end

      def tenanted?
        true
      end
    end
  end
end
