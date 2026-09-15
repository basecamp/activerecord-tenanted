# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    # In an untenanted context, instances of this class are returned by `Tenant.connection_pool`.
    #
    # Many places in Rails assume that `.connection_pool` can be called and will return an object,
    # and so we can't just raise an exception if it's called while untenanted.
    #
    # Instead, this class exists to provide a minimal set of features that don't need a database
    # connection, and that will raise if a connection is attempted.
    class UntenantedConnectionPool < ActiveRecord::ConnectionAdapters::NullPool # :nodoc:
      attr_reader :db_config

      def initialize(db_config, model)
        super()

        @db_config = db_config
        @model = model
      end

      # There is no database to query, so the schema cache dump is compared with the latest
      # migration file on disk instead.
      class SchemaReflection < Tenanted::SchemaReflection # :nodoc:
        def initialize(cache_path, migrations_paths)
          super(cache_path)
          @migrations_paths = migrations_paths
        end

        private
          # Mirrors ActiveRecord::MigrationContext#migration_files and #parse_migration_filename
          def current_schema_version(_pool)
            paths = Array(@migrations_paths)
            files = Dir[*paths.flat_map { |path| "#{path}/**/[0-9]*_*.rb" }]
            files.filter_map { |file| File.basename(file).scan(Migration::MigrationFilenameRegexp).first&.first&.to_i }.max || 0
          end
      end

      def schema_reflection
        schema_cache_path = ActiveRecord::Tasks::DatabaseTasks.cache_dump_filename(db_config)
        SchemaReflection.new(schema_cache_path, migrations_paths)
      end

      def migrations_paths
        db_config.migrations_paths || ActiveRecord::Migrator.migrations_paths
      end

      def schema_cache
        ActiveRecord::ConnectionAdapters::BoundSchemaReflection.new(schema_reflection, self)
      end

      def size
        db_config.max_connections
      end

      def clear_query_cache
      end

      def lease_connection(...)
        raise Tenanted::NoTenantError, "Cannot connect to a tenanted database while untenanted (#{@model})."
      end

      def checkout(...)
        raise Tenanted::NoTenantError, "Cannot connect to a tenanted database while untenanted (#{@model})."
      end

      def with_connection(...)
        raise Tenanted::NoTenantError, "Cannot connect to a tenanted database while untenanted (#{@model})."
      end

      def new_connection(...)
        raise Tenanted::NoTenantError, "Cannot connect to a tenanted database while untenanted (#{@model})."
      end
    end
  end
end
