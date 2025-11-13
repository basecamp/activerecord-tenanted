# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module Storage # :nodoc:
      module DiskService
        def root
          if klass = ActiveRecord::Tenanted.connection_class
            tenant = klass.current_tenant
            allow_untenanted = Rails.application.config.active_record_tenanted.allow_untenanted_active_storage

            if tenant.nil?
              return super if allow_untenanted

              raise NoTenantError, "Cannot access Active Storage Disk service without a tenant"
            end

            sprintf(@root, tenant: tenant)
          else
            super
          end
        end

        def path_for(key)
          if ActiveRecord::Tenanted.connection_class
            if key.include?("/")
              tenant, key = key.split("/", 2)
              File.join(root, tenant, folder_for(key), key)
            else
              super
            end
          else
            super
          end
        end
      end

      module Blob
        def key
          self[:key] ||= if klass = ActiveRecord::Tenanted.connection_class
            tenant = klass.current_tenant
            allow_untenanted = Rails.application.config.active_record_tenanted.allow_untenanted_active_storage

            if tenant.nil?
              return super if allow_untenanted

              raise NoTenantError, "Cannot generate a Blob key without a tenant"
            end

            token = self.class.generate_unique_secure_token(length: ActiveStorage::Blob::MINIMUM_TOKEN_LENGTH)
            [ tenant, token ].join("/")
          else
            super
          end
        end
      end
    end
  end
end
