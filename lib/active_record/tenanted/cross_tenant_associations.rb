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
            class_name = options[:class_name]
            enhanced_scope = enhance_cross_tenant_association(name, scope, tenant_key: tenant_key || :tenant_id, class_name: class_name)
            method(association_type).super_method.call(name, enhanced_scope, **options)
          end

          def enhance_cross_tenant_association(name, scope, tenant_key:, class_name: nil)
            resolved_class_name = class_name || name.to_s.classify

            ->(record) {
              target_class = resolved_class_name.constantize
              base_scope = scope ? target_class.instance_exec(&scope) : target_class.all

              if target_class.tenanted?
                base_scope
              else
                base_scope.where(tenant_key => record.tenant)
              end
            }
          end
      end
    end
  end
end
