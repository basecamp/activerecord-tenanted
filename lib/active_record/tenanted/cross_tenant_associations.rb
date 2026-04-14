# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module CrossTenantAssociations
      extend ActiveSupport::Concern

      class_methods do
        def has_one(name, scope = nil, **options)
          define_enhanced_association(:has_one, name, scope, **options)
        end

        def has_many(name, scope = nil, **options)
          define_enhanced_association(:has_many, name, scope, **options)
        end

        private
          # For now association methods are identical
          def define_enhanced_association(association_type, name, scope, **options)
            tenant_key = options.delete(:tenant_key)
            custom_options = { tenant_key: tenant_key || :tenant_id }

            enhanced_scope = enhance_cross_tenant_association(name, scope, custom_options)
            method(association_type).super_method.call(name, enhanced_scope, **options)
          end

          def enhance_cross_tenant_association(name, scope, options)
            target_class = options[:class_name]&.safe_constantize || name.to_s.classify.safe_constantize

            return scope unless target_class

            unless target_class.tenanted?
              tenant_key = options[:tenant_key]

              return ->(record) {
                base_scope = scope ? target_class.instance_exec(&scope) : target_class.all
                base_scope.where(tenant_key => record.tenant)
              }
            end

            scope
          end
      end
    end
  end
end
