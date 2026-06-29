# frozen_string_literal: true

require "globalid"

module ActiveRecord
  module Tenanted
    module GlobalId
      def tenant
        params && params[:tenant]
      end

      class Locator < ::GlobalID::Locator::BaseLocator
        def model_class(gid)
          gid.model_name.constantize
        end

        def locate(gid, options = {})
          ensure_tenant_context_safety(gid, gid.model_class)
          super(gid)
        end

        def locate_many(gids, options = {})
          gids.each { |gid| ensure_tenant_context_safety(gid, gid.model_class) }
          super
        end

        private
          def ensure_tenant_context_safety(gid, gid_model_class)
            return unless gid_model_class.tenanted?

            gid_tenant = gid.tenant
            raise MissingTenantError, "Tenant not present in #{gid.to_s.inspect}" unless gid_tenant

            current_tenant = gid_model_class.current_tenant.presence
            raise NoTenantError, "Cannot connect to a tenanted database while untenanted (#{gid})" unless current_tenant

            if gid_tenant != current_tenant
              raise WrongTenantError, "GlobalID #{gid.to_s.inspect} does not belong the current tenant #{current_tenant.inspect}"
            end
          end
      end
    end
  end
end
