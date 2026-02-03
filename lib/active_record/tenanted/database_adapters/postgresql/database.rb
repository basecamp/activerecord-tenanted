# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters
      module PostgreSQL
        # PostgreSQL adapter using database-based multi-tenancy
        #
        # Creates separate PostgreSQL databases for each tenant.
        # Similar to how MySQL and SQLite adapters work.
        #
        # Configuration example:
        #   adapter: postgresql
        #   tenanted: true
        #   database: myapp_%{tenant}
        #
        # The adapter will:
        # - Create separate databases like "myapp_foo", "myapp_bar"
        # - Connect to each tenant's database independently
        # - Provide stronger isolation than schema-based approach
        class Database < Base
          def tenant_databases
            like_pattern = db_config.database_for("%")
            scanner_pattern = db_config.database_for("(.+)")
            scanner = Regexp.new("^" + Regexp.escape(scanner_pattern).gsub(Regexp.escape("(.+)"), "(.+)") + "$")

            # Exclude the base database used by schema strategy
            # (e.g., "test_tenanted" when pattern is "test_%{tenant}")
            base_db_name = db_config.database.gsub(/%\{tenant\}/, "tenanted")

            begin
              with_maintenance_connection do |connection|
                # Query pg_database for databases matching pattern
                result = connection.execute(<<~SQL)
                  SELECT datname
                  FROM pg_database
                  WHERE datname LIKE '#{connection.quote_string(like_pattern)}'
                    AND datistemplate = false
                  ORDER BY datname
                SQL

                result.filter_map do |row|
                  db_name = row["datname"] || row[0]

                  # Skip the base database used by schema strategy
                  next if db_name == base_db_name

                  match = db_name.match(scanner)
                  if match.nil?
                    Rails.logger.warn "ActiveRecord::Tenanted: Cannot parse tenant name from database #{db_name.inspect}"
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
              Rails.logger.warn "Failed to list tenant databases: #{e.message}"
              []
            end
          end

          def create_database
            with_maintenance_connection do |connection|
              create_options = {}
              create_options[:encoding] = db_config.configuration_hash[:encoding] if db_config.configuration_hash.key?(:encoding)
              create_options[:collation] = db_config.configuration_hash[:collation] if db_config.configuration_hash.key?(:collation)

              # CREATE DATABASE cannot run inside a transaction block in PostgreSQL
              # Force commit any existing transaction, then use raw connection
              connection.commit_db_transaction if connection.transaction_open?

              encoding_clause = create_options[:encoding] ? " ENCODING '#{create_options[:encoding]}'" : ""
              collation_clause = create_options[:collation] ? " LC_COLLATE '#{create_options[:collation]}'" : ""

              connection.raw_connection.exec("CREATE DATABASE #{connection.quote_table_name(database_path)}#{encoding_clause}#{collation_clause}")
            end
          end

          def drop_database
            with_maintenance_connection do |connection|
              db_name = connection.quote_table_name(database_path)

              # Terminate all connections to the database before dropping
              # PostgreSQL doesn't allow dropping a database with active connections
              begin
                connection.execute(<<~SQL)
                  SELECT pg_terminate_backend(pg_stat_activity.pid)
                  FROM pg_stat_activity
                  WHERE pg_stat_activity.datname = '#{connection.quote_string(database_path)}'
                    AND pid <> pg_backend_pid()
                SQL
              rescue PG::Error => e
                # Ignore errors terminating connections (database might not exist)
                Rails.logger.debug "Could not terminate connections for #{database_path}: #{e.message}"
              end

              # DROP DATABASE cannot run inside a transaction block in PostgreSQL
              # Use raw connection to avoid transaction wrapping
              connection.raw_connection.exec("DROP DATABASE IF EXISTS #{db_name}")
            end
          rescue ActiveRecord::NoDatabaseError, PG::Error => e
            # Database might not exist or other PostgreSQL error
            Rails.logger.debug "Could not drop database #{database_path}: #{e.message}"
          end

          def database_exist?
            with_maintenance_connection do |connection|
              result = connection.execute(<<~SQL)
                SELECT 1
                FROM pg_database
                WHERE datname = '#{connection.quote_string(database_path)}'
              SQL
              result.any?
            end
          rescue ActiveRecord::NoDatabaseError, PG::Error
            false
          end

          def database_path
            db_config.database
          end

          def validate_tenant_name(tenant_name)
            super

            # Detect configuration errors - schema strategy features with database strategy
            if db_config.configuration_hash.key?(:schema_search_path)
              raise ActiveRecord::Tenanted::ConfigurationError,
                "PostgreSQL database strategy does not use `schema_search_path`. " \
                "Remove this configuration, or use `schema_name_pattern` " \
                "if you want schema-based multi-tenancy."
            end

            if db_config.configuration_hash.key?(:tenant_schema)
              raise ActiveRecord::Tenanted::ConfigurationError,
                "PostgreSQL database strategy does not use `tenant_schema`. " \
                "Remove this configuration, or use `schema_name_pattern` " \
                "if you want schema-based multi-tenancy."
            end
          end

        private
          def with_maintenance_connection(&block)
            ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(maintenance_config, &block)
          end

          def maintenance_config
            config_hash = db_config.configuration_hash.dup.merge(
              database: maintenance_db_name,  # Connect to maintenance database
              database_tasks: false
            )
            ActiveRecord::DatabaseConfigurations::HashConfig.new(
              db_config.env_name,
              "_maint_#{db_config.name}",
              config_hash
            )
          end
        end
      end
    end
  end
end
