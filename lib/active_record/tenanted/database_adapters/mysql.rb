# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters
      class MySQL
        attr_reader :db_config

        def initialize(db_config)
          @db_config = db_config
        end

        def tenant_databases
          like_pattern = db_config.database.gsub(/%\{tenant\}/, "%")
          scanner = Regexp.new("^" + Regexp.escape(db_config.database).gsub(Regexp.escape("%{tenant}"), "(.+)") + "$")

          server_config = db_config.configuration_hash.dup
          server_config.delete(:database)
          temp_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
            db_config.env_name,
            "#{db_config.name}_server",
            server_config
          )

          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(temp_config) do |conn|
            result = conn.execute("SHOW DATABASES LIKE '#{like_pattern}'")

            result.filter_map do |row|
              db_name = row[0] || row.first
              match = db_name.match(scanner)
              if match.nil?
                Rails.logger.warn "ActiveRecord::Tenanted: Cannot parse tenant name from database #{db_name.inspect}"
                nil
              else
                match[1]
              end
            end
          end
        rescue ActiveRecord::NoDatabaseError, Mysql2::Error => e
          Rails.logger.warn "Could not list tenant databases: #{e.message}"
          []
        end

        def validate_tenant_name(tenant_name)
          tenant_name_str = tenant_name.to_s

          database_name = sprintf(db_config.database, tenant: tenant_name_str)

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

          reserved_words = %w[
            database databases table tables column columns index indexes
            select insert update delete create drop alter
            user users group groups order by from where
            and or not null true false
          ]

          if reserved_words.include?(database_name.downcase)
            raise ActiveRecord::Tenanted::BadTenantNameError, "Database name is a reserved MySQL keyword: #{database_name.inspect}"
          end
        end

        def create_database
          # Create a temporary config without the specific database to connect to MySQL server
          server_config = db_config.configuration_hash.dup
          server_config.delete(:database)
          temp_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
            db_config.env_name,
            "#{db_config.name}_server",
            server_config
          )
          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(temp_config) do |conn|
            # Use ActiveRecord's built-in create_database method with charset/collation from config
            create_options = {}

            # Add charset/encoding if specified
            if charset = db_config.configuration_hash[:encoding] || db_config.configuration_hash[:charset]
              create_options[:charset] = charset
            end

            # Add collation if specified
            if collation = db_config.configuration_hash[:collation]
              create_options[:collation] = collation
            end

            conn.create_database(database_path, create_options)
          end
        end

        def drop_database
          # Create a temporary config without the specific database to connect to MySQL server
          server_config = db_config.configuration_hash.dup
          server_config.delete(:database)
          temp_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
            db_config.env_name,
            "#{db_config.name}_server",
            server_config
          )

          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(temp_config) do |conn|
            # Use ActiveRecord's built-in drop_database method
            conn.drop_database(database_path)
          end
        end

        def database_exist?
          server_config = db_config.configuration_hash.dup
          server_config.delete(:database)
          temp_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
            db_config.env_name,
            "#{db_config.name}_server",
            server_config
          )

          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(temp_config) do |conn|
            result = conn.execute("SHOW DATABASES LIKE '#{database_path}'")
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
          # TODO: Implement
        end

        def path_for(database)
          database
        end
      end
    end
  end
end
