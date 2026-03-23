# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module Patches
      # TODO: I think this is needed because there was no followup to rails/rails#46270.
      # See rails/rails@901828f2 from that PR for background.
      module DatabaseTasks
        private
          def with_temporary_pool(db_config, clobber: false)
            original_db_config = begin
              migration_class.connection_db_config
            rescue ActiveRecord::ConnectionNotDefined
              nil
            end

            begin
              pool = migration_class.connection_handler.establish_connection(db_config, clobber: clobber)

              yield pool
            ensure
              migration_class.connection_handler.establish_connection(original_db_config, clobber: clobber) if original_db_config
            end
          end
      end

      # This patch is only applied for Rails 8.1.x. Rails 8.2+ removed the with_connection
      # call in _default_attributes (rails/rails#54333), making this patch unnecessary.
      # See railtie.rb for the version check.
      module Attributes
        extend ActiveSupport::Concern

        class_methods do
          def _default_attributes # :nodoc:
            @default_attributes ||= begin
              # I've removed the `with_connection` block here.
              nil_connection = nil
              attributes_hash = columns_hash.transform_values do |column|
                ActiveModel::Attribute.from_database(column.name, column.default, type_for_column(nil_connection, column))
              end

              attribute_set = ActiveModel::AttributeSet.new(attributes_hash)
              apply_pending_attribute_modifications(attribute_set)
              attribute_set
            end
          end
        end
      end
    end
  end
end
