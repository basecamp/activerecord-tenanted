# frozen_string_literal: true

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require "rails"
require "rails/test_help" # should be before active_record is loaded to avoid schema/fixture setup

require_relative "../lib/active_record/tenanted"

# turn off the Rails integrations
ActiveRecord::Tenanted.connection_class = nil

require_relative "dummy/config/environment"
require "minitest/spec"

module ActiveRecord
  module Tenanted
    class TestCase < ActiveSupport::TestCase
      extend Minitest::Spec::DSL

      class << self
        def for_each_scenario(s = all_scenarios, &block)
          s.each do |db_scenario, model_scenarios|
            with_db_scenario(db_scenario) do
              model_scenarios.each do |model_scenario|
                with_model_scenario(model_scenario, &block)
              end
            end
          end
        end

        def all_scenarios
          Dir.glob(File.join(__dir__, "scenarios", "*", "database.yml"))
            .each_with_object({}) do |db_config_path, scenarios|
            db_config_dir = File.dirname(db_config_path)
            db_scenario = File.basename(db_config_dir)
            model_files = Dir.glob(File.join(db_config_dir, "*.rb"))

            scenarios[db_scenario] = model_files.map { File.basename(_1, ".*") }
          end
        end

        def with_db_scenario(db_scenario, &block)
          db_config_path = File.join(__dir__, "scenarios", db_scenario.to_s, "database.yml")
          raise "Could not find scenario db config: #{db_config_path}" unless File.exist?(db_config_path)

          describe "scenario::#{db_scenario}" do
            @db_config_dir = db_config_dir = File.dirname(db_config_path)

            let(:storage_path) { Dir.mktmpdir("test-active_record-tenanted-") }

            setup do
              db_config_yml = sprintf(File.read(db_config_path),
                                      storage: storage_path,
                                      scenario: db_config_dir)
              db_config = YAML.load(db_config_yml)

              @old_configurations = ActiveRecord::Base.configurations
              ActiveRecord::Base.configurations = db_config
            end

            teardown do
              ActiveRecord::Base.configurations = @old_configurations
              FileUtils.remove_entry storage_path
              ActiveRecord::Base.connection_handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
            end

            instance_eval(&block)
          end
        end

        def with_model_scenario(models_scenario, &block)
          models_scenario_file = File.join(@db_config_dir, "#{models_scenario}.rb")
          raise "Could not find model scenario: #{models_scenario_file}" unless File.exist?(models_scenario_file)

          describe models_scenario do
            setup do
              clear_dummy_models
              create_fake_record
              load models_scenario_file
              @migration_verbose_was, ActiveRecord::Migration.verbose = ActiveRecord::Migration.verbose, false
            end

            teardown do
              ActiveRecord::Migration.verbose = @migration_verbose_was
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
      end

      def capture_log
        StringIO.new.tap do |log|
          logger_was, ActiveRecord::Base.logger = ActiveRecord::Base.logger, ActiveSupport::Logger.new(log)
          yield
        ensure
          ActiveRecord::Base.logger = logger_was
        end
      end

      private def create_fake_record
        # emulate models like ActiveStorage::Record that inherit directly from AR::Base
        Object.const_set(:FakeRecord, Class.new(ActiveRecord::Base))
      end

      private def dummy_model_names
        %w[TenantedApplicationRecord User Post SharedApplicationRecord Announcement FakeRecord]
      end

      private def clear_dummy_models
        ActiveRecord.application_record_class = nil
        dummy_model_names.each do |model_name|
          Object.send(:remove_const, model_name) if Object.const_defined?(model_name)
        end
      end

      private def clear_connected_to_stack
        # definitely mucking with Rails private API here
        ActiveSupport::IsolatedExecutionState[:active_record_connected_to_stack] = nil
      end
    end
  end
end

# make TestCase the default
Minitest::Spec.register_spec_type(//, ActiveRecord::Tenanted::TestCase)
