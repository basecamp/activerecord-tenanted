# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module CrossTenantAssociations
      extend ActiveSupport::Concern

      class_methods do
        def has_one(name, scope = nil, **options)
          enhanced_scope = enhance_cross_tenant_association(name, scope, options, :has_one)
          super(name, enhanced_scope, **options)
        end

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
    end
  end
end
