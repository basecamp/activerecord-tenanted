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
          like_pattern = db_config.database_for("%")
          scanner_pattern = db_config.database_for("(.+)")
          scanner = Regexp.new("^" + Regexp.escape(scanner_pattern).gsub(Regexp.escape("(.+)"), "(.+)") + "$")

          begin
            ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(configuration_hash_without_database) do |connection|
              result = connection.execute("SHOW DATABASES LIKE '#{like_pattern}'")

              result.filter_map do |row|
                db_name = row[0] || row.first
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
          rescue ActiveRecord::NoDatabaseError, Mysql2::Error
            []
          end
        end

        def validate_tenant_name(tenant_name)
          return if tenant_name == "%" || tenant_name == "(.+)"

          database_name = sprintf(db_config.database, tenant: tenant_name.to_s)

          return if database_name.include?("%{") || database_name.include?("%}")

          if database_name.length > 64
            raise ActiveRecord::Tenanted::BadTenantNameError, "Database name too long (max 64 characters): #{database_name.inspect}"
          end

          if database_name.match?(/[^a-zA-Z0-9_$-]/)
            raise ActiveRecord::Tenanted::BadTenantNameError, "Database name contains invalid characters (only letters, numbers, underscore, $ and hyphen allowed): #{database_name.inspect}"
          end

          if database_name.match?(/^\d/)
            raise ActiveRecord::Tenanted::BadTenantNameError, "Database name cannot start with a number: #{database_name.inspect}"
          end
        end

        def create_database
          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(configuration_hash_without_database) do |connection|
            create_options = Hash.new.tap do |options|
              options[:charset] = db_config.configuration_hash[:encoding] if db_config.configuration_hash.include?(:encoding)
              options[:collation] = db_config.configuration_hash[:collation] if db_config.configuration_hash.include?(:collation)
            end

            connection.create_database(database_path, create_options)
          end
        end

        def drop_database
          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(configuration_hash_without_database) do |connection|
            connection.execute("DROP DATABASE IF EXISTS #{connection.quote_table_name(database_path)}")
          end
        end

        def database_exist?
          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(configuration_hash_without_database) do |connection|
            result = connection.execute("SHOW DATABASES LIKE '#{database_path}'")
            result.any?
          end
        rescue ActiveRecord::NoDatabaseError, Mysql2::Error
          false
        end

        def database_ready?
          database_exist?
        end

        def acquire_ready_lock(&block)
          yield
        end

        def ensure_database_directory_exists
          database_path.present?
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
        def configuration_hash_without_database
          configuration_hash = db_config.configuration_hash.dup.merge(database: nil)
          ActiveRecord::DatabaseConfigurations::HashConfig.new(
            db_config.env_name,
            db_config.name.to_s,
            configuration_hash
          )
        end
      end
    end
  end
end
