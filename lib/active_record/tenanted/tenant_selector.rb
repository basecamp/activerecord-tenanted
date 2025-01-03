# frozen_string_literal: true

require "rack/contrib"

module ActiveRecord
  module Tenanted
    class TenantSelector
      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new(env)
        tenant_name = ActiveRecord::Tenanted::Tenant.requested_tenant(request)

        if tenant_name.blank?
          ActiveRecord::Tenanted::Tenant.while_untenanted do
            @app.call(env)
          end
        elsif ActiveRecord::Tenanted::Tenant.exist?(tenant_name)
          ActiveRecord::Tenanted::Tenant.while_tenanted(tenant_name) do
            @app.call(env)
          end
        else
          Rails.logger.info("ActiveRecord::Tenanted::TenantSelector: Tenant not found: #{tenant_name.inspect}")
          Rack::NotFound.new("public/404.html").call(env)
        end
      end
    end
  end
end
