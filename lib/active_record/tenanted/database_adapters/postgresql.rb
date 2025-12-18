# frozen_string_literal: true

require_relative "postgresql/base"
require_relative "postgresql/schema"
require_relative "postgresql/database"
require_relative "postgresql/factory"

module ActiveRecord
  module Tenanted
    module DatabaseAdapters
      # PostgreSQL adapter support for multi-tenancy
      #
      # Supports two strategies:
      # - Schema-based (default): Multiple schemas within a single database
      # - Database-based: Separate databases per tenant
      #
      # Configure strategy in database.yml:
      #   postgresql_strategy: schema  # or "database"
      module PostgreSQL
      end
    end
  end
end
