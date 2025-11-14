# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseTasks do
  describe "#drop_tenant" do
    for_each_scenario do
      setup do
        base_config.new_tenant_config("foo").config_adapter.create_database
      end

      test "drops the specified tenant database" do
        config = base_config.new_tenant_config("foo")
        assert_predicate config.config_adapter, :database_exist?

        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).drop_tenant("foo")

        assert_not_predicate config.config_adapter, :database_exist?
      end
    end
  end

  describe "#drop_all" do
    for_each_scenario do
      let(:tenants) { %w[foo bar baz] }

      setup do
        tenants.each do |tenant|
          TenantedApplicationRecord.create_tenant(tenant)
        end
      end

      test "drops all tenant databases" do
        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).drop_all

        tenants.each do |tenant|
          config = base_config.new_tenant_config(tenant)
          assert_not_predicate config.config_adapter, :database_exist?
        end
      end
    end
  end

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

      test "skips migration when no pending migrations" do
        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")

        ActiveRecord::Migration.verbose = true
        assert_silent do
          ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")
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

      test "does not recreate schema cache when up to date" do
        config = base_config.new_tenant_config("foo")
        schema_cache_path = ActiveRecord::Tasks::DatabaseTasks.cache_dump_filename(config)

        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")
        original_mtime = File.mtime(schema_cache_path)

        sleep 0.1
        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant("foo")

        assert_equal original_mtime, File.mtime(schema_cache_path)
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
end
