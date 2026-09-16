# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    # Rails compares the version in the schema cache dump with the schema version of the database
    # before it uses the dump, and ignores the dump when the versions do not match. This gem turns
    # that check off globally (see Railtie) because an untenanted model has no database to query.
    #
    # This class restores the check for tenanted connection pools. It compares the dump with the
    # schema version of the tenant database, the same way Rails does. See
    # UntenantedConnectionPool::SchemaReflection for the check that runs without a database.
    class SchemaReflection < ActiveRecord::ConnectionAdapters::SchemaReflection # :nodoc:
      class << self
        # Rails stores these settings in class-level instance variables on its own class, so a
        # subclass must read them from there.
        delegate :use_schema_cache_dump, :check_schema_cache_dump_version,
                 to: ActiveRecord::ConnectionAdapters::SchemaReflection
      end

      private
        # Mirrors ActiveRecord::ConnectionAdapters::SchemaReflection#load_cache with the version
        # check turned on.
        def load_cache(pool)
          return unless possible_cache_available?
          return unless (new_cache = ActiveRecord::ConnectionAdapters::SchemaCache._load_from(@cache_path))
          return unless (current_version = current_schema_version(pool))

          if new_cache.schema_version != current_version
            warn "Ignoring #{@cache_path} because it has expired. " \
                 "The current schema version is #{current_version}, " \
                 "but the one in the schema cache file is #{new_cache.schema_version}. " \
                 "Run `bin/rails db:migrate` in the development environment to write a new schema cache dump. " \
                 "If the development database is ahead of the migration files, run `bin/rails db:reset:NAME` instead."
            return
          end

          new_cache
        rescue ActiveRecordError => error
          warn "Failed to validate the schema cache because of #{error.class}: #{error.message}"
          nil
        end

        # Returns nil when there is no pool to query, so the dump is not loaded.
        def current_schema_version(pool)
          pool&.with_connection(&:schema_version)
        end
    end
  end
end
