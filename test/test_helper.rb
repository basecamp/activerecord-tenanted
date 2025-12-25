# frozen_string_literal: true

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"
ENV["ARTENANT_SCHEMA_DUMP"] = "t" # we don't normally dump schemas outside of development
ENV["VERBOSE"] = "false" # suppress database task output

# Run cleanup at test suite start - defined later in ActiveRecord::Tenanted::TestCase
# We can't call it yet since the class isn't defined, so we'll do it after Rails loads

require "rails"
require "rails/test_help" # should be before active_record is loaded to avoid schema/fixture setup

class TestSuiteRailtie < ::Rails::Railtie
  initializer "turn off the Rails integrations when running this test suite" do
    ActiveSupport.on_load(:active_record_tenanted) do
      Rails.application.config.active_record_tenanted.connection_class = nil
      Rails.application.config.active_record.query_log_tags = [ :tenant ]
    end
  end

  initializer "enabled query log tags for tests" do
    Rails.application.config.active_record.query_log_tags_enabled = true
  end
end

require_relative "../lib/active_record/tenanted"

require_relative "dummy/config/environment"
require "erb"
require "minitest/spec"
require "minitest/mock"

# Needed to test Active Storage Disk Service in the absence of a full active_storage:install in the dummy app
require "active_storage"
require "active_storage/service/disk_service"
ActiveStorage::Service::DiskService.prepend ActiveRecord::Tenanted::Storage::DiskService

if ENV["NCPU"].to_i > 1
  require "minitest/parallel_fork"
  warn "Running parallel tests with NCPU=#{ENV["NCPU"].inspect}"
end

