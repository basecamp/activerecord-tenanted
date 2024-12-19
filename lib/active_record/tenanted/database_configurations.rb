# frozen_string_literal: true

require "active_record/database_configurations"

module ActiveRecord
  module Tenanted
    module DatabaseConfigurations
      class TemplateConfig < ActiveRecord::DatabaseConfigurations::HashConfig
        def database_tasks?
          false
        end

        def database_path_for(tenant_name)
          tenant_hash = Digest::MD5.hexdigest(tenant_name.to_s).chars.each_slice(2).take(4).map(&:join)
          format_specifiers = {
            tenant: tenant_name,
            tenant_hash1: tenant_hash[0], # 255
            tenant_hash2: File.join(tenant_hash[0..1]), # x 255 = 64 thousand
            tenant_hash3: File.join(tenant_hash[0..2]), # x 255 = 16 million
            tenant_hash4: File.join(tenant_hash[0..3])  # x 255 = 4.2 billion
          }
          database % format_specifiers
        end

        def new_connection
          raise ConfigurationError, "Tenant template config cannot be used to create a connection. If you have a model that inherits directly from ActiveRecord::Base, make sure to use 'tenanted_with'."
        end
      end

      class TenantConfig < ActiveRecord::DatabaseConfigurations::HashConfig
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
          tenant_tag = " [tenant=#{tenant}]"
          conn.instance_eval <<~CODE, __FILE__, __LINE__ + 1
            def log(sql, name = "SQL", binds = [], type_casted_binds = [], async: false, &block)
              name ||= ""
              name += "#{tenant_tag}"
              super(sql, name, binds, type_casted_binds, async: async, &block)
            end
          CODE
          conn
        end
      end
    end
  end
end
