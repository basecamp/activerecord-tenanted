# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters
      module PostgreSQL
        # Factory for creating the appropriate PostgreSQL adapter based on strategy
        #
        # The strategy is determined by the presence of
        # `schema_name_pattern` → "schema" strategy (colocated)
        #
        # Strategies:
        # - "schema" (default): Uses schema-based multi-tenancy
        # - "database": Uses database-based multi-tenancy
        class Factory
          def self.new(db_config)
            # Auto-detect strategy: if schema_name_pattern is present
            if db_config.configuration_hash[:schema_name_pattern]
              Schema.new(db_config)
            else
              Database.new(db_config)
            end
          end
        end
      end
    end
  end
end
