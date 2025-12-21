# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema do
  let(:db_config) do
    config_hash = { adapter: "postgresql", database: "myapp", schema_name_pattern: "%{tenant}" }
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
      def base_config.configuration_hash; {}; end
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
      def base_config.configuration_hash; {}; end
      def base_config.database_for(tenant_name)
        "test_#{tenant_name}"
      end

      config_hash = { tenant: "bar" }
      result = adapter.prepare_tenant_config_hash(config_hash, base_config, "bar")

      # Base database should replace %{tenant} with "tenanted"
      assert_equal "test_tenanted", result[:database]
    end

    test "uses schema_name_pattern when provided" do
      base_config = Object.new
      def base_config.database; "myapp_development"; end
      def base_config.configuration_hash
        { schema_name_pattern: "tenant_%{tenant}" }
      end
      def base_config.database_for(tenant_name)
        "myapp_development"
      end

      db_config_with_pattern = Object.new
      def db_config_with_pattern.database; "myapp_development"; end
      def db_config_with_pattern.configuration_hash
        { schema_name_pattern: "tenant_%{tenant}" }
      end

      adapter_with_pattern = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_with_pattern)
      config_hash = { tenant: "foo" }
      result = adapter_with_pattern.prepare_tenant_config_hash(config_hash, base_config, "foo")

      # Schema name should use the pattern
      assert_equal "tenant_foo", result[:schema_search_path]
      assert_equal "tenant_foo", result[:tenant_schema]
      # Database name should remain static
      assert_equal "myapp_development", result[:database]
    end

    test "uses static database name with schema_name_pattern" do
      base_config = Object.new
      def base_config.database; "rails_backend_production"; end
      def base_config.configuration_hash
        { schema_name_pattern: "%{tenant}" }
      end

      db_config_with_pattern = Object.new
      def db_config_with_pattern.database; "rails_backend_production"; end
      def db_config_with_pattern.configuration_hash
        { schema_name_pattern: "%{tenant}" }
      end

      adapter_with_pattern = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_with_pattern)
      config_hash = { tenant: "account-abc-123" }
      result = adapter_with_pattern.prepare_tenant_config_hash(config_hash, base_config, "account-abc-123")

      # Schema name should be just the tenant
      assert_equal "account-abc-123", result[:schema_search_path]
      assert_equal "account-abc-123", result[:tenant_schema]
      # Database name should remain static
      assert_equal "rails_backend_production", result[:database]
    end
  end

  describe "identifier_for" do
    test "returns schema name for tenant" do
      result = adapter.identifier_for("foo")
      assert_equal "myapp_foo", result
    end

    test "uses schema_name_pattern when provided" do
      db_config_with_pattern = Object.new
      def db_config_with_pattern.database; "myapp_development"; end
      def db_config_with_pattern.configuration_hash
        { schema_name_pattern: "tenant_%{tenant}" }
      end

      adapter_with_pattern = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_with_pattern)
      result = adapter_with_pattern.identifier_for("foo")
      assert_equal "tenant_foo", result
    end

    test "uses simple pattern with schema_name_pattern" do
      db_config_with_pattern = Object.new
      def db_config_with_pattern.database; "rails_backend_development"; end
      def db_config_with_pattern.configuration_hash
        { schema_name_pattern: "%{tenant}" }
      end

      adapter_with_pattern = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_with_pattern)
      result = adapter_with_pattern.identifier_for("account-abc-123")
      assert_equal "account-abc-123", result
    end
  end

  describe "colocated?" do
    test "returns true for schema-based strategy" do
      assert_equal true, adapter.colocated?
    end
  end

  describe "create_colocated_database" do
    test "delegates to Rails DatabaseTasks.create with base database config" do
      # This test verifies that create_colocated_database fully integrates with Rails
      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config)
      base_db_name = "myapp_tenanted"

      # Verify DatabaseTasks.create is called with the correct config
      ActiveRecord::Tasks::DatabaseTasks.stub :create, ->(config) do
        assert_equal base_db_name, config.database
        assert_equal "test", config.env_name
        assert_equal "postgresql", config.configuration_hash[:adapter]
      end do
        adapter.create_colocated_database
      end
    end

    test "uses static database name when schema_name_pattern is provided" do
      db_config_with_pattern = Object.new
      def db_config_with_pattern.database; "myapp_production"; end
      def db_config_with_pattern.configuration_hash
        { schema_name_pattern: "%{tenant}", adapter: "postgresql" }
      end
      def db_config_with_pattern.env_name; "test"; end
      def db_config_with_pattern.name; "primary"; end

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_with_pattern)

      # Verify DatabaseTasks.create is called with static database name
      ActiveRecord::Tasks::DatabaseTasks.stub :create, ->(config) do
        assert_equal "myapp_production", config.database
        assert_equal "test", config.env_name
        assert_equal "postgresql", config.configuration_hash[:adapter]
      end do
        adapter.create_colocated_database
      end
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

    test "uses static database name when schema_name_pattern is provided" do
      db_config_with_pattern = Object.new
      def db_config_with_pattern.database; "myapp_production"; end
      def db_config_with_pattern.configuration_hash
        { schema_name_pattern: "%{tenant}", adapter: "postgresql" }
      end
      def db_config_with_pattern.env_name; "test"; end
      def db_config_with_pattern.name; "primary"; end

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_with_pattern)

      # Verify DatabaseTasks.drop is called with static database name
      ActiveRecord::Tasks::DatabaseTasks.stub :drop, ->(config) do
        assert_equal "myapp_production", config.database
        assert_equal "test", config.env_name
        assert_equal "postgresql", config.configuration_hash[:adapter]
      end do
        adapter.drop_colocated_database
      end
    end
  end
end
