# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module Subtenant
      extend ActiveSupport::Concern

      class_methods do
        def has_one(name, scope = nil, **options)
          enhanced_scope = enhance_cross_tenant_association(name, scope, options, :has_one)
          super(name, enhanced_scope, **options)
        end

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

        private

        def enhance_cross_tenant_association(name, scope, options, association_type)
          target_class = options[:class_name]&.constantize || name.to_s.classify.constantize

          unless target_class.tenanted?
            tenant_column = options[:tenant_column] || :tenant_id

            return ->(record) {
              base_scope = scope ? target_class.instance_exec(&scope) : target_class.all
              base_scope.where(tenant_column => record.tenant)
            }
          end

          scope
        end
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
