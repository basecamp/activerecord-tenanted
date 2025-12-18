# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory do
  describe "strategy selection" do
    test "returns Schema adapter when strategy is 'schema'" do
      config_hash = { adapter: "postgresql", database: "test_%{tenant}", postgresql_strategy: "schema" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema, adapter
    end

    test "returns Database adapter when strategy is 'database'" do
      config_hash = { adapter: "postgresql", database: "test_%{tenant}", postgresql_strategy: "database" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Database, adapter
    end

    test "returns Schema adapter when strategy is not specified (default)" do
      config_hash = { adapter: "postgresql", database: "test_%{tenant}" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema, adapter
    end

    test "raises error for invalid strategy" do
      config_hash = { adapter: "postgresql", database: "test_%{tenant}", postgresql_strategy: "invalid" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      error = assert_raises(ActiveRecord::Tenanted::UnsupportedDatabaseError) do
        ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)
      end

      assert_match(/Invalid PostgreSQL strategy/, error.message)
      assert_match(/"invalid"/, error.message)
      assert_match(/Valid options are/, error.message)
    end

    test "suggests correct strategy for typos" do
      config_hash = { adapter: "postgresql", database: "test_%{tenant}", postgresql_strategy: "schemas" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      error = assert_raises(ActiveRecord::Tenanted::UnsupportedDatabaseError) do
        ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)
      end

      assert_match(/Did you mean "schema"\?/, error.message)
    end

    test "handles strategy as symbol" do
      config_hash = { adapter: "postgresql", database: "test_%{tenant}", postgresql_strategy: :database }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Database, adapter
    end
  end

  describe "suggest_strategy" do
    test "suggests 'schema' for 'schemas'" do
      suggestion = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.suggest_strategy("schemas")
      assert_equal "schema", suggestion
    end

    test "suggests 'database' for 'databases'" do
      suggestion = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.suggest_strategy("databases")
      assert_equal "database", suggestion
    end

    test "suggests closest match for completely wrong input" do
      suggestion = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Factory.suggest_strategy("xyz")
      assert_includes [ "schema", "database" ], suggestion
    end
  end
end
