# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module CrossTenantAssociations
      extend ActiveSupport::Concern

      class_methods do
        # I think we can have more configs later
        def cross_tenant_config(**config)
          @cross_tenant_config = config
        end

        def get_cross_tenant_config
          @cross_tenant_config ||= {}
        end

        def has_one(name, scope = nil, **options)
          define_enhanced_association(:has_one, name, scope, **options)
        end

        def has_many(name, scope = nil, **options)
          define_enhanced_association(:has_many, name, scope, **options)
        end

        private
          # For now association methods are identical
          def define_enhanced_association(association_type, name, scope, **options)
            config = get_cross_tenant_config
            tenant_column = config[:tenant_column] || :tenant_id
            custom_options = options.merge(tenant_column: tenant_column)

            enhanced_scope = enhance_cross_tenant_association(name, scope, custom_options)
            method(association_type).super_method.call(name, enhanced_scope, **options)
          end

          def enhance_cross_tenant_association(name, scope, options)
            begin
              target_class = options[:class_name]&.constantize || name.to_s.classify.constantize
            rescue NameError
              # Class not yet loaded during Rails initialization, skip enhancement
              return scope
            end

            unless target_class.tenanted?
              tenant_column = options[:tenant_column]

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
