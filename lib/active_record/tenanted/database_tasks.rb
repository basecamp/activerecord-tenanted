# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseTasks # :nodoc:
      extend self

      def migrate_all
        raise ArgumentError, "Could not find a tenanted database" unless root_config = root_database_config

        tenants = root_config.tenants.presence || [ get_current_tenant ].compact
        tenants.each do |tenant|
          tenant_config = root_config.new_tenant_config(tenant)
          migrate(tenant_config)
        end
      end

      def migrate_tenant(tenant_name = set_current_tenant)
        raise ArgumentError, "Could not find a tenanted database" unless root_config = root_database_config

        tenant_config = root_config.new_tenant_config(tenant_name)

        migrate(tenant_config)
      end

      def drop_all
        raise ArgumentError, "Could not find a tenanted database" unless root_config = root_database_config

        root_config.tenants.each do |tenant|
          root_config.database_path_for(tenant).tap do |path|
            db_config = root_config.new_tenant_config(tenant)
            ActiveRecord::Tenanted::DatabaseAdapter.drop_database(db_config)
            $stdout.puts "Dropped database '#{path}'" if verbose?
          end
        end
      end

      def root_database_config
        db_configs = ActiveRecord::Base.configurations.configs_for(
          env_name: ActiveRecord::Tasks::DatabaseTasks.env,
          include_hidden: true
        )
        db_configs.detect { |c| c.configuration_hash[:tenanted] }
      end

      def get_current_tenant
        tenant = ENV["ARTENANT"]

        if tenant.present?
          $stdout.puts "Setting current tenant to #{tenant.inspect}" if verbose?
        elsif Rails.env.local?
          tenant = Rails.application.config.active_record_tenanted.default_tenant
          $stdout.puts "Defaulting current tenant to #{tenant.inspect}" if verbose?
        else
          tenant = nil
          $stdout.puts "Cannot determine an implicit tenant: ARTENANT not set, and Rails.env is not local." if verbose?
        end

        tenant
      end

      def set_current_tenant
        unless (connection_class = ActiveRecord::Tenanted.connection_class)
          raise ActiveRecord::Tenanted::IntegrationNotConfiguredError,
                "ActiveRecord::Tenanted integration is not configured via connection_class"
        end

        if connection_class.current_tenant.nil?
          connection_class.current_tenant = get_current_tenant
        else
          connection_class.current_tenant
        end
      end

      # This is essentially a simplified implementation of ActiveRecord::Tasks::DatabaseTasks.migrate
      def migrate(config)
        ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
          pool = conn.pool

          # initialize_database
          unless pool.schema_migration.table_exists?
            schema_dump_path = ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(config)
            if schema_dump_path && File.exist?(schema_dump_path)
              ActiveRecord::Tasks::DatabaseTasks.load_schema(config)
            end
            # TODO: emit a "Created database" message once we sort out implicit creation
          end

          # migrate
          migrated = false
          if pool.migration_context.pending_migration_versions.present?
            pool.migration_context.migrate(nil)
            pool.schema_cache.clear!
            migrated = true
          end

          # dump the schema and schema cache
          if Rails.env.development? || ENV["ARTENANT_SCHEMA_DUMP"].present?
            if migrated
              ActiveRecord::Tasks::DatabaseTasks.dump_schema(config)
            end

            cache_dump = ActiveRecord::Tasks::DatabaseTasks.cache_dump_filename(config)
            if migrated || !File.exist?(cache_dump)
              ActiveRecord::Tasks::DatabaseTasks.dump_schema_cache(pool, cache_dump)
            end
          end
        end
      end

      def verbose?
        ActiveRecord::Tasks::DatabaseTasks.send(:verbose?)
      end
    end
  end
end
