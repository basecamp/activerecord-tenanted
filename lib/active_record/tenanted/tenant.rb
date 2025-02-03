# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module Tenant
      extend ActiveSupport::Concern

      # This is a sentinel value used to indicate that the class is not currently tenanted.
      #
      # It's the default value returned by `current_shard` when the class is not tenanted. The
      # `current_tenant` method's job is to recognizes that sentinel value and return `nil`, because
      # Active Record itself does not recognize `nil` as a valid shard value.
      UNTENANTED_SENTINEL = Object.new # :nodoc:

      included do
        connecting_to(shard: UNTENANTED_SENTINEL, role: ActiveRecord.writing_role)
      end

      class_methods do
        def current_tenant
          shard = current_shard
          shard != UNTENANTED_SENTINEL ? shard.to_s : nil
        end

        def while_tenanted(tenant_name, &block)
          connected_to(shard: tenant_name, role: ActiveRecord.writing_role) do
            prohibit_shard_swapping(true, &block)
          end
        end

        def connection_pool
          raise NoTenantError unless current_tenant
        end
      end
    end
  end
end
