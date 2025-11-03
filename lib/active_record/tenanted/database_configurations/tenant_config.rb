# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseConfigurations
      class TenantConfig < ActiveRecord::DatabaseConfigurations::HashConfig
        def initialize(...)
          super
          @config_adapter = nil
        end

        def tenant
          configuration_hash.fetch(:tenant)
        end

        def database
          configuration_hash.fetch(:database)
        end

        def configuration_hash
          hash = super
          if hash[:database]&.include?("%{tenant}")
            hash = hash.dup
            tenant_name = hash.fetch(:tenant)
            hash[:database] = sprintf(hash[:database], tenant: tenant_name)
          end
          hash
        end

        def config_adapter
          @config_adapter ||= ActiveRecord::Tenanted::DatabaseAdapter.new(self)
        end

        def new_connection
          # TODO: This line can be removed once rails/rails@f1f60dc1 is in a released version of
          # Rails, and this gem's dependency has been bumped to require that version or later.
          config_adapter.ensure_database_directory_exists

          super.tap { |connection| connection.tenant = tenant }
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

        def default_schema_cache_path(db_dir = "db")
          if primary?
            super
          else
            File.join(db_dir, "#{tenanted_config_name}_schema_cache.yml")
          end
        end
      end
    end
  end
end
