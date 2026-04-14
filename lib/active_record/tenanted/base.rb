# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module Base
      extend ActiveSupport::Concern

      class_methods do
        def initialize(...)
          super
        end

        def tenanted(config_name = "primary")
          raise Error, "Class #{self} is already tenanted" if tenanted?
          raise Error, "Class #{self} is not an abstract connection class" unless abstract_class?

          prepend Tenant

          self.connection_class = true
          self.tenanted_config_name = config_name

          unless tenanted_root_config.configuration_hash[:tenanted]
            raise Error, "The '#{tenanted_config_name}' database is not configured as tenanted."
          end
        end

        def subtenant_of(class_name)
          prepend Subtenant

          self.tenanted_subtenant_of_klass_name = class_name
        end

        def tenanted?
          false
        end

        def belongs_to(name, scope = nil, **options)
          tenant_key = options.delete(:tenant_key)
          super(name, scope, **options)

          if tenant_key
            define_method("#{name}=") do |value|
              super(value)
              if value.respond_to?(:tenant)
                self.send("#{tenant_key}=", value.tenant)
              end
            end

            unless tenanted?
              define_method(name) do
                tenant_value = send(tenant_key)
                return nil unless tenant_value
                target_klass = self.class.reflect_on_association(name).klass
                if target_klass.tenanted?
                  tenant_klass = if target_klass.respond_to?(:with_tenant)
                    target_klass
                  else
                    target_klass.tenanted_subtenant_of
                  end

                  tenant_klass.prohibit_shard_swapping(false) do
                    tenant_klass.with_tenant(tenant_value) { super() }
                  end
                else
                  super()
                end
              end
            end
          end
        end

        def table_exists?
          super
        rescue ActiveRecord::Tenanted::NoTenantError
          # If this exception was raised, then Rails is trying to determine if a non-tenanted
          # table exists by accessing the tenanted primary database config, probably during eager
          # loading.
          #
          # This happens for Record classes that late-bind to their database, like
          # SolidCable::Record, SolidQueue::Record, and SolidCache::Record (all of which inherit
          # directly from ActiveRecord::Base but call `connects_to` to set their database later,
          # during initialization).
          #
          # In non-tenanted apps, this method just returns false during eager loading. So let's
          # follow suit. Rails will figure it out later.
          false
        end
      end

      def tenanted?
        false
      end
    end
  end
end
