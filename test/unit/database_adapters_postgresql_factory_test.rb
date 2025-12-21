# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory do
  describe "strategy selection" do
    test "returns Database adapter when schema_name_pattern is not set" do
      config_hash = { adapter: "postgresql", database: "test_%{tenant}" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Database, adapter
    end

    test "auto-detects Schema strategy when schema_name_pattern is present" do
      config_hash = { adapter: "postgresql", database: "myapp_production", schema_name_pattern: "%{tenant}" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema, adapter
    end

    test "works with complex schema_name_pattern" do
      config_hash = {
        adapter: "postgresql",
        database: "rails_backend_development",
        schema_name_pattern: "tenant_%{tenant}",
      }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema, adapter
    end
  end
end
