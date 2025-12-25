# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters
      module PostgreSQL
        # Factory for creating the appropriate PostgreSQL adapter based on strategy
        #
        # The strategy is inferred from the database name:
        # - If database name contains `%{tenant}` → "database" strategy
        # - Otherwise → "schema" strategy (colocated)
        #
        # Strategies:
        # - "schema" (default): Uses schema-based multi-tenancy
        # - "database": Uses database-based multi-tenancy
        class Factory
          def self.new(db_config)
            # Auto-detect strategy: if database name contains %{tenant}, use database strategy
            if db_config.database.include?("%{tenant}")
              Database.new(db_config)
            else
              Schema.new(db_config)
            end
          end
        end
      end
    end
  end
end
