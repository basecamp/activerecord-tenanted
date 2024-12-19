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
        slug = ::Tenant.extract_slug(request)

        if slug.blank?
          ::Tenant.while_untenanted do
            @app.call(env)
          end
        elsif ::Tenant.exist?(slug)
          ::Tenant.connected_to(slug) do
            @app.call(env)
          end
        else
          Rails.logger.info("ActiveRecord::Tenanted::TenantSelector: Tenant not found for slug #{slug.inspect}")
          Rack::NotFound.new("public/404.html").call(env)
        end
      end
    end
  end
end
