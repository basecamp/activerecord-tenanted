# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module TenantPoolConfig # :nodoc:
      def pool
        return super unless db_config.is_a?(ActiveRecord::Tenanted::DatabaseConfigurations::TenantConfig)

        unless respond_to?(:synchronize) && defined?(ActiveRecord::Tenanted::TenantConnectionPool)
          raise ActiveRecord::Tenanted::TenantConfigurationError,
                "unsupported Active Record connection pool configuration"
        end

        @pool || synchronize { @pool ||= ActiveRecord::Tenanted::TenantConnectionPool.new(self) }
      end
    end
  end
end

ActiveRecord::ConnectionAdapters::PoolConfig.prepend(ActiveRecord::Tenanted::TenantPoolConfig)
