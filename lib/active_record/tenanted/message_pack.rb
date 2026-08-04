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
            has_tenant = attributes_hash.key?("tenant")
            tenant_name = attributes_hash.delete("tenant")

            super.tap do |record|
              record.instance_variable_set(:@tenant, tenant_name) if has_tenant
            end
          else
            super
          end
        end
      end
    end
  end
end
