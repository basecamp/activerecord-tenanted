# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module MessagePack # :nodoc:
      # This patch sees every record in a payload, unlike the Marshal, YAML, and JSON hooks, which
      # are methods on the record and so only ever run for tenanted models.
      module Decoder
        def build_record(entry)
          class_name, attributes_hash, * = entry

          if ActiveSupport::MessagePack::Extensions.load_class(class_name).tenanted?
            tenant_name = attributes_hash.delete("tenant")

            super.tap do |record|
              record.instance_variable_set(:@tenant, tenant_name) if tenant_name
            end
          else
            super
          end
        end
      end
    end
  end
end
