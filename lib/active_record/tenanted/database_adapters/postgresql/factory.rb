# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters
      module PostgreSQL
        # Factory for creating the appropriate PostgreSQL adapter based on strategy
        #
        # The strategy is determined by the `postgresql_strategy` configuration option:
        # - "schema" (default): Uses schema-based multi-tenancy
        # - "database": Uses database-based multi-tenancy
        class Factory
          VALID_STRATEGIES = %w[schema database].freeze
          DEFAULT_STRATEGY = "schema"

          def self.new(db_config)
            strategy = db_config.configuration_hash[:postgresql_strategy]&.to_s || DEFAULT_STRATEGY

            # Validate strategy at config load time
            unless VALID_STRATEGIES.include?(strategy)
              raise ActiveRecord::Tenanted::UnsupportedDatabaseError,
                "Invalid PostgreSQL strategy: #{strategy.inspect}. " \
                "Valid options are: #{VALID_STRATEGIES.map(&:inspect).join(', ')}\n\n" \
                "Did you mean #{suggest_strategy(strategy).inspect}?"
            end

            case strategy
            when "schema"
              Schema.new(db_config)
            when "database"
              Database.new(db_config)
            end
          end

          def self.suggest_strategy(invalid_strategy)
            # Simple typo detection using Levenshtein distance
            VALID_STRATEGIES.min_by { |valid| levenshtein_distance(invalid_strategy.to_s, valid) }
          end

          def self.levenshtein_distance(s, t)
            # Implementation of Levenshtein distance for suggestion
            m = s.length
            n = t.length
            return m if n == 0
            return n if m == 0

            d = Array.new(m + 1) { Array.new(n + 1) }

            (0..m).each { |i| d[i][0] = i }
            (0..n).each { |j| d[0][j] = j }

            (1..n).each do |j|
              (1..m).each do |i|
                cost = s[i - 1] == t[j - 1] ? 0 : 1
                d[i][j] = [
                  d[i - 1][j] + 1,      # deletion
                  d[i][j - 1] + 1,      # insertion
                  d[i - 1][j - 1] + cost, # substitution
                ].min
              end
            end

            d[m][n]
          end
        end
      end
    end
  end
end
