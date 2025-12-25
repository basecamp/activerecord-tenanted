# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema do
  let(:db_config) do
    config_hash = { adapter: "postgresql", database: "myapp" }
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

    test "raises error if tenant_schema not present" do
      db_config_dynamic = Object.new
      def db_config_dynamic.database; "myapp_development"; end
      def db_config_dynamic.configuration_hash; {}; end

      adapter_dynamic = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_dynamic)

      error = assert_raises(ActiveRecord::Tenanted::NoTenantError) do
        adapter_dynamic.database_path
      end

      assert_match(/tenant_schema not set/, error.message)
    end
  end

  describe "prepare_tenant_config_hash" do
    test "adds schema-specific configuration with account- prefix" do
      base_config = Object.new
      def base_config.database; "myapp_development"; end
      def base_config.configuration_hash; {}; end

      config_hash = { tenant: "foo", database: "myapp_development" }
      result = adapter.prepare_tenant_config_hash(config_hash, base_config, "foo")

      assert_equal "account-foo", result[:schema_search_path]
      assert_equal "account-foo", result[:tenant_schema]
      assert_equal "myapp_development", result[:database]
    end

    test "uses static database name" do
      base_config = Object.new
      def base_config.database; "rails_backend_production"; end
      def base_config.configuration_hash; {}; end

      config_hash = { tenant: "bar" }
      result = adapter.prepare_tenant_config_hash(config_hash, base_config, "bar")

      # Schema name should use account- prefix
      assert_equal "account-bar", result[:schema_search_path]
      assert_equal "account-bar", result[:tenant_schema]
      # Database name should remain static
      assert_equal "rails_backend_production", result[:database]
    end

    test "creates schema name with account- prefix for complex tenant" do
      base_config = Object.new
      def base_config.database; "myapp_production"; end
      def base_config.configuration_hash; {}; end

      config_hash = { tenant: "abc123" }
      result = adapter.prepare_tenant_config_hash(config_hash, base_config, "abc123")

      # Schema name should use account- prefix
      assert_equal "account-abc123", result[:schema_search_path]
      assert_equal "account-abc123", result[:tenant_schema]
      # Database name should remain static
      assert_equal "myapp_production", result[:database]
    end
  end

  describe "identifier_for" do
    test "returns schema name with account- prefix" do
      db_config_static = Object.new
      def db_config_static.database; "myapp_development"; end
      def db_config_static.configuration_hash; {}; end

      adapter_static = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_static)
      result = adapter_static.identifier_for("foo")
      assert_equal "account-foo", result
    end

    test "uses account- prefix for complex tenant names" do
      db_config_static = Object.new
      def db_config_static.database; "myapp_development"; end
      def db_config_static.configuration_hash; {}; end

      adapter_static = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_static)
      result = adapter_static.identifier_for("abc123")
      assert_equal "account-abc123", result
    end
  end

  describe "colocated?" do
    test "returns true for schema-based strategy" do
      assert_equal true, adapter.colocated?
    end
  end

  describe "create_colocated_database" do
    test "delegates to Rails DatabaseTasks.create with static database config" do
      # This test verifies that create_colocated_database fully integrates with Rails
      db_config_static = Object.new
      def db_config_static.database; "myapp_development"; end
      def db_config_static.configuration_hash; { adapter: "postgresql" }; end
      def db_config_static.env_name; "test"; end
      def db_config_static.name; "primary"; end

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_static)
      base_db_name = "myapp_development"

      # Verify DatabaseTasks.create is called with the correct config
      ActiveRecord::Tasks::DatabaseTasks.stub :create, ->(config) do
        assert_equal base_db_name, config.database
        assert_equal "test", config.env_name
        assert_equal "postgresql", config.configuration_hash[:adapter]
      end do
        adapter.create_colocated_database
      end
    end

    test "uses static database name" do
      db_config_static = Object.new
      def db_config_static.database; "myapp_production"; end
      def db_config_static.configuration_hash
        { adapter: "postgresql" }
      end
      def db_config_static.env_name; "test"; end
      def db_config_static.name; "primary"; end

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_static)

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
    test "delegates to Rails DatabaseTasks.drop with static database config" do
      # This test verifies that drop_colocated_database fully integrates with Rails
      db_config_static = Object.new
      def db_config_static.database; "myapp_development"; end
      def db_config_static.configuration_hash; { adapter: "postgresql" }; end
      def db_config_static.env_name; "test"; end
      def db_config_static.name; "primary"; end

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_static)
      base_db_name = "myapp_development"

      # Verify DatabaseTasks.drop is called with the correct config
      ActiveRecord::Tasks::DatabaseTasks.stub :drop, ->(config) do
        assert_equal base_db_name, config.database
        assert_equal "test", config.env_name
        assert_equal "postgresql", config.configuration_hash[:adapter]
      end do
        adapter.drop_colocated_database
      end
    end

    test "uses static database name" do
      db_config_static = Object.new
      def db_config_static.database; "myapp_production"; end
      def db_config_static.configuration_hash
        { adapter: "postgresql" }
      end
      def db_config_static.env_name; "test"; end
      def db_config_static.name; "primary"; end

      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema.new(db_config_static)

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
