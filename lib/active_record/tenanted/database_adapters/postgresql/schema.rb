# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters
      module PostgreSQL
        # PostgreSQL adapter using schema-based multi-tenancy
        #
        # Instead of creating separate databases per tenant, this adapter creates
        # separate schemas within a single PostgreSQL database. This is more efficient
        # and aligns with PostgreSQL best practices.
        #
        # Configuration examples:
        #
        # Colocated approach (recommended):
        #   adapter: postgresql
        #   tenanted: true
        #   database: myapp_production
        #   schema_name_pattern: "%{tenant}"  # Creates schemas: account-123, account-456, etc.
        #
        # The adapter will:
        # - Connect to a single base database
        # - Create/use schemas for tenant isolation
        # - Set schema_search_path to isolate tenants
        class Schema < Base
          include Colocated

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

          def create_database
            # Create schema instead of database
            schema = database_path

            with_base_connection do |connection|
              quoted_schema = connection.quote_table_name(schema)

              # Create the schema (our patch makes this idempotent with IF NOT EXISTS)
              connection.execute("CREATE SCHEMA IF NOT EXISTS #{quoted_schema}")

              # Commit any pending transaction to ensure schema is visible to other connections
              # with_temporary_connection may wrap DDL in a transaction
              connection.commit_db_transaction if connection.transaction_open?

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

          def create_colocated_database
            # Create the colocated database that will contain all tenant schemas.
            # Use Rails' DatabaseTasks.create to fully integrate with Rails
            base_db_name = extract_base_database_name

            # Create a non-tenanted database config for the base database
            # We strip out tenanted-specific keys to create a regular Rails
            # config Rails' create method will handle connection, logging, etc.
            base_config_hash = db_config.configuration_hash
              .except(:tenanted, :tenant_schema, :schema_search_path)
              .merge(database: base_db_name)

            base_create_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
              db_config.env_name,
              db_config.name,
              base_config_hash
            )

            ActiveRecord::Tasks::DatabaseTasks.create(base_create_config)
          end

          def drop_colocated_database
            # Drop the entire colocated database using Rails' DatabaseTasks.drop
            # to fully integrate with Rails
            base_db_name = extract_base_database_name

            # Create a non-tenanted database config for the base database
            # We strip out tenanted-specific keys to create a regular Rails config
            # Rails' drop method will handle connection, termination, logging, etc.
            base_config_hash = db_config.configuration_hash
              .except(:tenanted, :tenant_schema, :schema_search_path)
              .merge(database: base_db_name)

            base_drop_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
              db_config.env_name,
              db_config.name,
              base_config_hash
            )

            ActiveRecord::Tasks::DatabaseTasks.drop(base_drop_config)
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

          def database_path
            # Returns the schema name for this tenant
            # For PostgreSQL with schema-based tenancy, we store the schema name separately
            # because db_config.database is the base database name
            db_config.configuration_hash[:tenant_schema] || db_config.database
          end

          # Prepare tenant config hash with schema-specific settings
          def prepare_tenant_config_hash(config_hash, base_config, tenant_name)
            # If schema_name_pattern is provided, use it for schema names
            # Otherwise fall back to database pattern (original behavior)
            if base_config.configuration_hash[:schema_name_pattern]
              schema_name = sprintf(base_config.configuration_hash[:schema_name_pattern], tenant: tenant_name.to_s)
              database_name = extract_base_database_name
            else
              schema_name = base_config.database_for(tenant_name)
              database_name = base_config.database.gsub(/%\{tenant\}/, "tenanted")
            end

            config_hash.merge(
              schema_search_path: schema_name,
              tenant_schema: schema_name,
              database: database_name
            )
          end

          def identifier_for(tenant_name)
            # Override base class to use schema_name_pattern if provided
            if db_config.configuration_hash[:schema_name_pattern]
              sprintf(db_config.configuration_hash[:schema_name_pattern], tenant: tenant_name.to_s)
            else
              # Fall back to base class behavior
              super
            end
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
            # Extract base database name
            # If schema_name_pattern is provided, the database name is already static
            # Otherwise, replace %{tenant} with "tenanted" for the base database
            if db_config.configuration_hash[:schema_name_pattern]
              db_config.database
            else
              db_config.database.gsub(/%\{tenant\}/, "tenanted")
            end
          end

          def schema_name_for(tenant_name)
            # Generate schema name from tenant name
            # Delegate to identifier_for for consistency
            identifier_for(tenant_name)
          end
        end
      end
    end
  end
end
