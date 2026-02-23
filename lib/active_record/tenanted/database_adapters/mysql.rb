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
                Rails.logger.warn "ActiveRecord::Tenanted: Cannot parse tenant name from database #{name.inspect}"
                nil
              end
            end
          end
        rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
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
        rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
          false
        end

        def database_ready?
          database_exist?
        end

        def acquire_ready_lock
          yield
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

          def with_server_connection
            server_config_hash = db_config.configuration_hash.except(:database)
            server_db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
              db_config.env_name, "#{db_config.name}_server", server_config_hash
            )

            ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(server_db_config) do |conn|
              yield conn
            end
          end
      end
    end
  end
end
