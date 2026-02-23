# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseConfigurations
      class BaseConfig < ActiveRecord::DatabaseConfigurations::HashConfig
        DEFAULT_MAX_CONNECTION_POOLS = 50

        attr_accessor :test_worker_id

        def initialize(...)
          super
          @test_worker_id = nil
          @config_adapter = nil
        end

        def config_adapter
          @config_adapter ||= ActiveRecord::Tenanted::DatabaseAdapter.new(self)
        end

        def database_tasks?
          false
        end

        def database_for(tenant_name)
          tenant_name = tenant_name.to_s

          config_adapter.validate_tenant_name(tenant_name)

          db = sprintf(database, tenant: tenant_name)

          if test_worker_id
            db = config_adapter.test_workerize(db, test_worker_id)
          end

          if %w[mysql2 trilogy].include?(adapter) && db.length > 64
            raise BadTenantNameError, "Database name too long (max 64 characters): #{db.inspect}"
          end

          db
        end

        def host_for(tenant_name)
          return unless host

          sprintf(host, tenant: tenant_name.to_s)
        end

        def tenants
          config_adapter.tenant_databases
        end

        def new_tenant_config(tenant_name)
          config_name = "#{name}_#{tenant_name}"
          config_hash = configuration_hash.dup.tap do |hash|
            hash[:tenant] = tenant_name
            hash[:database] = database_for(tenant_name)
            hash[:host] = host_for(tenant_name) if configuration_hash.key?(:host)
            hash[:tenanted_config_name] = name
          end
          Tenanted::DatabaseConfigurations::TenantConfig.new(env_name, config_name, config_hash)
        end

        def new_connection
          raise NoTenantError, "Cannot use an untenanted ActiveRecord::Base connection. " \
                               "If you have a model that inherits directly from ActiveRecord::Base, " \
                               "make sure to use 'subtenant_of'. In development, you may see this error " \
                               "if constant reloading is not being done properly."
        end

        def max_connection_pools
          (configuration_hash[:max_connection_pools] || DEFAULT_MAX_CONNECTION_POOLS).to_i
        end

        def shared_pool?
          configuration_hash[:shared_pool] == true
        end

        def fallback_database
          configuration_hash[:untenanted_database].presence
        end

        def build_shared_pool_config(connection_class_name:)
          validate_shared_pool

          hash = configuration_hash.merge(
            database: fallback_database,
            tenanted_connection_class_name: connection_class_name,
            tenanted_config_name: name
          )

          ActiveRecord::DatabaseConfigurations::HashConfig.new(env_name, "#{name}_shared_pool", hash)
        end

        def validate_shared_pool
          return unless shared_pool?

          unless %w[mysql2 trilogy].include?(adapter)
            raise ActiveRecord::Tenanted::TenantConfigurationError,
              "Shared pool mode requires the mysql2 or trilogy adapter, " \
              "but #{name.inspect} is configured with #{adapter.inspect}."
          end

          if fallback_database.blank?
            raise ActiveRecord::Tenanted::TenantConfigurationError,
              "Shared pool mode requires an untenanted_database to be configured " \
              "for #{name.inspect}."
          end

          if configuration_hash[:host]&.include?("%{tenant}")
            raise ActiveRecord::Tenanted::TenantConfigurationError,
              "Shared pool mode does not support host templating " \
              "because a single pool implies a single host (config #{name.inspect})."
          end

          if configuration_hash[:prepared_statements] == true
            raise ActiveRecord::Tenanted::TenantConfigurationError,
              "Shared pool mode does not support prepared statements " \
              "for #{name.inspect}. Set prepared_statements to false."
          end
        end
      end
    end
  end
end
