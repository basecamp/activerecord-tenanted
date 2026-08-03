# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    # Tenant context is checked when an association reads or writes the database, and not when the
    # Association object is created. Serializers create associations to dump and restore their
    # targets without ever going near a connection, and must not be tripped up by the check.
    #
    # `klass` is resolved at both of these seams, so a polymorphic association is checked against
    # the class it actually points at rather than being presumed tenanted.
    module Associations # :nodoc:
      # Every query built on behalf of an association funnels through here, including the ones
      # issued by a collection proxy that has outlived the tenant context it was created in.
      def scope
        ensure_owner_tenant_context_safety
        super
      end

      private
        # Called by the collection and singular association readers, so that the exception is
        # raised at the call site that made the mistake and not at the eventual query.
        def ensure_klass_exists!
          super
          ensure_owner_tenant_context_safety
        end

        def ensure_owner_tenant_context_safety
          owner.ensure_tenant_context_safety if owner.class.tenanted? && klass&.tenanted?
        end
    end
  end
end
