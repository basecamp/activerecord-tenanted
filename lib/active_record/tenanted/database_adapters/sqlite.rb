# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters # :nodoc:
      #
      #  TODO: This still feels to me like it's not _quite_ right. I think we could further refactor this by:
      #
      #  1. Moving tenant_databases and validate_tenant_name to BaseConfig, and subclassing it for
      #     each database
      #  2. Moving create_database, drop_database, database_exist?, database_ready?,
      #     acquire_ready_lock, ensure_database_directory_exists, and database_path to the SQLite
      #     connection adapter, possibly into Rails
      #  3. Moving test_workerize and path_for to be SQLite connection adapter class methods,
      #     possibly into Rails
      #
      class SQLite
        attr_reader :db_config

        def initialize(db_config)
          @db_config = db_config
        end

        def tenant_databases
          glob = path_for(db_config.database_for("*"))
          scanner = Regexp.new(path_for(db_config.database_for("(.+)")))

          Dir.glob(glob).filter_map do |path|
            result = path.scan(scanner).flatten.first
            if result.nil?
              ActiveRecord::Base.logger&.warn "ActiveRecord::Tenanted: Cannot parse tenant name from filename #{path.inspect}"
            end
            result
          end
        end

        def validate_tenant_name(tenant_name)
          if tenant_name.match?(%r{[/'"`]})
            raise BadTenantNameError, "Tenant name contains an invalid character: #{tenant_name.inspect}"
          end
        end

        def create_database
          ensure_database_directory_exists
          FileUtils.touch(database_path)
        end

        def drop_database
          # Remove the SQLite database file and associated files
          FileUtils.rm_f(database_path)
          FileUtils.rm_f("#{database_path}-wal")  # Write-Ahead Logging file
          FileUtils.rm_f("#{database_path}-shm")  # Shared Memory file
        end

        def database_exist?
          File.exist?(database_path)
        end

        def database_ready?
          File.exist?(database_path) && !ActiveRecord::Tenanted::Mutex::Ready.locked?(database_path)
        end

        def acquire_ready_lock(&block)
          ActiveRecord::Tenanted::Mutex::Ready.lock(database_path, &block)
        end

        def ensure_database_directory_exists
          return unless database_path

          database_dir = File.dirname(database_path)
          unless File.directory?(database_dir)
            FileUtils.mkdir_p(database_dir)
          end
        end

        def database_path
          path_for(db_config.database)
        end

        def test_workerize(db, test_worker_id)
          test_worker_suffix = "_#{test_worker_id}"

          if db.start_with?("file:") && db.include?("?")
            db.sub(/(\?.*)$/, "#{test_worker_suffix}\\1")
          else
            # This check is needed because of https://github.com/rails/rails/pull/55769 adding
            # replicas to the parallelization setup by using `include_hidden: true` which pulls in
            # the BaseConfig. We don't want to double-suffix the database name.
            #
            # TODO: Ideally we should have finer-grained filtering of database configurations in Rails
            # (other than simply hidden or not-hidden).
            if db.end_with?(test_worker_suffix)
              db
            else
              db + test_worker_suffix
            end
          end
        end

        # A sqlite database path can be a file path or a URI (either relative or absolute).  We
        # can't parse it as a standard URI in all circumstances, though, see
        # https://sqlite.org/uri.html
        def path_for(database)
          if database.start_with?("file:/")
            URI.parse(database).path
          elsif database.start_with?("file:")
            URI.parse(database.sub(/\?.*$/, "")).opaque
          else
            database
          end
        end
      end
    end
  end
end
