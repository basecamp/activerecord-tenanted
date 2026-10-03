# frozen_string_literal: true

require "monitor"

module ActiveRecord
  module Tenanted
    # instance methods common to both Tenant and Subtenant
    module TenantCommon # :nodoc:
      extend ActiveSupport::Concern

      prepended do
        attr_reader :tenant

        before_save :ensure_belongs_to_tenant_safety, prepend: true
        before_save :ensure_tenant_context_safety, prepend: true
        before_destroy :ensure_tenant_context_safety, prepend: true
      end

      def cache_key
        tenant ? "#{tenant}/#{super}" : super
      end

      def ==(other)
        super && tenant == other.tenant
      end
      alias eql? ==

      def hash
        [ super, tenant ].hash
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

      def reload(...)
        ensure_tenant_context_safety

        super
      end

      def valid?(...)
        ensure_tenant_context_safety

        super
      end

      def delete
        ensure_tenant_context_safety

        super
      end

      # #update_column delegates here
      def update_columns(...)
        ensure_tenant_context_safety

        super
      end

      def touch(...)
        ensure_tenant_context_safety

        super
      end

      # #decrement! delegates here
      def increment!(...)
        ensure_tenant_context_safety

        super
      end

      # A belongs_to writes its foreign key onto this record, so nothing else notices when the
      # target came from another tenant's database.
      def ensure_belongs_to_tenant_safety
        self.class.reflect_on_all_associations(:belongs_to).each do |reflection|
          # Avoid creating the Association object for a belongs_to that was never touched
          next unless association_cached?(reflection.name)

          target = association(reflection.name).target

          if target && target.class.tenanted? && target.tenant != tenant
            raise WrongTenantError,
                  "#{self.class} model belongs to tenant #{tenant.inspect}, but its " \
                  "#{reflection.name} association belongs to tenant #{target.tenant.inspect}"
          end
        end
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

      # The tenant is an ordinary attribute in serialized snapshots of the record, the same way Job
      # and GlobalId serialize the tenant. Rails's only callers of this method are the serializers
      # (Marshal 7.1 format and MessagePack); it does not feed the persistence write path.
      def attributes_for_database
        super.merge!("tenant" => tenant)
      end

      def encode_with(coder)
        super
        coder["tenant"] = tenant
      end

      def init_with(coder, &block)
        super

        # Psych::Coder does not implement #key?, but exposes the underlying hash as #map
        @tenant = coder.map["tenant"] if coder.map.key?("tenant")

        self
      end

      def from_json(json, include_root = include_root_in_json)
        hash = ActiveSupport::JSON.decode(json)
        hash = hash.values.first if include_root

        @tenant = hash.delete("tenant") if hash.key?("tenant")

        self.attributes = hash
        self
      end

      def marshal_load(state)
        has_tenant = state[0].key?("tenant")
        tenant_name = state[0].delete("tenant")

        super

        @tenant = tenant_name if has_tenant
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

        # Presenting the tenant as one more serializable attribute lets ActiveModel apply the
        # `only:` and `except:` options to it, and read it back through the `tenant` reader.
        def attribute_names_for_serialization
          super + [ "tenant" ]
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
      POOL_REGISTRY_LOCK = Monitor.new # :nodoc:

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
          pool = nil

          adapter.acquire_ready_lock do
            unless adapter.database_exist?
              adapter.create_database

              with_tenant(tenant_name) do
                pool = connection_pool(schema_version_check: false)
                ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant(tenant_name)
              end

              pool.tenant_pool_ready!
              mark_tenant_pool_ready([ tenant_name.to_s, ActiveRecord.writing_role ], pool)
              created_db = true
            end
          rescue StandardError => creation_error
            begin
              if cleanup_failed_tenant_creation(tenant_name)
                adapter.drop_database
              else
                Rails.logger.error("Could not safely remove the database for an unsuccessful tenant creation")
              end
            rescue StandardError
              Rails.logger.error("Failed to clean up an unsuccessful tenant creation")
            end
            raise creation_error
          end

          raise TenantExistsError unless created_db || if_not_exists

          with_tenant(tenant_name) do
            yield if block_given?
          end
        end

        def destroy_tenant(tenant_name)
          ActiveRecord::Base.logger.info "  DESTROY [tenant=#{tenant_name}] Destroying tenant database"

          with_tenant(tenant_name, prohibit_shard_swapping: false) do
            if raw_tenant_connection_pool
              pool = raw_tenant_connection_pool
              POOL_REGISTRY_LOCK.synchronize do
                tenanted_connection_pools.delete_if_same([ current_tenant, current_role ], pool)
              end
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
          return Tenanted::UntenantedConnectionPool.new(tenanted_root_config, self) unless current_tenant

          pool_key = [ current_tenant, current_role ]
          pool = raw_tenant_connection_pool
          return pool if pool && ready_tenant_pool?(pool_key, pool)

          CONNECTION_POOL_CREATION_LOCK.synchronize do
            pool = raw_tenant_connection_pool
            return pool if pool && ready_tenant_pool?(pool_key, pool)
            if pool && !pool.tenant_pool_available_to_current_context?
              raise ActiveRecord::ConnectionNotEstablished, "tenant connection pool is not ready"
            end
            discard_stale_tenant_pool(pool_key)

            begin
              if pool
                return pool unless pool.tenant_pool_ready?

                ensure_tenant_pool_capacity!(already_registered: true)
                validate_tenant_pool_schema!(pool) if schema_version_check
              else
                ensure_tenant_pool_capacity!
                pool = _create_tenanted_pool(schema_version_check:)
              end

              mark_tenant_pool_ready(pool_key, pool) if pool.tenant_pool_ready?
              pool
            rescue StandardError
              failed_pool = pool || raw_tenant_connection_pool
              if failed_pool
                begin
                  cleanup_failed_tenant_pool(pool_key, failed_pool)
                rescue StandardError
                  Rails.logger.error("Failed to clean up a tenant connection pool after validation failed")
                end
              end
              raise
            end
          end
        end

        def tenanted_root_config # :nodoc:
          ActiveRecord::Base.configurations.resolve(tenanted_config_name.to_sym)
        end

        def _create_tenanted_pool(schema_version_check: true) # :nodoc:
          # ensure all classes use the same connection pool
          return superclass._create_tenanted_pool unless connection_class?

          previous_provisional_state = ActiveSupport::IsolatedExecutionState[:active_record_tenanted_provisional_pool]
          tenant = current_tenant
          db_config = tenanted_root_config.new_tenant_config(tenant)

          unless db_config.config_adapter.database_exist?
            raise TenantDoesNotExistError, "The database for tenant #{tenant.inspect} does not exist."
          end
          ActiveSupport::IsolatedExecutionState[:active_record_tenanted_provisional_pool] = !schema_version_check
          pool = establish_connection(db_config)
          ActiveSupport::IsolatedExecutionState[:active_record_tenanted_provisional_pool] = previous_provisional_state

          validate_tenant_pool_schema!(pool) if schema_version_check

          pool
        ensure
          ActiveSupport::IsolatedExecutionState[:active_record_tenanted_provisional_pool] = previous_provisional_state if defined?(previous_provisional_state)
        end

        private
          def raw_tenant_connection_pool(shard: current_tenant, role: current_role)
            connection_handler.retrieve_connection_pool(
              connection_specification_name,
              role:,
              shard:,
              strict: false)
          end

          def ready_tenant_pool?(pool_key, pool)
            POOL_REGISTRY_LOCK.synchronize do
              current = tenanted_connection_pools.peek(pool_key)
              if current.equal?(pool) && !pool.tenant_pool_retired? && !pool.tenant_pool_failed?
                tenanted_connection_pools[pool_key]
                true
              else
                false
              end
            end
          end

          def mark_tenant_pool_ready(pool_key, pool)
            POOL_REGISTRY_LOCK.synchronize do
              tenanted_connection_pools[pool_key] = pool
            end
          end

          def validate_tenant_pool_schema!(pool)
            pending_migrations = pool.migration_context.open.pending_migrations
            raise ActiveRecord::PendingMigrationError.new(pending_migrations:) if pending_migrations.any?
          end

          def registered_tenant_pool_configs
            manager = connection_handler.send(:get_pool_manager, connection_specification_name)
            return [] unless manager

            manager.pool_configs.select do |pool_config|
              pool_config.db_config.is_a?(ActiveRecord::Tenanted::DatabaseConfigurations::TenantConfig)
            end
          end

          def ensure_tenant_pool_capacity!(already_registered: false)
            capacity = tenanted_root_config.max_connection_pools
            target_size = capacity - (already_registered ? 0 : 1)
            return if registered_tenant_pool_configs.size <= target_size

            pool_snapshot = POOL_REGISTRY_LOCK.synchronize { tenanted_connection_pools.snapshot }

            pool_snapshot.each do |pool_key, pool|
              break if registered_tenant_pool_configs.size <= target_size

              unless raw_pool_for_key(pool_key).equal?(pool)
                POOL_REGISTRY_LOCK.synchronize { tenanted_connection_pools.delete_if_same(pool_key, pool) }
                next
              end

              retire_tenant_pool(pool_key, pool, require_ready: true)
            end

            if registered_tenant_pool_configs.size > target_size
              raise ConnectionPoolCapacityError, "All tenant connection pools are busy"
            end
          end

          def raw_pool_for_key(pool_key)
            shard, role = pool_key
            raw_tenant_connection_pool(shard:, role:)
          end

          def discard_stale_tenant_pool(pool_key)
            stale_pool = POOL_REGISTRY_LOCK.synchronize { tenanted_connection_pools.peek(pool_key) }
            return unless stale_pool
            return if raw_pool_for_key(pool_key).equal?(stale_pool)

            POOL_REGISTRY_LOCK.synchronize { tenanted_connection_pools.delete_if_same(pool_key, stale_pool) }
          end

          def cleanup_failed_tenant_pool(pool_key, pool)
            retired = retire_tenant_pool(pool_key, pool, require_ready: false)
            unless retired
              pool.tenant_pool_failed!
              POOL_REGISTRY_LOCK.synchronize { tenanted_connection_pools.delete_if_same(pool_key, pool) }
            end
            retired
          rescue StandardError
            pool.tenant_pool_failed!
            POOL_REGISTRY_LOCK.synchronize { tenanted_connection_pools.delete_if_same(pool_key, pool) }
            raise
          end

          def cleanup_failed_tenant_creation(tenant_name)
            pool_key = [ tenant_name.to_s, ActiveRecord.writing_role ]
            CONNECTION_POOL_CREATION_LOCK.synchronize do
              pool = raw_pool_for_key(pool_key)
              return true unless pool

              cleanup_failed_tenant_pool(pool_key, pool)
            end
          end

          def retire_tenant_pool(pool_key, pool, require_ready:)
            pool_config = pool.pool_config
            return false unless pool_config.mon_try_enter

            begin
              pool.try_with_retirement_barriers do
                next false unless pool.tenant_pool_idle?
                next false unless raw_pool_for_key(pool_key).equal?(pool)

                removed = POOL_REGISTRY_LOCK.synchronize do
                  registered = tenanted_connection_pools.peek(pool_key)
                  if registered.nil? && !require_ready
                    true
                  elsif registered.equal?(pool)
                    tenanted_connection_pools.delete_if_same(pool_key, pool)
                  else
                    false
                  end
                end
                next false unless removed

                begin
                  shard, role = pool_key
                  connection_handler.remove_connection_pool(connection_specification_name, role:, shard:)
                  Rails.logger.info "  REAPED [tenant=#{shard} role=#{role}] Tenanted connection pool reaped to limit total connection pools"
                ensure
                  POOL_REGISTRY_LOCK.synchronize { pool.retire_tenant_pool! }
                end

                true
              end
            ensure
              pool_config.mon_exit
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
