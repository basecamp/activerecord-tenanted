# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    class DatabaseAdapter # :nodoc:
      ADAPTERS = {
        "sqlite3" => "ActiveRecord::Tenanted::DatabaseAdapters::SQLite",
        "beamer" => "Beamer::ConnectionAdapter",
      }.freeze

      class << self
        def new(db_config)
          adapter_class_name = ADAPTERS[db_config.adapter]

          if adapter_class_name.nil?
            raise ActiveRecord::Tenanted::UnsupportedDatabaseError,
                  "Unsupported database adapter for tenanting: #{db_config.adapter}. " \
                  "Supported adapters: #{ADAPTERS.keys.join(', ')}"
          end

          adapter_class_name.constantize.new(db_config)
        end
      end
    end
  end
end
