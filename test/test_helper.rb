# frozen_string_literal: true

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require "rails"
require "rails/test_help" # should be before active_record is loaded to avoid schema/fixture setup

require_relative "../lib/active_record/tenanted"

require_relative "dummy/config/environment"
require "minitest/spec"

module ActiveRecord
  module Tenanted
    class TestCase < ActiveSupport::TestCase
      extend Minitest::Spec::DSL

      class << self
        def with_db_config(name_or_path_to_yml, &block)
          name_or_path_to_yml = name_or_path_to_yml.to_s
          if File.exist?(name_or_path_to_yml)
            db_config_path = name_or_path_to_yml
            db_config_name = File.basename(File.dirname(db_config_path))
          else
            db_config_name = name_or_path_to_yml
            db_config_path = File.join(__dir__, "scenarios", db_config_name, "database.yml")
            raise "Could not find scenario db config: #{db_config_path}" unless File.exist?(db_config_path)
          end

          describe "scenario::#{db_config_name}" do
            @db_config_path = File.dirname(db_config_path)

            let(:storage_dir) { Dir.mktmpdir(db_config_name) }
            let(:scenario_name) { "unknown" }

            setup do
              db_config_yml = sprintf(File.read(db_config_path),
                                      __dir__: __dir__, storage: storage_dir)
              db_config = YAML.load(db_config_yml)

              @old_configurations = ActiveRecord::Base.configurations
              ActiveRecord::Base.configurations = db_config
            end

            teardown do
              ActiveRecord::Base.configurations = @old_configurations
              FileUtils.remove_entry storage_dir
            end

            instance_eval(&block)
          end
        end

        def with_each_db_config(&block)
          Dir.glob(File.join(__dir__, "scenarios", "*", "database.yml")).each do |db_config_path|
            with_db_config(db_config_path, &block)
          end
        end

        def with_scenario(db_config_name, model_scenario_name, &block)
          model_scenario_file = File.join(__dir__, "scenarios", db_config_name.to_s, "#{model_scenario_name}.rb")
          raise "Cannot find scenario: #{model_scenario_file}" unless File.exist?(model_scenario_file)

          with_db_config(db_config_name) do
            with_scenario_given_db_config(model_scenario_file, &block)
          end
        end

        def with_scenario_given_db_config(models_scenario_file, &block)
          models_scenario_name = File.basename(models_scenario_file, ".*")

          describe models_scenario_name do
            let(:scenario_name) { models_scenario_name }

            setup do
              clear_dummy_models
              load models_scenario_file
            end

            teardown do
              clear_dummy_models
            end

            instance_eval(&block)
          end
        end

        def with_each_scenario(&block)
          with_each_db_config do |db_config|
            Dir.glob(File.join(@db_config_path, "*.rb")).each do |models_scenario_file|
              with_scenario_given_db_config(models_scenario_file, &block)
            end
          end
        end
      end

      private def dummy_model_names
        %w[TenantedApplicationRecord SharedApplicationRecord User Announcement]
      end

      private def clear_dummy_models
        ActiveRecord.application_record_class = nil
        dummy_model_names.each do |model_name|
          Object.send(:remove_const, model_name) if Object.const_defined?(model_name)
        end
      end
    end
  end
end

# make TestCase the default
Minitest::Spec.register_spec_type(//, ActiveRecord::Tenanted::TestCase)
