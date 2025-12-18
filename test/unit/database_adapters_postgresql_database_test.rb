# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Database do
  let(:db_config) do
    config_hash = { adapter: "postgresql", database: "myapp_%{tenant}", postgresql_strategy: "database" }
    ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)
  end
  let(:adapter) { ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Database.new(db_config) }

  describe "database_path" do
    test "returns database from config" do
      assert_equal "myapp_%{tenant}", adapter.database_path
    end
  end

  describe "validate_tenant_name" do
    test "raises error if schema_search_path is configured" do
      config_hash = {
        adapter: "postgresql",
        database: "myapp_%{tenant}",
        postgresql_strategy: "database",
        schema_search_path: "myapp_foo",
      }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)
      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Database.new(db_config)

      error = assert_raises(ActiveRecord::Tenanted::ConfigurationError) do
        adapter.validate_tenant_name("foo")
      end

      assert_match(/does not use `schema_search_path`/, error.message)
      assert_match(/postgresql_strategy: schema/, error.message)
    end

    test "raises error if tenant_schema is configured" do
      config_hash = {
        adapter: "postgresql",
        database: "myapp_%{tenant}",
        postgresql_strategy: "database",
        tenant_schema: "myapp_foo",
      }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)
      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Database.new(db_config)

      error = assert_raises(ActiveRecord::Tenanted::ConfigurationError) do
        adapter.validate_tenant_name("foo")
      end

      assert_match(/does not use `tenant_schema`/, error.message)
      assert_match(/postgresql_strategy: schema/, error.message)
    end

    test "allows valid configuration without schema-specific settings" do
      assert_nothing_raised do
        adapter.validate_tenant_name("foo")
        adapter.validate_tenant_name("bar")
      end
    end
  end

  describe "identifier_for" do
    test "returns database name for tenant" do
      result = adapter.identifier_for("foo")
      assert_equal "myapp_foo", result
    end
  end
end
