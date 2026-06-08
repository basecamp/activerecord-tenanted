# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module Storage # :nodoc:
      module DiskService
        def root
          if klass = ActiveRecord::Tenanted.connection_class
            unless tenant = klass.current_tenant
              raise NoTenantError, "Cannot access Active Storage Disk service without a tenant"
            end

            sprintf(@root, tenant: tenant)
          else
            super
          end
        end

        def path_for(key)
          return super unless ActiveRecord::Tenanted.connection_class && key.include?("/")

          if key.split("/").intersect?(%w[. ..])
            raise ActiveStorage::InvalidKeyError, "key has path traversal segments"
          end

          tenant, key = key.split("/", 2)

          if tenant.blank? || key.blank?
            raise ActiveStorage::InvalidKeyError, "key has a blank segment"
          end

          begin
            path = File.expand_path(File.join(root, tenant, folder_for(key), key))
          rescue ArgumentError
            raise ActiveStorage::InvalidKeyError, "key is an invalid string"
          end

          unless path.start_with?(File.expand_path(root) + "/")
            raise ActiveStorage::InvalidKeyError, "key is outside of disk service root"
          end

          path
        rescue Encoding::CompatibilityError
          raise ActiveStorage::InvalidKeyError, "key has incompatible encoding"
        end
      end

      module Blob
        def key
          self[:key] ||= if klass = ActiveRecord::Tenanted.connection_class
            unless tenant = klass.current_tenant
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
