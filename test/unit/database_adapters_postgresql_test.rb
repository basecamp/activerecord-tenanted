# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL do
  let(:adapter) { ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL.new(Object.new) }

  describe "path_for" do
    test "returns database name as-is" do
      database = "myapp_production"
      expected = "myapp_production"
      assert_equal(expected, adapter.path_for(database))
    end
  end

  describe "test_workerize" do
    test "appends test worker id to database name" do
      db = "myapp_test"
      test_worker_id = 1
      expected = "myapp_test_1"
      assert_equal(expected, adapter.test_workerize(db, test_worker_id))
    end

    test "does not double-suffix if already present" do
      db = "myapp_test_1"
      test_worker_id = 1
      expected = "myapp_test_1"
      assert_equal(expected, adapter.test_workerize(db, test_worker_id))
    end
  end

  describe "validate_tenant_name" do
    let(:db_config) do
      config_hash = { adapter: "postgresql", database: "myapp_%{tenant}" }
      ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)
    end
    let(:adapter) { ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL.new(db_config) }

    test "allows valid tenant names" do
      assert_nothing_raised do
        adapter.validate_tenant_name("tenant1")
        adapter.validate_tenant_name("tenant_123")
        adapter.validate_tenant_name("tenant$foo")
        adapter.validate_tenant_name("tenant-name")  # hyphens are allowed
      end
    end

    test "raises error for database names that are too long" do
      # Max is 63 characters, so with "myapp_" prefix (6 chars), tenant name can be max 57 chars
      # Testing with 58 chars should fail (6 + 58 = 64 > 63)
      long_name = "a" * 58
      error = assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
        adapter.validate_tenant_name(long_name)
      end
      assert_match(/too long/, error.message)
    end

    test "allows database names at exactly 63 characters" do
      # With "myapp_" prefix (6 chars), tenant name of 57 chars = exactly 63 total
      max_length_name = "a" * 57
      assert_nothing_raised do
        adapter.validate_tenant_name(max_length_name)
      end
    end

    test "raises error for database names with invalid characters" do
      error = assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
        adapter.validate_tenant_name("tenant.name")  # dots are not allowed
      end
      assert_match(/invalid characters/, error.message)
    end

    test "raises error for schema names starting with a number" do
      # Create a config where the pattern would result in a schema starting with a number
      config_hash = { adapter: "postgresql", database: "%{tenant}_schema" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)
      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL.new(db_config)

      error = assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
        adapter.validate_tenant_name("1tenant")
      end
      assert_match(/must start with a letter or underscore/, error.message)
    end

    test "allows special validation patterns" do
      assert_nothing_raised do
        adapter.validate_tenant_name("%")
        adapter.validate_tenant_name("(.+)")
      end
    end
  end
end
