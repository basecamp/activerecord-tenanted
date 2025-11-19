# frozen_string_literal: true

require "test_helper"
require "rake"

describe ActiveRecord::Tenanted::DatabaseTasks do
  describe ".migrate_tenant" do
    for_each_scenario do
      setup do
        base_config.new_tenant_config("foo").config_adapter.create_database
      end

      test "database should be created" do
        config = base_config.new_tenant_config("bar")

        assert_not_predicate(config.config_adapter, :database_exist?)

        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("bar")

        assert_predicate(config.config_adapter, :database_exist?)
      end

      test "database should be migrated" do
        ActiveRecord::Migration.verbose = true

        assert_output(/migrating.*create_table/m, nil) do
          ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")
        end

        config = base_config.new_tenant_config("foo")
        ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
          assert_equal(20250203191115, conn.pool.migration_context.current_version)
        end
      end

      test "database schema file should be created" do
        config = base_config.new_tenant_config("foo")
        schema_path = ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(config)

        assert_not(File.exist?(schema_path))

        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")

        assert(File.exist?(schema_path))
      end

      test "database schema cache file should be created" do
        config = base_config.new_tenant_config("foo")
        schema_cache_path = ActiveRecord::Tasks::DatabaseTasks.cache_dump_filename(config)

        assert_not(File.exist?(schema_cache_path))

        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")

        assert(File.exist?(schema_cache_path))
      end

      describe "when schema dump file exists" do
        setup { with_schema_dump_file }

        test "database should load the schema dump file" do
          ActiveRecord::Migration.verbose = true

          assert_silent do
            ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")
          end

          config = base_config.new_tenant_config("foo")
          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
            assert_equal(20250203191115, conn.pool.migration_context.current_version)
          end
        end

        describe "and there are pending migrations" do
          setup { with_new_migration_file }

          test "it runs the migrations after loading the schema" do
            ActiveRecord::Migration.verbose = true

            assert_output(/migrating.*add_column/m, nil) do
              ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")
            end

            config = base_config.new_tenant_config("foo")
            ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
              assert_equal(20250213005959, conn.pool.migration_context.current_version)
            end
          end
        end
      end

      describe "when an outdated schema cache dump file exists" do
        setup { with_schema_cache_dump_file }
        setup { with_new_migration_file }

        test "remaining migrations are applied" do
          ActiveRecord::Migration.verbose = true

          assert_output(/migrating.*add_column/m, nil) do
            ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")
          end

          config = base_config.new_tenant_config("foo")
          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
            assert_equal(20250213005959, conn.pool.migration_context.current_version)
          end
        end
      end
    end
  end

  describe ".migrate_all" do
    for_each_scenario do
      let(:tenants) { %w[foo bar baz] }

      setup do
        tenants.each do |tenant|
          TenantedApplicationRecord.create_tenant(tenant)
        end

        with_new_migration_file
      end

      test "migrates all existing tenants" do
        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_all

        tenants.each do |tenant|
          config = base_config.new_tenant_config(tenant)
          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
            assert_equal(20250213005959, conn.pool.migration_context.current_version)
          end
        end
      end
    end
  end

  describe ".rollback_tenant" do
    for_each_scenario do
      setup do
        with_new_migration_file
        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")
      end

      test "rolls back the most recent migration" do
        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).rollback_tenant("foo")

        config = base_config.new_tenant_config("foo")
        ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
          assert_equal(20250203191115, conn.pool.migration_context.current_version)
        end
      end

      test "accepts a custom step count" do
        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).rollback_tenant("foo", step: 2)

        config = base_config.new_tenant_config("foo")
        ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
          assert_equal(0, conn.pool.migration_context.current_version)
        end
      end
    end
  end

  describe ".rollback_all" do
    for_each_scenario do
      let(:tenants) { %w[foo bar baz] }

      setup do
        tenants.each do |tenant|
          TenantedApplicationRecord.create_tenant(tenant)
        end

        with_new_migration_file
        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_all
      end

      test "rolls back all existing tenants" do
        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).rollback_all

        tenants.each do |tenant|
          config = base_config.new_tenant_config(tenant)
          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
            assert_equal(20250203191115, conn.pool.migration_context.current_version)
          end
        end
      end
    end
  end

  describe ".wrap_rails_task" do
    setup do
      @original_rake_application = Rake.application
      Rake.application = Rake::Application.new
      ActiveRecord::Tenanted::DatabaseTasks.instance_variable_set(:@wrapped_rails_tasks, nil)
    end

    teardown do
      ActiveRecord::Tenanted::DatabaseTasks.instance_variable_set(:@wrapped_rails_tasks, nil)
      Rake.application = @original_rake_application
    end

    test "skips the original task when the guard returns false" do
      Rake::Task.define_task("db:rollback") { raise "should not run" }

      ActiveRecord::Tenanted::DatabaseTasks.send(:wrap_rails_task, "db:rollback") { false }

      Rake::Task["db:rollback"].invoke
      assert(true)
    end

    test "runs the original task when the guard returns true" do
      Rake::Task.define_task("db:rollback") { raise "original task ran" }

      ActiveRecord::Tenanted::DatabaseTasks.send(:wrap_rails_task, "db:rollback") { true }

      error = assert_raises(RuntimeError) { Rake::Task["db:rollback"].invoke }
      assert_equal("original task ran", error.message)
    end

    test "guard skips original db:rollback when no default configurations exist" do
      Rake::Task.define_task("db:rollback") { raise "should not run" }

      fake_configs = Class.new do
        def configs_for(...)
          []
        end
      end.new

      ActiveRecord::Base.stub(:configurations, fake_configs) do
        ActiveRecord::Tenanted::DatabaseTasks.send(:wrap_rails_task, "db:rollback") do
          ActiveRecord::Tenanted::DatabaseTasks.send(:default_database_tasks_present?)
        end

        Rake::Task["db:rollback"].invoke
      end

      assert(true)
    end
  end
end
