# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters # :nodoc:
      class MySQL
        attr_reader :db_config

        def initialize(db_config)
          @db_config = db_config
        end

        def tenant_databases
          database_pattern = db_config.database_for("%")
          scanner = Regexp.new(db_config.database_for("(.+)"))

          with_server_connection do |conn|
            conn.select_values(
              "SHOW DATABASES LIKE #{conn.quote(database_pattern)}"
            ).filter_map do |name|
              match = name.match(scanner)
              if match
                match[1]
              else
                ActiveRecord::Base.logger&.warn "ActiveRecord::Tenanted: Cannot parse tenant name from database #{name.inspect}"
                nil
              end
            end
          end
        rescue ActiveRecord::NoDatabaseError => error
          ActiveRecord::Base.logger&.warn "ActiveRecord::Tenanted: tenant_databases returned empty due to NoDatabaseError: #{error.message}"
          []
        end

        def validate_tenant_name(tenant_name)
          if tenant_name.empty?
            raise BadTenantNameError, "Tenant name cannot be empty."
          end

          if tenant_name.match?(/[\/`]/) || !tenant_name.match?(/\A[\x20-\x7E]+\z/)
            raise BadTenantNameError, "Tenant name contains an invalid character: #{tenant_name.inspect}"
          end
        end

        def create_database
          with_server_connection do |conn|
            options = {}
            options[:charset] = db_config.configuration_hash[:encoding] if db_config.configuration_hash[:encoding]
            options[:collation] = db_config.configuration_hash[:collation] if db_config.configuration_hash[:collation]
            conn.create_database(database_path, options)
          end
        end

        def drop_database
          with_server_connection do |conn|
            conn.drop_database(database_path)
          end
        end

        def database_exist?
          with_server_connection do |conn|
            conn.select_values(
              "SELECT schema_name FROM information_schema.schemata WHERE schema_name = #{conn.quote(database_path)}"
            ).any?
          end
        rescue ActiveRecord::NoDatabaseError => error
          ActiveRecord::Base.logger&.warn "ActiveRecord::Tenanted: database_exist? returned false due to NoDatabaseError: #{error.message}"
          false
        end

        def database_ready?
          database_exist?
        end

        def acquire_ready_lock
          lock_name = "tenanted:#{database_path}"

          with_server_connection do |conn|
            result = conn.select_value("SELECT GET_LOCK(#{conn.quote(lock_name)}, 30)")
            unless result == 1
              raise ActiveRecord::LockWaitTimeout,
                "Could not acquire advisory lock for tenant database #{database_path.inspect}"
            end

            begin
              yield
            ensure
              begin
                conn.select_value("SELECT RELEASE_LOCK(#{conn.quote(lock_name)})")
              rescue => error
                # MySQL releases advisory locks automatically when the
                # connection closes, so a failed RELEASE_LOCK is recoverable.
                # Letting it propagate would mask the real operation result and
                # could cause create_tenant to drop a successfully created
                # database.
                ActiveRecord::Base.logger&.warn(
                  "ActiveRecord::Tenanted: failed to release advisory lock " \
                  "#{lock_name.inspect}: #{error.message}; the lock will be " \
                  "released when the connection closes"
                )
              end
            end
          end
        end

        def ensure_database_directory_exists
          true
        end

        def database_path
          db_config.database
        end

        def test_workerize(db, test_worker_id)
          test_worker_suffix = "_#{test_worker_id}"

          if db.end_with?(test_worker_suffix)
            db
          else
            db + test_worker_suffix
          end
        end

        def path_for(database)
          database
        end

        private

          # Establishes an isolated connection to the MySQL server (without a
          # specific database selected).  We intentionally avoid
          # DatabaseTasks.with_temporary_connection here because that method
          # replaces ActiveRecord::Base's global connection pool for the
          # duration of the block — any Base-backed query running concurrently
          # would hit the database-less server config.
          #
          # Instead we spin up a throwaway ConnectionHandler so the server
          # connection never touches the global pool.
          def with_server_connection
            server_config_hash = db_config.configuration_hash.except(:database)
            server_db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
              db_config.env_name, "#{db_config.name}_server", server_config_hash
            )

            handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
            pool = handler.establish_connection(server_db_config)

            pool.with_connection do |conn|
              yield conn
            end
          ensure
            handler&.clear_all_connections!(:all)
          end
      end
    end
  end
end
