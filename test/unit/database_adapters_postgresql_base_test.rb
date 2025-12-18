# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Base do
  let(:db_config) do
    config_hash = { adapter: "postgresql", database: "myapp_%{tenant}" }
    ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)
  end
  let(:adapter) { ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Base.new(db_config) }

  describe "abstract methods" do
    test "tenant_databases raises NotImplementedError" do
      error = assert_raises(NotImplementedError) do
        adapter.tenant_databases
      end
      assert_match(/must implement #tenant_databases/, error.message)
    end

    test "create_database raises NotImplementedError" do
      error = assert_raises(NotImplementedError) do
        adapter.create_database
      end
      assert_match(/must implement #create_database/, error.message)
    end

    test "drop_database raises NotImplementedError" do
      error = assert_raises(NotImplementedError) do
        adapter.drop_database
      end
      assert_match(/must implement #drop_database/, error.message)
    end

    test "database_exist? raises NotImplementedError" do
      error = assert_raises(NotImplementedError) do
        adapter.database_exist?
      end
      assert_match(/must implement #database_exist\?/, error.message)
    end

    test "database_path raises NotImplementedError" do
      error = assert_raises(NotImplementedError) do
        adapter.database_path
      end
      assert_match(/must implement #database_path/, error.message)
    end
  end

  describe "path_for" do
    test "returns name as-is" do
      database = "myapp_production"
      expected = "myapp_production"
      assert_equal(expected, adapter.path_for(database))
    end
  end

  describe "test_workerize" do
    test "appends test worker id to name" do
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
    test "allows valid tenant names" do
      assert_nothing_raised do
        adapter.validate_tenant_name("tenant1")
        adapter.validate_tenant_name("tenant_123")
        adapter.validate_tenant_name("tenant$foo")
        adapter.validate_tenant_name("tenant-name")  # hyphens are allowed
      end
    end

    test "raises error for identifiers that are too long" do
      # Max is 63 characters, so with "myapp_" prefix (6 chars), tenant name can be max 57 chars
      # Testing with 58 chars should fail (6 + 58 = 64 > 63)
      long_name = "a" * 58
      error = assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
        adapter.validate_tenant_name(long_name)
      end
      assert_match(/too long/, error.message)
    end

    test "allows identifiers at exactly 63 characters" do
      # With "myapp_" prefix (6 chars), tenant name of 57 chars = exactly 63 total
      max_length_name = "a" * 57
      assert_nothing_raised do
        adapter.validate_tenant_name(max_length_name)
      end
    end

    test "raises error for identifiers with invalid characters" do
      error = assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
        adapter.validate_tenant_name("tenant.name")  # dots are not allowed
      end
      assert_match(/invalid characters/, error.message)
    end

    test "raises error for identifiers starting with a number" do
      # Create a config where the pattern would result in an identifier starting with a number
      config_hash = { adapter: "postgresql", database: "%{tenant}_schema" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)
      adapter = ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Base.new(db_config)

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

  describe "database_ready?" do
    test "delegates to database_exist?" do
      # Since database_exist? is abstract, we can't test this fully
      # but we can verify it's defined
      assert_respond_to adapter, :database_ready?
    end
  end

  describe "acquire_ready_lock" do
    test "yields to block" do
      block_called = false
      adapter.acquire_ready_lock do
        block_called = true
      end
      assert block_called
    end
  end

  describe "ensure_database_directory_exists" do
    test "returns true" do
      assert_equal true, adapter.ensure_database_directory_exists
    end
  end
end
