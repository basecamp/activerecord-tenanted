# frozen_string_literal: true

require "active_record/database_configurations"

module ActiveRecord
  module Tenanted
    module DatabaseConfigurations
      class TemplateConfig < ActiveRecord::DatabaseConfigurations::HashConfig
        def database_tasks?
          false
        end
      end

      class TenantConfig < TemplateConfig
        def tenant
          configuration_hash.fetch(:tenant)
        end

        def tenanted_config_name
          configuration_hash.fetch(:tenanted_config_name)
        end

        def primary?
          ActiveRecord::Base.configurations.primary?(tenanted_config_name)
        end

        def schema_dump(format = ActiveRecord.schema_format)
          if configuration_hash.key?(:schema_dump) || primary?
            super
          else
            "#{tenanted_config_name}_#{schema_file_type(format)}"
          end
        end

        def new_connection
          conn = super
          log_addition = " [tenant=#{tenant}]"
          conn.instance_eval <<~CODE, __FILE__, __LINE__ + 1
            def log(sql, name = "SQL", binds = [], type_casted_binds = [], async: false, &block)
              name ||= ""
              name += "#{log_addition}"
              super(sql, name, binds, type_casted_binds, async: async, &block)
            end
          CODE
          conn
        end
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::DatabaseConfigurations.register_db_config_handler do |env_name, name, _, config|
    next unless config.fetch(:tenanted, false)
    ActiveRecord::Tenanted::DatabaseConfigurations::TemplateConfig.new(env_name, name, config)
  end
end