module ActiveRecord
  module Tenanted
    class TestCase < ActiveSupport::TestCase
      extend Minitest::Spec::DSL

      class << self
        # Shared helper to clean up PostgreSQL test databases and schemas
        def cleanup_postgresql_databases_and_schemas(skip_shared: false)
          return unless defined?(PG)

          prefix = ENV.fetch("POSTGRES_UNIQUE_PREFIX", "test")

          begin
            require "pg"
            conn = PG.connect(
              host: ENV.fetch("POSTGRES_HOST", "127.0.0.1"),
              port: ENV.fetch("POSTGRES_PORT", "5432").to_i,
              dbname: "postgres",
              user: ENV.fetch("POSTGRES_USERNAME", "postgres"),
              password: ENV.fetch("POSTGRES_PASSWORD", "postgres")
            )

            # Find all databases starting with the test prefix OR integration test prefix (t<digits>)
            result = conn.exec(
              "SELECT datname FROM pg_database WHERE (datname LIKE '#{prefix}%' OR datname ~ '^t[0-9]+') AND datistemplate = false"
            )

            result.each do |row|
              db_name = row["datname"]
              next if skip_shared && db_name == "#{prefix}_shared"

              begin
                conn.exec_params(
                  "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = $1 AND pid <> pg_backend_pid()",
                  [ db_name ]
                )
                conn.exec("DROP DATABASE IF EXISTS #{conn.escape_identifier(db_name)}")
              rescue => e
                # Ignore errors
              end
            end

            # Clean up schemas in the base database
            base_db = prefix
            if conn.exec_params("SELECT 1 FROM pg_database WHERE datname = $1", [ base_db ]).ntuples > 0
              conn.close
              conn = PG.connect(
                host: ENV.fetch("POSTGRES_HOST", "127.0.0.1"),
                port: ENV.fetch("POSTGRES_PORT", "5432").to_i,
                dbname: base_db,
                user: ENV.fetch("POSTGRES_USERNAME", "postgres"),
                password: ENV.fetch("POSTGRES_PASSWORD", "postgres")
              )

              schemas_result = conn.exec_params(
                "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE $1",
                [ "account-%" ]
              )

              schemas_result.each do |row|
                schema_name = row["schema_name"]
                begin
                  conn.exec("DROP SCHEMA IF EXISTS #{conn.escape_identifier(schema_name)} CASCADE")
                rescue => e
                  # Ignore
                end
              end
            end

            conn.close if conn
          rescue => e
            # Continue if PostgreSQL isn't available
          end
        end

        # When used with Minitest::Spec's `describe`, ActiveSupport::Testing's `test` creates methods
        # that may be inherited by subsequent describe blocks and run multiple times. Warn us if this
        # happens. (Note that Minitest::Spec's `it` doesn't do this.)
        def test(name, &block)
          if self.children.any?
            c = caller_locations[0]
            path = Pathname.new(c.path).relative_path_from(Pathname.new(Dir.pwd))
            puts "WARNING: #{path}:#{__LINE__}: test #{name.inspect} is being inherited"
          end

          super
        end

        def for_each_db_scenario(s = all_scenarios, &block)
          s.each_key do |db_scenario|
            with_db_scenario(db_scenario, &block)
          end
        end

        def for_each_scenario(s = all_scenarios, except: {}, only: {}, &block)
          s.each do |db_scenario, model_scenarios|
            with_db_scenario(db_scenario) do
              model_scenarios.each do |model_scenario|
                scenario_name = db_scenario.to_s.split("/").last
                adapter = db_scenario.to_s.include?("/") ? db_scenario.to_s.split("/").first.to_sym : nil

                next if only.present? && only.dig(:adapter) != adapter
                next if except[db_scenario.to_sym]&.include?(model_scenario.to_sym)
                next if except[scenario_name.to_sym]&.include?(model_scenario.to_sym)
                with_model_scenario(model_scenario, &block)
              end
            end
          end
        end

        def all_scenarios
          Dir.glob(File.join(__dir__, "scenarios", "*", "*", "database.yml"))
            .each_with_object({}) do |db_config_path, scenarios|
            db_config_dir = File.dirname(db_config_path)
            db_adapter = File.basename(File.dirname(db_config_dir))
            db_scenario = File.basename(db_config_dir)
            model_files = Dir.glob(File.join(db_config_dir, "*.rb"))

            scenarios["#{db_adapter}/#{db_scenario}"] = model_files.map { File.basename(_1, ".*") }
          end
        end

        def with_db_scenario(db_scenario, &block)
          db_adapter, db_name = db_scenario.to_s.split("/", 2)

          if db_name.nil?
            db_name = db_adapter
            matching_scenarios = all_scenarios.keys.select { |key| key.to_s.end_with?("/#{db_name}") }
            raise "Could not find scenario: #{db_name}" if matching_scenarios.empty?

            if matching_scenarios.size > 1
              matching_scenarios.each do |scenario|
                with_db_scenario(scenario, &block)
              end
              return
            end

            db_adapter, db_name = matching_scenarios.first.to_s.split("/", 2)
          end

          db_config_path = File.join(__dir__, "scenarios", db_adapter, db_name, "database.yml")
          raise "Could not find scenario db config: #{db_config_path}" unless File.exist?(db_config_path)

          describe "scenario::#{db_adapter}/#{db_name}" do
            @db_config_dir = db_config_dir = File.dirname(db_config_path)

            let(:ephemeral_path) { Dir.mktmpdir("test-activerecord-tenanted-") }
            let(:storage_path) { File.join(ephemeral_path, "storage") }
            let(:db_path) { File.join(ephemeral_path, "db") }
            let(:db_adapter) { "#{db_adapter}" }
            let(:db_scenario) { db_name.to_sym }
            let(:db_config_yml) do
              erb_content = ERB.new(File.read(db_config_path)).result(binding)
              sprintf(erb_content, storage: storage_path, db_path: db_path, tenant: "%{tenant}")
            end
            let(:db_config) { YAML.load(db_config_yml, aliases: true) }

            setup do
              FileUtils.mkdir(db_path)
              FileUtils.cp_r Dir.glob(File.join(db_config_dir, "*migrations")), db_path

              # Make sure that both the primary thread and any threads in the tests will have a
              # fresh connection handler, otherwise threads may try to connect to a temporary
              # database used in (and destroyed by) a previous test
              @old_connection_handler = ActiveRecord::Base.connection_handler
              ActiveRecord::Base.connection_handler = ActiveRecord::Base.default_connection_handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new

              @old_db_dir = ActiveRecord::Tasks::DatabaseTasks.db_dir
              ActiveRecord::Tasks::DatabaseTasks.db_dir = db_path

              @old_configurations = ActiveRecord::Base.configurations
              ActiveRecord::Base.configurations = db_config

              @migration_verbose_was, ActiveRecord::Migration.verbose = ActiveRecord::Migration.verbose, false
              ActiveRecord::Tasks::DatabaseTasks.prepare_all
            end

            teardown do
              drop_shared_databases
              drop_tentant_databases
              cleanup_postgresql_test_databases if defined?(PG) && db_adapter == "postgresql"
              ActiveRecord::Migration.verbose = @migration_verbose_was
              ActiveRecord::Base.configurations = @old_configurations
              ActiveRecord::Tasks::DatabaseTasks.db_dir = @old_db_dir
              ActiveRecord::Base.connection_handler = ActiveRecord::Base.default_connection_handler = @old_connection_handler
              FileUtils.remove_entry ephemeral_path
            end

            instance_eval(&block)
          end
        end

        def with_model_scenario(models_scenario, &block)
          models_scenario_file = File.join(@db_config_dir, "#{models_scenario}.rb")
          raise "Could not find model scenario: #{models_scenario_file}" unless File.exist?(models_scenario_file)

          describe models_scenario do
            let(:models_scenario) { models_scenario.to_sym }

            setup do
              clear_dummy_models
              create_fake_record
              load models_scenario_file
            end

            teardown do
              clear_dummy_models
              clear_connected_to_stack
            end

            instance_eval(&block)
          end
        end

        def with_scenario(db_scenario, model_scenario, &block)
          with_db_scenario(db_scenario) do
            with_model_scenario(model_scenario, &block)
          end
        end

        def with_active_storage(&block)
          with_scenario(:primary_db, :primary_record) do
            setup do
              as_path = Gem.loaded_specs["activestorage"].full_gem_path
              as_migrations = Dir.glob(File.join(as_path, "db", "*migrate", "*.rb"))
              FileUtils.cp as_migrations, File.join(db_path, "tenanted_migrations")

              ActiveStorage::Record.subtenant_of "TenantedApplicationRecord"
            end

            instance_eval(&block)
          end
        end
      end

      # save and restore the gem's configuration options, so we can safely muck with them in tests
      setup do
        @old_connection_class       = Rails.application.config.active_record_tenanted.connection_class
        @old_tenanted_rails_records = Rails.application.config.active_record_tenanted.tenanted_rails_records
        @old_log_tenant_tag         = Rails.application.config.active_record_tenanted.log_tenant_tag
        @old_tenant_resolver        = Rails.application.config.active_record_tenanted.tenant_resolver
      end

      teardown do
        Rails.application.config.active_record_tenanted.connection_class        = @old_connection_class
        Rails.application.config.active_record_tenanted.tenanted_rails_records  = @old_tenanted_rails_records
        Rails.application.config.active_record_tenanted.log_tenant_tag          = @old_log_tenant_tag
        Rails.application.config.active_record_tenanted.tenant_resolver         = @old_tenant_resolver
      end

      def run(...)
        if defined?(with_debug_event_reporting)
          with_debug_event_reporting do
            super
          end
        else
          super
        end
      end

      def all_configs
        ActiveRecord::Base.configurations.configs_for(env_name: "test", include_hidden: true)
      end

      def base_config
        all_configs.find { |c| c.configuration_hash[:tenanted] }
      end

      def with_schema_dump_file
        # Only copy the schema file for the current adapter to avoid conflicts
        schema_file = File.join("test", "scenarios", db_adapter, "schema.rb")
        if File.exist?(schema_file)
          FileUtils.cp schema_file,
            ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(base_config)
        end
      end

      def with_schema_cache_dump_file
        Dir.glob("test/scenarios/*/schema_cache.yml").each do |cache_file|
          FileUtils.cp cache_file,
            ActiveRecord::Tasks::DatabaseTasks.cache_dump_filename(base_config)
        end
      end

      def with_new_migration_file
        with_migration("20250213005959_add_age_to_users.rb")
      end

      def with_migration(file)
        FileUtils.cp File.join("test", "scenarios", db_adapter, file), File.join(db_path, "tenanted_migrations")
      end

      def assert_same_elements(expected, actual)
        assert_equal(expected.sort, actual.sort, "Elements don't match")
      end

      def capture_log
        StringIO.new.tap do |log|
          logger_was, ActiveRecord::Base.logger = ActiveRecord::Base.logger, ActiveSupport::Logger.new(log)
          yield
        ensure
          ActiveRecord::Base.logger = logger_was
        end
      end

      def capture_rails_log
        StringIO.new.tap do |log|
          logger_was, Rails.logger = Rails.logger, ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(log))
          yield
        ensure
          Rails.logger = logger_was
        end
      end

      private
        def cleanup_postgresql_test_databases
          # Skip shared database during per-test cleanup (it gets dropped in drop_shared_databases)
          self.class.cleanup_postgresql_databases_and_schemas(skip_shared: true)
        end

        def drop_shared_databases
          shared_configs = all_configs.reject { |c| c.configuration_hash[:tenanted] || c.database.blank? }
          return if shared_configs.empty?

          shared_configs.each do |config|
            ActiveRecord::Tasks::DatabaseTasks.drop(config)
          rescue => e
            Rails.logger.warn "Failed to cleanup shared database #{config.name}: #{e.message}"
          end
        end

        def drop_tentant_databases
          base_config = all_configs.find { |c| c.configuration_hash[:tenanted] }
          return unless base_config

          begin
            tenants = base_config.tenants
          rescue => e
            # If we can't list tenants (e.g., database doesn't exist), that's fine
            Rails.logger.debug "Could not list tenants for cleanup: #{e.message}"
            return
          end

          return if tenants.empty?

          tenants.each do |tenant_name|
            # Use the tenant config's adapter for proper cleanup
            tenant_config = base_config.new_tenant_config(tenant_name)
            adapter = tenant_config.config_adapter
            adapter.drop_database
          rescue => e
            # Log warning but don't fail the teardown
            warn "Failed to cleanup tenant database #{tenant_name}: #{e.class}: #{e.message}"
          end
        end

        def create_fake_record
          # emulate models like ActiveStorage::Record that inherit directly from AR::Base
          Object.const_set(:FakeRecord, Class.new(ActiveRecord::Base))
        end

        def dummy_model_names
          %w[TenantedApplicationRecord User Post SharedApplicationRecord Announcement FakeRecord]
        end

        def clear_dummy_models
          ActiveRecord.application_record_class = nil
          dummy_model_names.each do |model_name|
            Object.send(:remove_const, model_name) if Object.const_defined?(model_name)
          end
        end

        def clear_connected_to_stack
          # definitely mucking with Rails private API here
          ActiveSupport::IsolatedExecutionState[:active_record_connected_to_stack] = nil
        end
    end
  end
end

# make TestCase the default
Minitest::Spec.register_spec_type(//, ActiveRecord::Tenanted::TestCase)

# Clean up PostgreSQL test databases at the start of the test suite
ActiveRecord::Tenanted::TestCase.cleanup_postgresql_databases_and_schemas
