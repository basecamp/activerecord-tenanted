# frozen_string_literal: true

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require "rails"
require "rails/test_help" # should be before active_record to avoid schema/fixture setup
require "active_record"

require "minitest/spec"

require_relative "../lib/active_record/tenanted"

module ActiveRecord
  module Tenanted
    class TestCase < ActiveSupport::TestCase
      extend Minitest::Spec::DSL

      class << self
        def for_each_db_config(&block)
          Dir.glob("#{__dir__}/scenarios/*/database.yml").each do |db_config_path|
            db_config_name = File.basename(File.dirname(db_config_path))

            describe "#{db_config_name} db config" do
              setup do
                @storage = Dir.mktmpdir(db_config_name)
                db_config_yml = sprintf(File.read(db_config_path),
                                        __dir__: __dir__, storage: @storage, scenario: "TODO")
                db_config = YAML.load(db_config_yml)

                @old_configurations = ActiveRecord::Base.configurations
                ActiveRecord::Base.configurations = db_config
              end

              teardown do
                ActiveRecord::Base.configurations = @old_configurations
                FileUtils.remove_entry @storage
              end

              instance_eval(&block)
            end
          end
        end
      end
    end
  end
end

# make TestCase the default
Minitest::Spec.register_spec_type(//, ActiveRecord::Tenanted::TestCase)
