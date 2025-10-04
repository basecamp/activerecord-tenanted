# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module Subtenant
      extend ActiveSupport::Concern

      class_methods do
        include CrossTenantAssociations::ClassMethods

        def tenanted?
          true
        end

        def tenanted_subtenant_of
          # TODO: cache this / speed this up
          klass = tenanted_subtenant_of_klass_name&.constantize

          raise Error, "Class #{klass} is not tenanted" unless klass.tenanted?
          raise Error, "Class #{klass} is not a connection class" unless klass.abstract_class?

          klass
        end

        delegate :current_tenant, :connection_pool, to: :tenanted_subtenant_of
      end

      prepended do
        prepend TenantCommon

        cattr_accessor :tenanted_subtenant_of_klass_name
      end

      def tenanted?
        true
      end
    end
  end
end
