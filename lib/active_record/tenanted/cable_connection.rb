# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module CableConnection # :nodoc:
      # this module is included into ActionCable::Connection::Base
      module Base
        extend ActiveSupport::Concern

        prepended do
          identified_by :current_tenant
          around_command :with_tenant
        end

        def connect
          # If Rails had a before_connect hook, this could be moved there.
          set_current_tenant if connection_class && tenant_resolver
        end

        private
          def set_current_tenant
            tenant = tenant_resolver&.call(request)
            return if tenant.nil?

            if tenant.present? && connection_class.tenant_exist?(tenant)
              self.current_tenant = tenant
            else
              reject_unauthorized_connection
            end
          end

          def with_tenant(&block)
            if current_tenant.present?
              connection_class.with_tenant(current_tenant, &block)
            else
              yield
            end
          end

          def tenant_resolver
            @tenant_resolver ||= Rails.application.config.active_record_tenanted.tenant_resolver
          end

          def connection_class
            # TODO: cache this / speed this up
            Rails.application.config.active_record_tenanted.connection_class&.constantize
          end
      end
    end
  end
end
