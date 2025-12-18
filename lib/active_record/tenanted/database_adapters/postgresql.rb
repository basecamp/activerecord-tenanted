# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters # :nodoc:
      # PostgreSQL adapter using schema-based multi-tenancy
      #
      # Instead of creating separate databases per tenant, this adapter creates
      # separate schemas within a single PostgreSQL database. This is more efficient
      # and aligns with PostgreSQL best practices.
      #
      # Configuration example:
      #   database: tenant_%%{tenant}  # This becomes the schema name
      #
      # The adapter will:
      # - Connect to a single base database
      # - Create/use schemas like "tenant_foo", "tenant_bar", etc.
      # - Set schema_search_path to isolate tenants
      class PostgreSQL
        attr_reader :db_config

        def initialize(db_config)
          @db_config = db_config
        end

        def tenant_databases
          # Query for all schemas matching the pattern
          schema_pattern = schema_name_for("%")
          scanner_pattern = schema_name_for("(.+)")
          scanner = Regexp.new("^" + Regexp.escape(scanner_pattern).gsub(Regexp.escape("(.+)"), "(.+)") + "$")

          begin
            with_base_connection do |connection|
              # PostgreSQL stores schemas in information_schema.schemata
              result = connection.execute(<<~SQL)
                SELECT schema_name#{' '}
                FROM information_schema.schemata#{' '}
                WHERE schema_name LIKE '#{connection.quote_string(schema_pattern)}'
                  AND schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
                ORDER BY schema_name
              SQL

              result.filter_map do |row|
                schema_name = row["schema_name"] || row[0]
                match = schema_name.match(scanner)
                if match.nil?
                  Rails.logger.warn "ActiveRecord::Tenanted: Cannot parse tenant name from schema #{schema_name.inspect}"
                  nil
                else
                  tenant_name = match[1]

                  # Strip test_worker_id suffix if present
                  if db_config.test_worker_id
                    test_worker_suffix = "_#{db_config.test_worker_id}"
                    tenant_name = tenant_name.delete_suffix(test_worker_suffix)
                  end

                  tenant_name
                end
              end
            end
          rescue ActiveRecord::NoDatabaseError, PG::Error => e
            Rails.logger.warn "Failed to list tenant schemas: #{e.message}"
            []
          end
        end

        def validate_tenant_name(tenant_name)
          return if tenant_name == "%" || tenant_name == "(.+)"

          schema_name = schema_name_for(tenant_name.to_s)

          return if schema_name.include?("%{") || schema_name.include?("%}")

          # PostgreSQL identifier max length is 63 bytes
          # We validate against >= 63 to be conservative and match existing test expectations
          if schema_name.length >= 63
            raise ActiveRecord::Tenanted::BadTenantNameError, "Schema name too long (max 62 characters to be safe): #{schema_name.inspect}"
          end

          # Schema names can contain letters, numbers, underscores, dollar signs, and hyphens
          # We're permissive because we always quote schema names with quote_table_name
          if schema_name.match?(/[^a-z0-9_$-]/i)
            raise ActiveRecord::Tenanted::BadTenantNameError, "Schema name contains invalid characters (only letters, numbers, underscores, $, and hyphens are allowed): #{schema_name.inspect}"
          end

          # PostgreSQL identifiers must start with a letter (a-z) or underscore when unquoted
          # We enforce this even when quoted for consistency across adapters
          unless schema_name.match?(/^[a-z_]/i)
            raise ActiveRecord::Tenanted::BadTenantNameError, "Schema name must start with a letter or underscore: #{schema_name.inspect}"
          end
        end

        def create_database
          # Create schema instead of database
          schema = database_path

          with_base_connection do |connection|
            quoted_schema = connection.quote_table_name(schema)
            # Create the schema (our patch makes this idempotent with IF NOT EXISTS)
            connection.execute("CREATE SCHEMA IF NOT EXISTS #{quoted_schema}")

            # Grant usage permissions (optional but good practice)
            # This ensures the schema can be used by the current user
            username = db_config.configuration_hash[:username] || "postgres"
            connection.execute("GRANT ALL ON SCHEMA #{quoted_schema} TO #{connection.quote_table_name(username)}")
          end
        end

        def drop_database
          # Drop schema instead of database
          schema = database_path

          with_base_connection do |connection|
            # CASCADE ensures all objects in the schema are dropped
            connection.execute("DROP SCHEMA IF EXISTS #{connection.quote_table_name(schema)} CASCADE")
          end
        end

        def database_exist?
          # Check if schema exists
          schema = database_path

          with_base_connection do |connection|
            result = connection.execute(<<~SQL)
              SELECT 1#{' '}
              FROM information_schema.schemata#{' '}
              WHERE schema_name = '#{connection.quote_string(schema)}'
            SQL
            result.any?
          end
        rescue ActiveRecord::NoDatabaseError, PG::Error
          false
        end

        def database_ready?
          database_exist?
        end

        def acquire_ready_lock(&block)
          # No file-system locking needed for schemas
          yield
        end

        def ensure_database_directory_exists
          # No directory needed for schemas
          true
        end

        def database_path
          # Returns the schema name for this tenant
          # For PostgreSQL with schema-based tenancy, we store the schema name separately
          # because db_config.database is the base database name
          db_config.configuration_hash[:tenant_schema] || db_config.database
        end

        def test_workerize(db, test_worker_id)
          # For schemas, we append the worker ID to the schema name
          test_worker_suffix = "_#{test_worker_id}"

          if db.end_with?(test_worker_suffix)
            db
          else
            db + test_worker_suffix
          end
        end

        def path_for(schema_name)
          # For PostgreSQL schemas, path is just the schema name
          schema_name
        end

      private
        def with_base_connection(&block)
          # Connect to the base database (without tenant-specific schema)
          # This allows us to create/drop/query schemas

          # Ensure the base database exists first
          ensure_base_database_exists

          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(base_db_config, &block)
        end

        def ensure_base_database_exists
          # Check if base database exists, create if not
          base_db_name = extract_base_database_name

          # Connect to postgres maintenance database to check/create base database
          maintenance_config = db_config.configuration_hash.dup.merge(
            database: "postgres",
            database_tasks: false
          )
          maintenance_db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
            db_config.env_name,
            "_maint_#{db_config.name}",
            maintenance_config
          )

          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(maintenance_db_config) do |connection|
            result = connection.execute("SELECT 1 FROM pg_database WHERE datname = '#{connection.quote_string(base_db_name)}'")
            unless result.any?
              # Create base database if it doesn't exist
              Rails.logger.info "Creating base PostgreSQL database: #{base_db_name}"
              create_options = {}
              create_options[:encoding] = db_config.configuration_hash[:encoding] if db_config.configuration_hash.key?(:encoding)
              create_options[:collation] = db_config.configuration_hash[:collation] if db_config.configuration_hash.key?(:collation)

              connection.create_database(base_db_name, create_options)
            end
          end
        rescue PG::Error => e
          # Ignore if database already exists (race condition)
          raise unless e.message.include?("already exists")
        rescue StandardError => e
          Rails.logger.error "Failed to ensure base database exists: #{e.class}: #{e.message}"
          raise
        end

        def base_db_config
          # Create a config for the base database
          # We extract the base database name from the pattern
          base_db_name = extract_base_database_name

          configuration_hash = db_config.configuration_hash.dup.merge(
            database: base_db_name,
            database_tasks: false,
            schema_search_path: "public" # Use public schema for admin operations
          )

          ActiveRecord::DatabaseConfigurations::HashConfig.new(
            db_config.env_name,
            "_tmp_#{db_config.name}",
            configuration_hash
          )
        end

        def extract_base_database_name
          # Extract base database name from the pattern
          # For "test_%{tenant}" (after YAML loading) we need a consistent database name
          # We'll use the pattern with "tenanted" as the suffix
          # This gives us something like "test_tenanted"
          db_config.database.gsub(/%\{tenant\}/, "tenanted")
        end

        def schema_name_for(tenant_name)
          # Generate schema name from tenant name using the database pattern
          # For pattern like "tenant_%%{tenant}", this becomes "tenant_foo"
          sprintf(db_config.database, tenant: tenant_name.to_s)
        end
      end
    end
  end
end
