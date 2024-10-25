# frozen_string_literal: true

require_relative "tenanted/version"
require_relative "tenanted/database_configurations"
require_relative "tenanted/patches"

module ActiveRecord
  module Tenanted
    # mixed into ActiveRecord::Base when the gem is loaded
    module Stub
      def initialize(...)
        super

        @tenant_config_name = nil
      end

      def tenanted(tenant_config_name = "primary")
        extend Base

        @tenant_config_name = tenant_config_name

        self.connection_class = true
      end
    end

    # mixed into an Active Record class when `tenanted` is called
    module Base
      def tenant_config_name
        @tenant_config_name ||= (superclass.respond_to?(:tenant_config_name) ? superclass.tenant_config_name : nil)
      end

      def connection_pool
        pool = connection_handler.retrieve_connection_pool(connection_specification_name, role: current_role, shard: current_shard, strict: false)

        if pool.nil?
          create_tenanted_pool
          pool = connection_handler.retrieve_connection_pool(connection_specification_name, role: current_role, shard: current_shard, strict: true)
        end

        pool
      end

      def create_tenanted_pool
        base_config = ActiveRecord::Base.configurations.resolve(tenant_config_name.to_sym)

        tenant_name = "#{tenant_config_name}_#{current_shard}"
        config_hash = base_config.configuration_hash.dup
        config_hash[:database] = config_hash[:database] % { tenant: current_shard }
        config_hash[:tenant_config_name] = tenant_config_name
        config_hash[:tenant] = current_shard
        config = Tenanted::DatabaseConfigurations::TenantConfig.new(base_config.env_name, tenant_name, config_hash)

        establish_connection(config)
        ensure_schema_migrations(config)
      end

      def ensure_schema_migrations(config)
        ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
          pool = conn.pool
          unless pool.schema_migration.table_exists?
            if File.exist?(ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(config))
              ActiveRecord::Tasks::DatabaseTasks.load_schema(config)
            end
          end

          if pool.migration_context.pending_migration_versions.present?
            ActiveRecord::Tasks::DatabaseTasks.migrate(nil)
            ActiveRecord::Tasks::DatabaseTasks.dump_schema(config) if Rails.env.development?
          end
        end
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  extend ActiveRecord::Tenanted::Stub
end
