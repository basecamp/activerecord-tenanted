# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseConfigurations do
  describe Rails do
    with_scenario(:primary_named_db, :primary_record) do
      test "instantiates a BaseConfig for the tenanted database" do
        assert_equal(
          {
            "tenanted" => ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig,
            "shared" => ActiveRecord::DatabaseConfigurations::HashConfig,
          },
          all_configs.each_with_object({}) { |c, h| h[c.name] = c.class }
        )
      end

      test "the BaseConfig has tasks turned off by default" do
        assert_not base_config.database_tasks?
      end
    end
  end

  describe "BaseConfig" do
    let(:database) { "database" }
    let(:config) do
      ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig.new(
        "test",
        "test_tenant",
        { adapter: adapter, database: database }
      )
    end

    describe "SQLite" do
      let(:adapter) { "sqlite3" }
      let(:dir) { Dir.mktmpdir }

      describe "database_for" do
        describe "validation" do
          test "raises if the tenant name contains a path separator" do
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo/bar") }
          end

          test "raises if the tenant name contains a quote or double-quote or back-quote" do
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo'bar") }
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo\"bar") }
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo`bar") }
          end
        end

        def assert_all_tenants_found
          Dir.chdir(dir) do
            [ "foo", "bar", "baz" ].each do |tenant|
              path = config.config_adapter.path_for(config.database_for(tenant))
              FileUtils.mkdir_p(File.dirname(path))
              FileUtils.touch(path)
            end

            assert_equal(Set.new(config.tenants), Set.new([ "foo", "bar", "baz" ]))
          end
        end

        describe "file path" do
          let(:database) { "storage/db/tenanted/%{tenant}/main.sqlite3" }

          test "returns the path for a tenant" do
            assert_equal("storage/db/tenanted/foo/main.sqlite3", config.database_for("foo"))
          end

          test "returns all tenants" do
            assert_all_tenants_found
          end

          describe "parallel test workers" do
            setup { config.test_worker_id = 99 }

            test "returns the worker-specific path for a tenant" do
              assert_equal("storage/db/tenanted/foo/main.sqlite3_99", config.database_for("foo"))
            end

            test "parallel test worker returns all tenants" do
              assert_all_tenants_found
            end
          end
        end

        describe "absolute URI" do
          let(:database) { "file:#{dir}/storage/db/tenanted/%{tenant}/main.sqlite3" }

          test "returns the path for a tenant" do
            assert_equal("file:#{dir}/storage/db/tenanted/foo/main.sqlite3", config.database_for("foo"))
          end

          test "returns all tenants" do
            assert_all_tenants_found
          end

          describe "parallel test workers" do
            setup { config.test_worker_id = 99 }

            test "returns the worker-specific path for a tenant" do
              assert_equal("file:#{dir}/storage/db/tenanted/foo/main.sqlite3_99", config.database_for("foo"))
            end

            test "parallel test worker returns all tenants" do
              assert_all_tenants_found
            end
          end
        end

        describe "absolute URI with query params" do
          let(:database) { "file:#{dir}/storage/db/tenanted/%{tenant}/main.sqlite3?vfs=unix-dotfile" }

          test "returns the path for a tenant" do
            assert_equal("file:#{dir}/storage/db/tenanted/foo/main.sqlite3?vfs=unix-dotfile", config.database_for("foo"))
          end

          test "returns all tenants" do
            assert_all_tenants_found
          end

          describe "parallel test workers" do
            setup { config.test_worker_id = 99 }

            test "returns the worker-specific path for a tenant" do
              assert_equal("file:#{dir}/storage/db/tenanted/foo/main.sqlite3_99?vfs=unix-dotfile", config.database_for("foo"))
            end

            test "parallel test worker returns all tenants" do
              assert_all_tenants_found
            end
          end
        end

        describe "relative URI" do
          let(:database) { "file:storage/db/tenanted/%{tenant}/main.sqlite3" }

          test "returns the path for a tenant" do
            assert_equal("file:storage/db/tenanted/foo/main.sqlite3", config.database_for("foo"))
          end

          test "returns all tenants" do
            assert_all_tenants_found
          end

          describe "parallel test workers" do
            setup { config.test_worker_id = 99 }

            test "returns the worker-specific path for a tenant" do
              assert_equal("file:storage/db/tenanted/foo/main.sqlite3_99", config.database_for("foo"))
            end

            test "parallel test worker returns all tenants" do
              assert_all_tenants_found
            end
          end
        end

        describe "relative URI with query params" do
          let(:database) { "file:storage/db/tenanted/%{tenant}/main.sqlite3?vfs=unix-dotfile" }

          test "returns the path for a tenant" do
            assert_equal("file:storage/db/tenanted/foo/main.sqlite3?vfs=unix-dotfile", config.database_for("foo"))
          end

          test "returns all tenants" do
            assert_all_tenants_found
          end

          describe "parallel test workers" do
            setup { config.test_worker_id = 99 }

            test "returns the worker-specific path for a tenant" do
              assert_equal("file:storage/db/tenanted/foo/main.sqlite3_99?vfs=unix-dotfile", config.database_for("foo"))
            end

            test "parallel test worker returns all tenants" do
              assert_all_tenants_found
            end
          end
        end
      end
    end

    describe "MySQL" do
      let(:adapter) { "mysql2" }

      describe "database_for" do
        describe "validation" do
          let(:database) { "test_%{tenant}_db" }

          test "raises if the tenant name contains a forward slash" do
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo/bar") }
          end

          test "raises if the tenant name contains a backslash" do
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo\\bar") }
          end

          test "raises if the resulting database name ends with a period" do
            config_with_period = ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig.new(
              "test",
              "test_tenant",
              { adapter: adapter, database: "%{tenant}." }
            )
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config_with_period.database_for("foo") }
          end

          test "raises if the tenant name contains ASCII NUL or control characters" do
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo\x00bar") }
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo\x01bar") }
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo\nbar") }
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo\tbar") }
          end

          test "raises if the tenant name contains spaces" do
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo bar") }
          end

          test "raises if the tenant name contains special characters" do
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo@bar") }
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo#bar") }
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo!bar") }
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for("foo*bar") }
          end

          test "raises if the resulting database name is too long (>64 chars)" do
            long_name = "a" * 100
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config.database_for(long_name) }
          end

          test "raises if the resulting database name starts with a number" do
            config_with_prefix = ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig.new(
              "test",
              "test_tenant",
              { adapter: adapter, database: "%{tenant}_db" }
            )
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) { config_with_prefix.database_for("123") }
          end

          test "allows valid characters: letters, numbers, underscore, dollar, and hyphen" do
            assert_nothing_raised { config.database_for("foo_bar") }
            assert_nothing_raised { config.database_for("foo-bar") }
            assert_nothing_raised { config.database_for("foo$bar") }
            assert_nothing_raised { config.database_for("foo123") }
          end
        end

        describe "database name pattern" do
          let(:database) { "tenanted_%{tenant}_db" }

          test "returns the database name for a tenant" do
            assert_equal("tenanted_foo_db", config.database_for("foo"))
          end

          test "works with hyphens in the pattern" do
            config_with_hyphens = ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig.new(
              "test",
              "test_tenant",
              { adapter: adapter, database: "tenanted-%{tenant}-db" }
            )
            assert_equal("tenanted-foo-db", config_with_hyphens.database_for("foo"))
          end

          describe "parallel test workers" do
            setup { config.test_worker_id = 99 }

            test "returns the worker-specific database name for a tenant" do
              assert_equal("tenanted_foo_db_99", config.database_for("foo"))
            end

            test "appends worker id to the end of the database name" do
              config_with_pattern = ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig.new(
                "test",
                "test_tenant",
                { adapter: adapter, database: "prefix_%{tenant}_suffix" }
              )
              config_with_pattern.test_worker_id = 42
              assert_equal("prefix_bar_suffix_42", config_with_pattern.database_for("bar"))
            end
          end
        end
      end
    end

    describe "max_connection_pools" do
      test "defaults to 50" do
        config_hash = { adapter: "sqlite3", database: "database" }
        config = ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig.new("test", "foo", config_hash)

        assert_equal(50, config.max_connection_pools)
      end

      test "can be set in the config" do
        config_hash = { adapter: "sqlite3", database: "database", max_connection_pools: 99 }
        config = ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig.new("test", "foo", config_hash)

        assert_equal(99, config.max_connection_pools)
      end
    end

    for_each_scenario do
      test "raises if a connection is attempted" do
        assert_raises(ActiveRecord::Tenanted::NoTenantError) { base_config.new_connection }
      end

      describe ".tenants" do
        test "returns an array of existing tenants" do
          assert_empty(base_config.tenants)

          TenantedApplicationRecord.create_tenant("foo")

          assert_equal([ "foo" ], base_config.tenants)

          TenantedApplicationRecord.create_tenant("bar")

          assert_same_elements([ "foo", "bar" ], base_config.tenants)

          TenantedApplicationRecord.destroy_tenant("foo")

          assert_equal([ "bar" ], base_config.tenants)
        end

        test "only returns tenants from tenanted databases, not shared databases" do
          assert_empty(base_config.tenants)

          TenantedApplicationRecord.create_tenant("foo")

          assert_equal([ "foo" ], base_config.tenants)

          all_databases = ActiveRecord::Base.configurations.configs_for(env_name: base_config.env_name)

          untenanted_config = all_databases.reject { |c| c.configuration_hash[:tenanted] }
          untenanted_config.each do |shared_config|
            assert_not_includes(base_config.tenants, shared_config.database)
          end
        end
      end
    end

    with_scenario("sqlite/primary_db", :primary_record) do
      test "handles non-alphanumeric characters" do
        assert_empty(base_config.tenants)

        crazy_name = 'a~!@#$%^&*()_-+=:;[{]}|,.?9' # please don't do this
        TenantedApplicationRecord.create_tenant(crazy_name)

        assert_equal([ crazy_name ], base_config.tenants)
      end
    end
  end

  describe "TenantConfig" do
    describe "#primary?" do
      for_each_scenario({ primary_db: [ :primary_record ], primary_named_db: [ :primary_record ] }) do
        test "returns true" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }
          assert_predicate(config, :primary?)
        end
      end

      with_scenario(:secondary_db, :primary_record) do
        test "returns false" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }
          assert_not_predicate(config, :primary?)
        end
      end
    end

    describe "implicit file creation" do
      with_scenario("sqlite/primary_db", :primary_record) do
        # This is probably not behavior we want, long-term. See notes about the sqlite3 adapter in
        # tenant.rb. This test is descriptive, not prescriptive.
        test "creates a file if one does not exist" do
          config = base_config.new_tenant_config("foo")
          conn = config.new_connection

          assert_not(File.exist?(config.database))

          conn.execute("SELECT 1")

          assert(File.exist?(config.database))
          assert_operator(File.size(config.database), :>, 0)
        end
      end
    end

    describe "schema dump" do
      with_scenario(:primary_db, :primary_record) do
        test "to the default primary dump file" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }
          assert_equal("schema.rb", config.schema_dump)
        end

        test "can be overridden" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }

          config_hash = config.configuration_hash.dup.tap do |h|
            h[:schema_dump] = "custom_file_name.rb"
          end.freeze
          config.instance_variable_set(:@configuration_hash, config_hash)

          assert_equal("custom_file_name.rb", config.schema_dump)
        end
      end

      with_scenario(:primary_named_db, :primary_record) do
        test "to the default primary dump file" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }
          assert_equal("schema.rb", config.schema_dump)
        end
      end

      with_scenario(:secondary_db, :primary_record) do
        test "to a named dump file" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }
          assert_equal("tenanted_schema.rb", config.schema_dump)
        end
      end

      with_scenario(:primary_uri_db, :primary_record) do
        test "the URI is preserved in the config" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }
          assert_operator(config.database, :start_with?, "file:")
          assert_operator(config.database, :end_with?, "?foo=bar")
        end
      end
    end

    describe "schema cache dump" do
      with_scenario(:primary_db, :primary_record) do
        test "to the default primary dump file" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }
          path = ActiveRecord::Tasks::DatabaseTasks.cache_dump_filename(config)

          expected = File.join(ActiveRecord::Tasks::DatabaseTasks.db_dir, "schema_cache.yml")
          assert_equal(expected, path)
        end

        test "can be overridden" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }

          config_hash = config.configuration_hash.dup.tap do |h|
            h[:schema_cache_path] = "db/custom_file_name.rb"
          end.freeze
          config.instance_variable_set(:@configuration_hash, config_hash)
          path = ActiveRecord::Tasks::DatabaseTasks.cache_dump_filename(config)

          assert_equal("db/custom_file_name.rb", path)
        end
      end

      with_scenario(:primary_named_db, :primary_record) do
        test "to the default primary dump file" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }
          path = ActiveRecord::Tasks::DatabaseTasks.cache_dump_filename(config)

          expected = File.join(ActiveRecord::Tasks::DatabaseTasks.db_dir, "schema_cache.yml")
          assert_equal(expected, path)
        end
      end

      with_scenario(:secondary_db, :primary_record) do
        test "to a named dump file" do
          config = TenantedApplicationRecord.create_tenant("foo") { User.connection_db_config }
          path = ActiveRecord::Tasks::DatabaseTasks.cache_dump_filename(config)

          expected = File.join(ActiveRecord::Tasks::DatabaseTasks.db_dir, "tenanted_schema_cache.yml")
          assert_equal(expected, path)
        end
      end
    end
  end
end
