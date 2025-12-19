# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema do
  let(:db_config) do
    config_hash = { adapter: "postgresql", database: "myapp_%{tenant}", postgresql_strategy: "schema" }
    ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)
  end
  let(:adapter) { ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config) }

  describe "database_path" do
    test "returns tenant_schema from config if present" do
      db_config_with_schema = Object.new
      def db_config_with_schema.database; "myapp_%{tenant}"; end
      def db_config_with_schema.configuration_hash
        { tenant_schema: "myapp_foo" }
      end

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_with_schema)
      assert_equal "myapp_foo", adapter.database_path
    end

    test "returns database pattern if tenant_schema not present" do
      assert_equal "myapp_%{tenant}", adapter.database_path
    end
  end

  describe "prepare_tenant_config_hash" do
    test "adds schema-specific configuration" do
      base_config = Object.new
      def base_config.database; "myapp_%{tenant}"; end
      def base_config.database_for(tenant_name)
        "myapp_#{tenant_name}"
      end

      config_hash = { tenant: "foo", database: "myapp_foo" }
      result = adapter.prepare_tenant_config_hash(config_hash, base_config, "foo")

      assert_equal "myapp_foo", result[:schema_search_path]
      assert_equal "myapp_foo", result[:tenant_schema]
      assert_equal "myapp_tenanted", result[:database]
    end

    test "uses consistent base database name" do
      base_config = Object.new
      def base_config.database; "test_%{tenant}"; end
      def base_config.database_for(tenant_name)
        "test_#{tenant_name}"
      end

      config_hash = { tenant: "bar" }
      result = adapter.prepare_tenant_config_hash(config_hash, base_config, "bar")

      # Base database should replace %{tenant} with "tenanted"
      assert_equal "test_tenanted", result[:database]
    end
  end

  describe "identifier_for" do
    test "returns schema name for tenant" do
      result = adapter.identifier_for("foo")
      assert_equal "myapp_foo", result
    end
  end

  describe "drop_colocated_database" do
    test "delegates to Rails DatabaseTasks.drop with base database config" do
      # This test verifies that drop_colocated_database fully integrates with Rails
      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config)
      base_db_name = "myapp_tenanted"

      # Verify DatabaseTasks.drop is called with the correct config
      ActiveRecord::Tasks::DatabaseTasks.stub :drop, ->(config) do
        assert_equal base_db_name, config.database
        assert_equal "test", config.env_name
        assert_equal "postgresql", config.configuration_hash[:adapter]
      end do
        adapter.drop_colocated_database
      end
    end
  end
end
