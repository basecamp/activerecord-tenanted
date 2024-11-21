# frozen_string_literal: true

require "active_record/tasks/database_tasks"

require_relative "tenanted/version"
require_relative "tenanted/database_configurations"
require_relative "tenanted/patches"

module ActiveRecord
  module Tenanted
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

        tenant_hash = Digest::MD5.hexdigest(tenant_shard.to_s).chars.each_slice(2).take(4).map(&:join)
        format_specifiers = {
          tenant: tenant_shard,
          tenant_hash1: tenant_hash[0], # 255
          tenant_hash2: File.join(tenant_hash[0..1]), # x 255 = 64 thousand
          tenant_hash3: File.join(tenant_hash[0..2]), # x 255 = 16 million
          tenant_hash4: File.join(tenant_hash[0..3])  # x 255 = 4.2 billion
        }

        config_hash = base_config.configuration_hash.dup
        config_hash[:database] = config_hash[:database] % format_specifiers
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
        @tenanted_with_class ||= (@tenanted_with_class_name.present? ? Object.const_get(@tenanted_with_class_name) : superclass.tenanted_with_class)
      end

      def connection_pool
        tenanted_with_class.connection_pool
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  extend ActiveRecord::Tenanted::Stub
end
