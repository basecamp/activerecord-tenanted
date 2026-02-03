# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    #
    # If config.active_record_tenanted.connection_class is set, this middleware will be loaded
    # automatically, and will use config.active_record_tenanted.tenant_resolver to determine the
    # appropriate tenant for the request.
    #
    # If no tenant is resolved, the request will be executed without wrapping it in a tenanted
    # context. Application code will be free to set the tenant as needed.
    #
    # If a tenant is resolved and the tenant exists, the application will be locked to that
    # tenant's database for the duration of the request.
    #
    # If a tenant is resolved, but the tenant does not exist, a 404 response will be returned.
    #
    class TenantSelector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new(env)
        tenant_name = tenant_resolver&.call(request)

        if tenant_name.blank?
          # run the request without wrapping it in a tenanted context
          @app.call(env)
        elsif tenanted_class.tenant_exist?(tenant_name)
          tenanted_class.with_tenant(tenant_name) { @app.call(env) }
        else
          raise ActiveRecord::Tenanted::TenantDoesNotExistError, "Tenant not found: #{tenant_name.inspect}"
        end
      end

      def tenanted_class
        # Note: we'll probably want to cache this when we look at performance, but don't cache it
        # when class reloading is enabled.
        tenanted_class_name.constantize
      end

      def tenanted_class_name
        @tenanted_class_name ||= Rails.application.config.active_record_tenanted.connection_class
      end

      def tenant_resolver
        @tenanted_resolver ||= Rails.application.config.active_record_tenanted.tenant_resolver
      end
    end
  end
end
