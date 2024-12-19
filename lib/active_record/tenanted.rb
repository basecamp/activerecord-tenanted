# frozen_string_literal: true

require "active_record/tasks/database_tasks"

require_relative "tenanted/version"
require_relative "tenanted/railtie"
require_relative "tenanted/database_configurations"
require_relative "tenanted/tenant"
require_relative "tenanted/tenant_selector"
require_relative "tenanted/patches"

module ActiveRecord
  module Tenanted
    class NoCurrentTenantError < StandardError; end
    class TenantAlreadyExistsError < StandardError; end

    PROTOSHARD = :__protoshard__

    # mixed into ActiveRecord::Base when the gem is loaded
    module Stub
      def initialize(...)
        super

        @tenanted_config_name = nil
        @tenanted_with_class_name = nil
      end

      def tenanted(config_name = "primary")
        extend Base

        @tenanted_config_name = config_name
        self.connection_class = true
      end

      def tenanted_with(class_name)
        extend Sharer

        @tenanted_with_class_name = class_name
      end
    end

    # mixed into an Active Record class when `tenanted` is called
    module Base
      def tenanted_config_name
        @tenanted_config_name ||= (superclass.respond_to?(:tenanted_config_name) ? superclass.tenanted_config_name : nil)
      end

      def connection_pool
        raise NoCurrentTenantError if current_shard == PROTOSHARD && current_role != ActiveRecord.reading_role

        pool = connection_handler.retrieve_connection_pool(connection_specification_name, role: current_role, shard: current_shard, strict: false)

        if pool.nil?
          create_tenanted_pool
          pool = connection_handler.retrieve_connection_pool(connection_specification_name, role: current_role, shard: current_shard, strict: true)
        end

        pool
      end

      def create_tenanted_pool # :nodoc:
        # ensure all classes use the same connection pool
        return superclass.create_tenanted_pool unless connection_class?

        base_config = ActiveRecord::Base.configurations.resolve(tenanted_config_name.to_sym)

        tenant_shard = current_shard
        tenant_name = "#{tenanted_config_name}_#{tenant_shard}"

        config_hash = base_config.configuration_hash.dup
        config_hash[:database] = base_config.database_path_for(tenant_shard)
        config_hash[:tenanted_config_name] = tenanted_config_name
        config_hash[:tenant] = current_shard
        config = Tenanted::DatabaseConfigurations::TenantConfig.new(base_config.env_name, tenant_name, config_hash)

        establish_connection(config)
        ensure_schema_migrations(config)
      end

      def ensure_schema_migrations(config) # :nodoc:
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

    module Sharer
      def tenanted_with_class
        @tenanted_with_class ||= @tenanted_with_class_name&.constantize || superclass.tenanted_with_class
      end

      def connection_pool
        tenanted_with_class.connection_pool
      end
    end
  end
end
