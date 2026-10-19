# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters # :nodoc:
      class Base
        attr_reader :db_config

        def initialize(db_config)
          @db_config = db_config
        end

        # The Active Storage disk service interpolates the tenant name into a filesystem path, so a
        # valid name must be a single, safe path segment whatever the database allows.
        def valid_tenant_name?(tenant_name)
          raise NotImplementedError, "#{self.class.name} must implement valid_tenant_name?"
        end

        def validate_tenant_name(tenant_name)
          unless valid_tenant_name?(tenant_name)
            raise BadTenantNameError, "Invalid tenant name: #{tenant_name.inspect}"
          end
        end
      end
    end
  end
end
