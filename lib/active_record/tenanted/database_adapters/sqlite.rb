# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters
      class SQLite
        def initialize(db_config)
          @db_config = db_config
          @configuration_hash = db_config.configuration_hash
        end

        def create_database
          database_path = get_database_path(db_config)

          # Ensure the directory exists
          database_dir = File.dirname(database_path)
          FileUtils.mkdir_p(database_dir) unless File.directory?(database_dir)

          # Create the SQLite database file
          FileUtils.touch(database_path)
        end

        def drop_database
          database_path = get_database_path(db_config)

          # Remove the SQLite database file and associated files
          FileUtils.rm_f(database_path)
          FileUtils.rm_f("#{database_path}-wal")  # Write-Ahead Logging file
          FileUtils.rm_f("#{database_path}-shm")  # Shared Memory file
        end

        def database_exists?
          database_path = get_database_path(db_config)
          File.exist?(database_path) && !ActiveRecord::Tenanted::Mutex::Ready.locked?(database_path)
        end

        def list_tenant_databases
          glob = db_config.database_path_for("*")
          scanner = Regexp.new(db_config.database_path_for("(.+)"))

          Dir.glob(glob).filter_map do |path|
            result = path.scan(scanner).flatten.first
            if result.nil?
              Rails.logger.warn "ActiveRecord::Tenanted: Cannot parse tenant name from filename #{path.inspect}"
            end
            result
          end
        end

        def acquire_lock(lock_identifier, &block)
          ActiveRecord::Tenanted::Mutex::Ready.lock(lock_identifier, &block)
        end

        def validate_tenant_name(tenant_name)
          if tenant_name.match?(%r{[/'"`]})
            raise BadTenantNameError, "Tenant name contains an invalid character: #{tenant_name.inspect}"
          end
        end

        private
          attr_reader :db_config, :db_configuration_hash

          def get_database_path(db_config)
            if db_config.respond_to?(:database_path) && db_config.database_path
              db_config.database_path
            else
              db_config.database
            end
          end
      end
    end
  end
end
