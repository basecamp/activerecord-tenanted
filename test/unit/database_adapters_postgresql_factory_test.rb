# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory do
  describe "strategy selection" do
    test "returns Database adapter when database name contains %{tenant}" do
      config_hash = { adapter: "postgresql", database: "test_%{tenant}" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Database, adapter
    end

    test "auto-detects Schema strategy when database name is static" do
      config_hash = { adapter: "postgresql", database: "myapp_production" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema, adapter
    end

    test "returns Database adapter with just %{tenant} as database name" do
      config_hash = {
        adapter: "postgresql",
        database: "%{tenant}",
      }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Database, adapter
    end
  end
end
