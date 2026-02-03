# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters
      # Module for database adapters that use a colocated multi-tenancy strategy.
      #
      # A "colocated" strategy means all tenants share a single database server resource,
      # but are isolated using database-level constructs:
      # - PostgreSQL schema strategy: All tenant schemas in one database
      # - Future: Other colocated strategies (e.g., row-level with tenant_id)
      module Colocated
        # Returns true to indicate this adapter uses a colocated strategy
        def colocated?
          true
        end

        # Create the colocated database that will contain all tenant data.
        # Must be implemented by the including adapter.
        def create_colocated_database
          raise NotImplementedError, "#{self.class.name} must implement #create_colocated_database"
        end

        # Drop the colocated database and all tenant data within it.
        # Must be implemented by the including adapter.
        def drop_colocated_database
          raise NotImplementedError, "#{self.class.name} must implement #drop_colocated_database"
        end
      end
    end
  end
end
