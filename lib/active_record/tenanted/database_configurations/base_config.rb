# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseConfigurations
      class BaseConfig < ActiveRecord::DatabaseConfigurations::HashConfig
        DEFAULT_MAX_CONNECTION_POOLS = 50

        attr_accessor :test_worker_id

        def initialize(...)
          super
          max_connection_pools
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

          db
        end

        def tenants
          config_adapter.tenant_databases
        end

        def new_tenant_config(tenant_name)
          config_name = "#{name}_#{tenant_name}"
          config_hash = configuration_hash.dup.tap do |hash|
            hash[:tenant] = tenant_name
            hash[:database] = database_for(tenant_name)
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
          maximum = configuration_hash.fetch(:max_connection_pools, DEFAULT_MAX_CONNECTION_POOLS)
          maximum = DEFAULT_MAX_CONNECTION_POOLS if maximum.nil?
          return maximum if maximum.is_a?(Integer) && maximum.positive?

          raise TenantConfigurationError, "max_connection_pools must be a positive integer"
        end
      end
    end
  end
end
