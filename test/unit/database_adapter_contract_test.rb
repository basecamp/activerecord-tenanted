# frozen_string_literal: true

require "test_helper"

#
#  These tests describe the contract between the gem and a database adapter. They run against the
#  adapter of each database scenario, so a new adapter is covered when its scenarios are added.
#
describe "ActiveRecord::Tenanted::DatabaseAdapters contract" do
  for_each_db_scenario do
    let(:adapter) { adapter_for("foo") }

    describe "#create_database" do
      test "creates the database" do
        assert_not(adapter.database_exist?)

        adapter.create_database

        assert_predicate(adapter, :database_exist?)
      end
    end

    describe "#drop_database" do
      test "drops the database" do
        adapter.create_database

        adapter.drop_database

        assert_not(adapter.database_exist?)
      end

      test "does nothing when the database does not exist" do
        assert_nothing_raised { adapter.drop_database }

        assert_not(adapter.database_exist?)
      end
    end

    describe "#database_ready?" do
      test "is false when the database does not exist" do
        assert_not(adapter.database_ready?)
      end

      test "is true when the database exists" do
        adapter.create_database

        assert_predicate(adapter, :database_ready?)
      end

      test "is false while the ready lock is held" do
        adapter.acquire_ready_lock do
          adapter.create_database

          assert_predicate(adapter, :database_exist?)
          assert_not(adapter.database_ready?)
        end

        assert_predicate(adapter, :database_ready?)
      end
    end

    describe "#acquire_ready_lock" do
      test "yields" do
        yielded = false

        adapter.acquire_ready_lock { yielded = true }

        assert(yielded)
      end

      test "releases the lock when the block raises" do
        adapter.create_database

        assert_raises(RuntimeError) do
          adapter.acquire_ready_lock { raise "boom" }
        end

        assert_predicate(adapter, :database_ready?)
      end
    end

    describe "#tenant_databases" do
      test "is empty when there are no tenant databases" do
        assert_empty(base_config.config_adapter.tenant_databases)
      end

      test "returns the tenant name of each database" do
        adapter_for("foo").create_database
        adapter_for("bar").create_database

        assert_same_elements([ "foo", "bar" ], base_config.config_adapter.tenant_databases)
      end

      test "does not return a tenant whose database is dropped" do
        adapter_for("foo").create_database
        adapter_for("bar").create_database
        adapter_for("foo").drop_database

        assert_equal([ "bar" ], base_config.config_adapter.tenant_databases)
      end

      test "returns only the databases of the test worker" do
        adapter_for("foo").create_database
        base_config.test_worker_id = 99
        adapter_for("bar").create_database

        assert_equal([ "bar" ], base_config.config_adapter.tenant_databases)
      end
    end

    describe "#validate_tenant_name" do
      test "accepts a simple name" do
        assert_nothing_raised { adapter.validate_tenant_name("foo") }
      end

      test "raises BadTenantNameError on a name with a path separator" do
        assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
          adapter.validate_tenant_name("foo/bar")
        end
      end
    end

    describe "#test_workerize" do
      let(:database) { base_config.database }

      test "returns a database name that is specific to the test worker" do
        workerized = adapter.test_workerize(database, 99)

        assert_not_equal(database, workerized)
        assert_not_equal(adapter.test_workerize(database, 98), workerized)
      end

      test "does not add the test worker suffix a second time" do
        workerized = adapter.test_workerize(database, 99)

        assert_equal(workerized, adapter.test_workerize(workerized, 99))
      end
    end
  end

  private
    def adapter_for(tenant_name)
      base_config.new_tenant_config(tenant_name).config_adapter
    end
end
