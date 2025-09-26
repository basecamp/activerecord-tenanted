# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapter do
  describe ".adapter_for" do
    test "selects correct adapter for sqlite3" do
      adapter = ActiveRecord::Tenanted::DatabaseAdapter.adapter_for(create_config("sqlite3"))
      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::SQLite, adapter
    end

    test "raises error for unsupported adapter" do
      unsupported_config = create_config("mongodb")

      error = assert_raises ActiveRecord::Tenanted::Error do
        ActiveRecord::Tenanted::DatabaseAdapter.adapter_for(unsupported_config)
      end

      assert_includes error.message, "Unsupported database adapter for tenanting: mongodb."
    end
  end

  describe "delegation" do
    ActiveRecord::Tenanted::DatabaseAdapter::ADAPTERS.each do |adapter, adapter_class_name|
      test ".create_database calls adapter's #create_database" do
        adapter_mock = Minitest::Mock.new
        adapter_mock.expect(:create_database, nil)

        adapter_class_name.constantize.stub(:new, adapter_mock) do
          ActiveRecord::Tenanted::DatabaseAdapter.create_database(create_config(adapter))
        end

        assert_mock adapter_mock
      end

      test ".drop_database calls adapter's #drop_database" do
        adapter_mock = Minitest::Mock.new
        adapter_mock.expect(:drop_database, nil)

        adapter_class_name.constantize.stub(:new, adapter_mock) do
          ActiveRecord::Tenanted::DatabaseAdapter.drop_database(create_config(adapter))
        end

        assert_mock adapter_mock
      end

      test ".database_exists? calls adapter's #database_exists?" do
        adapter_mock = Minitest::Mock.new
        adapter_mock.expect(:database_exists?, true)

        result = adapter_class_name.constantize.stub(:new, adapter_mock) do
          ActiveRecord::Tenanted::DatabaseAdapter.database_exists?(create_config(adapter))
        end

        assert_equal true, result
        assert_mock adapter_mock
      end

      test ".list_tenant_databases calls adapter's #list_tenant_databases" do
        adapter_mock = Minitest::Mock.new
        adapter_mock.expect(:list_tenant_databases, [ "foo", "bar" ])

        result = adapter_class_name.constantize.stub(:new, adapter_mock) do
          ActiveRecord::Tenanted::DatabaseAdapter.list_tenant_databases(create_config(adapter))
        end

        assert_equal [ "foo", "bar" ], result
        assert_mock adapter_mock
      end

      test ".validate_tenant_name calls adapter's #validate_tenant_name" do
        adapter_mock = Minitest::Mock.new
        adapter_mock.expect(:validate_tenant_name, nil, [ "tenant1" ])

        adapter_class_name.constantize.stub(:new, adapter_mock) do
          ActiveRecord::Tenanted::DatabaseAdapter.validate_tenant_name(create_config(adapter), "tenant1")
        end

        assert_mock adapter_mock
      end

      test ".acquire_lock calls adapter's #acquire_lock" do
        lock_name = "tenant_creation_test.sqlite3"

        called = nil
        fake_adapter = Object.new
        fake_adapter.define_singleton_method(:acquire_lock) do |id, &blk|
          called = id
          blk&.call
        end

        yielded = false
        result = adapter_class_name.constantize.stub(:new, fake_adapter) do
          ActiveRecord::Tenanted::DatabaseAdapter.acquire_lock(create_config(adapter), lock_name) { yielded = true; :ok }
        end

        assert_equal lock_name, called
        assert_equal true, yielded
        assert_equal :ok, result
      end
    end
  end

  private
    def create_config(adapter)
      ActiveRecord::DatabaseConfigurations::HashConfig.new(
        "test",
        "test_config",
        {
          adapter: adapter,
          database: "db_name",
        }
      )
    end
end
