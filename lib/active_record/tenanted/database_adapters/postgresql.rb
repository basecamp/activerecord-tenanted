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
      # - Schema-based (preferred): Multiple schemas within a single database
      # - Database-based (default): Separate databases per tenant
      module PostgreSQL
      end
    end
  end
end
