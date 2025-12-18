# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapter # :nodoc:
      # Hash of registered database configuration adapters
      @adapters = {}

      class << self
        def register(name, class_name)
          @adapters[name.to_s] = class_name
        end

        def new(db_config)
          adapter_class_name = @adapters[db_config.adapter]

          if adapter_class_name.nil?
            raise ActiveRecord::Tenanted::UnsupportedDatabaseError,
                  "Unsupported database adapter for tenanting: #{db_config.adapter}. " \
                  "Supported adapters: #{@adapters.keys.join(', ')}"
          end

          adapter_class_name.constantize.new(db_config)
        end
      end

      register "sqlite3", "ActiveRecord::Tenanted::DatabaseAdapters::SQLite"
      register "trilogy", "ActiveRecord::Tenanted::DatabaseAdapters::MySQL"
      register "mysql2", "ActiveRecord::Tenanted::DatabaseAdapters::MySQL"
      register "postgresql", "ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL"
    end
  end
end
