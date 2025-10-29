# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::Tenant do
  describe ".tenanted_config_name" do
    for_each_scenario({ primary_db: [ :primary_record, :secondary_record, :subtenant_record ] }) do
      test "it sets database configuration name to 'primary' by default" do
        assert_equal("primary", TenantedApplicationRecord.tenanted_config_name)
      end
    end

    for_each_scenario({ primary_named_db: [ :primary_record, :secondary_record ],
                        secondary_db:     [ :primary_record, :secondary_record ] }) do
      test "it sets database configuration name" do
        assert_equal("tenanted", TenantedApplicationRecord.tenanted_config_name)
      end
    end
  end

  describe ".tenanted?" do
    for_each_scenario do
      test "returns true" do
        assert_predicate(User, :tenanted?)
      end
    end
  end

  describe ".default_shard" do
    test "UNTENANTED_SENTINEL is self-describing" do
      assert_equal("ActiveRecord::Tenanted::Tenant::UNTENANTED_SENTINEL",
                   ActiveRecord::Tenanted::Tenant::UNTENANTED_SENTINEL.inspect)
      assert_equal("(untenanted)", ActiveRecord::Tenanted::Tenant::UNTENANTED_SENTINEL.to_s)
    end

    for_each_scenario do
      test "sets the default shard to UNTENANTED_SENTINEL" do
        assert_equal(:default, ActiveRecord::Base.default_shard)
        assert_equal(ActiveRecord::Tenanted::Tenant::UNTENANTED_SENTINEL, TenantedApplicationRecord.default_shard)
      end
    end
  end

  describe "no current tenant" do
    for_each_scenario do
      test "raise NoTenantError on database access if there is no current tenant" do
        assert_raises(ActiveRecord::Tenanted::NoTenantError) do
          User.first
        end
      end
    end
  end

  describe ".current_tenant" do
    for_each_scenario do
      test "returns nil by default" do
        assert_nil(TenantedApplicationRecord.current_tenant)
        assert_nil(User.current_tenant)
      end

      test ".current_tenant= sets tenant context" do
        TenantedApplicationRecord.create_tenant("foo")

        assert_nil(TenantedApplicationRecord.current_tenant)

        TenantedApplicationRecord.current_tenant = "foo"

        assert_equal("foo", TenantedApplicationRecord.current_tenant)
        assert_nothing_raised { User.first }
      end

      test ".current_tenant=nil clears tenant context" do
        assert_nil(TenantedApplicationRecord.current_tenant)

        TenantedApplicationRecord.current_tenant = "foo"

        assert_equal("foo", TenantedApplicationRecord.current_tenant)

        TenantedApplicationRecord.current_tenant = nil

        assert_nil(TenantedApplicationRecord.current_tenant)
      end

      test ".current_tenant= sets tenant context for a symbol" do
        TenantedApplicationRecord.create_tenant("foo")

        assert_nil(TenantedApplicationRecord.current_tenant)

        TenantedApplicationRecord.current_tenant = :foo

        assert_equal("foo", TenantedApplicationRecord.current_tenant)
        assert_nothing_raised { User.first }
      end

      test ".current_tenant= sets tenant context for an integer" do
        TenantedApplicationRecord.create_tenant("12345678")

        assert_nil(TenantedApplicationRecord.current_tenant)

        TenantedApplicationRecord.current_tenant = 12345678

        assert_equal("12345678", TenantedApplicationRecord.current_tenant)
        assert_nothing_raised { User.first }
      end

      test ".current_tenant= can be called repeatedly" do
        assert_nil(TenantedApplicationRecord.current_tenant)

        TenantedApplicationRecord.current_tenant = "foo"

        assert_equal("foo", TenantedApplicationRecord.current_tenant)

        TenantedApplicationRecord.current_tenant = "bar"

        assert_equal("bar", TenantedApplicationRecord.current_tenant)
      end

      test ".current_tenant= fires callbacks" do
        before_callback_fired = false
        after_callback_fired = false
        TenantedApplicationRecord.set_callback :set_current_tenant, :before do
          before_callback_fired = true
        end
        TenantedApplicationRecord.set_callback :set_current_tenant, :after do
          after_callback_fired = true
        end

        TenantedApplicationRecord.current_tenant = "foo"

        assert(before_callback_fired, "Before callback should be fired")
        assert(after_callback_fired, "After callback should be fired")
      end

      test "using a record after changing tenant raises WrongTenantError" do
        TenantedApplicationRecord.create_tenant("foo")
        TenantedApplicationRecord.create_tenant("bar")

        TenantedApplicationRecord.current_tenant = "foo"

        user = User.create!(email: "user1@example.org")

        TenantedApplicationRecord.current_tenant = "bar"

        assert_raises(ActiveRecord::Tenanted::WrongTenantError) do
          user.update!(email: "user1+bar@example.org")
        end
      end

      test ".current_tenant inside with_tenant raises exception" do
        TenantedApplicationRecord.create_tenant("foo")

        TenantedApplicationRecord.with_tenant("foo") do
          assert_raises(ArgumentError) do
            TenantedApplicationRecord.current_tenant = "bar"
          end

          assert_raises(ArgumentError) do # not even the same tenant is OK
            TenantedApplicationRecord.current_tenant = "foo"
          end
        end
      end
    end

    for_each_scenario(except: { primary_db: [ :subtenant_record ] }) do
      describe "concrete classes" do
        test "concrete classes can call current_tenant=" do
          TenantedApplicationRecord.current_tenant = "foo"
          assert_equal("foo", TenantedApplicationRecord.current_tenant)
          assert_equal("foo", User.current_tenant)

          User.current_tenant = "bar"
          assert_equal("bar", TenantedApplicationRecord.current_tenant)
          assert_equal("bar", User.current_tenant)
        end

        test ".current_tenant= sets tenant context" do
          TenantedApplicationRecord.create_tenant("foo")

          assert_nil(User.current_tenant)

          User.current_tenant = "foo"

          assert_equal("foo", User.current_tenant)
          assert_nothing_raised { User.first }
        end
      end
    end
  end

  describe ".with_tenant" do
    for_each_scenario do
      setup do
        TenantedApplicationRecord.create_tenant("foo")
        TenantedApplicationRecord.create_tenant("bar")
        TenantedApplicationRecord.create_tenant("12345678")
      end

      test "current tenant is set in the block context " do
        TenantedApplicationRecord.with_tenant(:foo) do
          User.first
          assert_equal("foo", TenantedApplicationRecord.current_tenant)
        end

        TenantedApplicationRecord.with_tenant("foo") do
          User.first
          assert_equal("foo", TenantedApplicationRecord.current_tenant)
        end

        TenantedApplicationRecord.with_tenant(12345678) do
          User.first
          assert_equal("12345678", TenantedApplicationRecord.current_tenant)
        end
      end

      test "subclasses see the same tenant" do
        assert_nil(User.current_tenant)

        TenantedApplicationRecord.with_tenant("foo") do
          assert_equal("foo", User.current_tenant)
        end
      end

      test "raise if switching tenants in a with_tenant block" do
        TenantedApplicationRecord.with_tenant("foo") do
          # an odd exception to raise here IMHO, but that's the current behavior of Rails
          e = assert_raises(ArgumentError) do
            TenantedApplicationRecord.with_tenant("bar") { }
          end
          assert_includes(e.message, "shard swapping is prohibited")
        end
      end

      test "overrides the current tenant if set with current_tenant=" do
        TenantedApplicationRecord.current_tenant = "foo"

        TenantedApplicationRecord.with_tenant("bar") do
          assert_equal("bar", TenantedApplicationRecord.current_tenant)
        end

        assert_equal("foo", TenantedApplicationRecord.current_tenant)
      end

      test "using a record outside of the block raises NoTenantError" do
        user = TenantedApplicationRecord.with_tenant("bar") do
          User.create!(email: "user1@example.org")
        end

        assert_raises(ActiveRecord::Tenanted::NoTenantError) do
          user.update!(email: "user1+bar@example.org")
        end
      end

      test "using a record in another block raises WrongTenantError" do
        user = TenantedApplicationRecord.with_tenant("foo") do
          User.create!(email: "user1@example.org")
        end

        TenantedApplicationRecord.with_tenant("bar") do
          assert_raises(ActiveRecord::Tenanted::WrongTenantError) do
            user.update!(email: "user1+bar@example.org")
          end
        end
      end

      test "may allow shard swapping if explicitly asked" do
        invoked = nil

        TenantedApplicationRecord.with_tenant("foo", prohibit_shard_swapping: false) do
          assert_nothing_raised do
            TenantedApplicationRecord.with_tenant("bar") { invoked = true }
          end
        end

        assert(invoked)
      end

      test "allow nesting with_tenant calls when the tenant is the same" do
        invoked = nil

        assert_nothing_raised do
          TenantedApplicationRecord.with_tenant("foo") do
            TenantedApplicationRecord.with_tenant("foo") { invoked = true }
          end
        end

        assert(invoked)
      end

      test "attempting to access a tenant that does not exist raises TenantDoesNotExistError" do
        assert_not(TenantedApplicationRecord.tenant_exist?("baz"))

        assert_nothing_raised do
          TenantedApplicationRecord.with_tenant("baz") { } # this is OK because it doesn't hit the database
        end

        assert_raises(ActiveRecord::Tenanted::TenantDoesNotExistError) do
          TenantedApplicationRecord.with_tenant("baz") { User.count }
        end
      end

      test ".with_tenant fires callbacks" do
        around_callback_fired = false
        block_called = false
        TenantedApplicationRecord.set_callback :with_tenant, :around do |_, block|
          around_callback_fired = true
          block.call
        end

        TenantedApplicationRecord.with_tenant("foo") do
          block_called = true
        end

        assert(around_callback_fired, "Around callback should be fired")
        assert(block_called, "Block should be called")
      end

      test ".with_tenant fires callbacks even when tenant doesn't change" do
        around_callback_fired = 0
        block_called = false
        TenantedApplicationRecord.set_callback :with_tenant, :around do |_, block|
          around_callback_fired += 1
          block.call
        end

        TenantedApplicationRecord.with_tenant("foo") do
          TenantedApplicationRecord.with_tenant("foo") do
            block_called = true
          end
        end

        assert_equal(2, around_callback_fired, "Around callback should be fired for each call")
        assert(block_called, "Block should be called")
      end
    end

    for_each_scenario(except: { primary_db: [ :subtenant_record ] }) do
      setup do
        TenantedApplicationRecord.create_tenant("foo")
        TenantedApplicationRecord.create_tenant("bar")
      end

      describe "concrete classes" do
        test "current tenant is set in the block context " do
          User.with_tenant(:foo) do
            User.first
            assert_equal("foo", User.current_tenant)
          end

          User.with_tenant("foo") do
            User.first
            assert_equal("foo", User.current_tenant)
          end
        end

        test "superclasses see the same tenant" do
          assert_nil(User.current_tenant)

          User.with_tenant("foo") do
            assert_equal("foo", TenantedApplicationRecord.current_tenant)
          end
        end

        test "raise if switching tenants in a with_tenant block" do
          User.with_tenant("foo") do
            # an odd exception to raise here IMHO, but that's the current behavior of Rails
            e = assert_raises(ArgumentError) do
              TenantedApplicationRecord.with_tenant("bar") { }
            end
            assert_includes(e.message, "shard swapping is prohibited")
          end
        end

        test "overrides the current tenant if set with current_tenant=" do
          TenantedApplicationRecord.current_tenant = "foo"

          User.with_tenant("bar") do
            assert_equal("bar", TenantedApplicationRecord.current_tenant)
          end

          assert_equal("foo", TenantedApplicationRecord.current_tenant)
        end

        test "using a record outside of the block raises NoTenantError" do
          user = User.with_tenant("bar") do
            User.create!(email: "user1@example.org")
          end

          assert_raises(ActiveRecord::Tenanted::NoTenantError) do
            user.update!(email: "user1+bar@example.org")
          end
        end

        test "using a record in another block raises WrongTenantError" do
          user = User.with_tenant("foo") do
            User.create!(email: "user1@example.org")
          end

          User.with_tenant("bar") do
            assert_raises(ActiveRecord::Tenanted::WrongTenantError) do
              user.update!(email: "user1+bar@example.org")
            end
          end
        end

        test "may allow shard swapping if explicitly asked" do
          invoked = nil

          User.with_tenant("foo", prohibit_shard_swapping: false) do
            assert_nothing_raised do
              TenantedApplicationRecord.with_tenant("bar") { invoked = true }
            end
          end

          assert(invoked)
        end

        test "allow nesting with_tenant calls when the tenant is the same" do
          invoked = 0

          assert_nothing_raised do
            User.with_tenant("foo") do
              User.with_tenant("foo") { invoked += 1 }
            end

            User.with_tenant("foo") do
              TenantedApplicationRecord.with_tenant("foo") { invoked += 1 }
            end
          end

          assert_equal(2, invoked)
        end

        test "attempting to access a tenant that does not exist raises TenantDoesNotExistError" do
          assert_not(TenantedApplicationRecord.tenant_exist?("baz"))

          assert_nothing_raised do
            User.with_tenant("baz") { } # this is OK because it doesn't hit the database
          end

          assert_raises(ActiveRecord::Tenanted::TenantDoesNotExistError) do
            User.with_tenant("baz") { User.count }
          end
        end
      end
    end
  end

  describe "associations" do
    for_each_scenario do
      describe "to a tenanted model" do
        setup do
          with_migration "20250830152220_create_posts.rb"
          User.has_many :posts
          Post.belongs_to :user

          TenantedApplicationRecord.create_tenant("foo") do
            user = User.create!(email: "user1@foo.example.org")
            Post.create!(title: "Post 1 foo", user: user)
            Post.create!(title: "Post 2 foo", user: user)
          end

          TenantedApplicationRecord.create_tenant("bar") do
            user = User.create!(email: "user1@bar.example.org")
            Post.create!(title: "Post 1 bar", user: user)
            Post.create!(title: "Post 2 bar", user: user)
          end
        end

        test "in a tenanted context" do
          TenantedApplicationRecord.with_tenant("foo") do
            user = User.first
            posts = user.posts.to_a

            assert_same_elements([ "Post 1 foo", "Post 2 foo" ], posts.map(&:title))
            assert_equal([ "foo" ], posts.map(&:tenant).uniq)
          end
        end

        test "outside of a tenanted context" do
          user = TenantedApplicationRecord.with_tenant("foo") { User.first }

          assert_raises(ActiveRecord::Tenanted::NoTenantError) do
            user.posts
          end
        end

        test "in another tenant context" do
          user = TenantedApplicationRecord.with_tenant("foo") { User.first }

          TenantedApplicationRecord.with_tenant("bar") do
            assert_raises(ActiveRecord::Tenanted::WrongTenantError) do
              user.posts
            end
          end
        end
      end

      describe "to an untenanted model" do
        setup do
          with_migration "20250830170325_add_announcement_to_users.rb"
          User.belongs_to :announcement

          TenantedApplicationRecord.create_tenant("foo") do
            # this association doesn't make a lot of sense, but it's just for testing
            announcement = Announcement.create!(message: "Announcement 1")
            User.create!(email: "user1@foo.example.org", announcement: announcement)
          end

          TenantedApplicationRecord.create_tenant("bar")
        end

        test "in a tenanted context" do
          TenantedApplicationRecord.with_tenant("foo") do
            user = User.first
            announcement = user.announcement

            assert_equal("Announcement 1", announcement.message)
          end
        end

        test "outside of a tenanted context" do
          user = TenantedApplicationRecord.with_tenant("foo") { User.first }

          announcement = user.announcement

          assert_equal("Announcement 1", announcement.message)
        end

        test "in another tenant context" do
          user = TenantedApplicationRecord.with_tenant("foo") { User.first }

          announcement = TenantedApplicationRecord.with_tenant("bar") do
            user.announcement
          end

          assert_equal("Announcement 1", announcement.message)
        end
      end

      describe "polymorphic" do
        setup do
          with_migration "20250830175957_add_announceable_to_users.rb"
          User.belongs_to :announceable, polymorphic: true

          TenantedApplicationRecord.create_tenant("foo") do
            # this association doesn't make a lot of sense, but it's just for testing
            announcement = Announcement.create!(message: "Announcement 1")
            User.create!(email: "user1@foo.example.org", announceable: announcement)
          end

          TenantedApplicationRecord.create_tenant("bar")
        end

        test "in a tenanted context" do
          TenantedApplicationRecord.with_tenant("foo") do
            user = User.first
            announcement = user.announceable

            assert_equal("Announcement 1", announcement.message)
          end
        end

        test "outside of a tenanted context" do
          user = TenantedApplicationRecord.with_tenant("foo") { User.first }

          assert_raises(ActiveRecord::Tenanted::NoTenantError) do
            user.announceable
          end
        end

        test "in another tenant context" do
          user = TenantedApplicationRecord.with_tenant("foo") { User.first }

          TenantedApplicationRecord.with_tenant("bar") do
            assert_raises(ActiveRecord::Tenanted::WrongTenantError) do
              user.announceable
            end
          end
        end
      end
    end
  end


  describe ".without_tenant" do
    for_each_scenario do
      setup do
        TenantedApplicationRecord.create_tenant("foo")
        TenantedApplicationRecord.create_tenant("bar")
      end

      test "current_tenant is nil" do
        TenantedApplicationRecord.current_tenant = "foo"
        TenantedApplicationRecord.without_tenant do
          assert_nil(TenantedApplicationRecord.current_tenant)
        end
      end

      test "allows shard swapping" do
        TenantedApplicationRecord.current_tenant = "foo"
        TenantedApplicationRecord.without_tenant do
          TenantedApplicationRecord.with_tenant("bar") do
            assert_equal("bar", TenantedApplicationRecord.current_tenant)
          end
        end
      end
    end
  end

  describe ".tenant_exist?" do
    for_each_scenario do
      test "it returns false if the tenant database has not been created" do
        assert_not(TenantedApplicationRecord.tenant_exist?("doesnotexist"))
      end

      test "it returns true if the tenant database has been created" do
        TenantedApplicationRecord.create_tenant("foo")

        assert(TenantedApplicationRecord.tenant_exist?("foo"))
      end

      test "it returns true for symbols if the tenant database has been created" do
        TenantedApplicationRecord.create_tenant("foo")

        assert(TenantedApplicationRecord.tenant_exist?("foo"))
      end

      test "it returns true for integers if the tenant database has been created" do
        TenantedApplicationRecord.create_tenant("12345678")

        assert(TenantedApplicationRecord.tenant_exist?(12345678))
      end
    end

    with_scenario("sqlite/primary_db", :primary_record) do
      test "it returns false if the tenant database is in the process of being migrated" do
        config = TenantedApplicationRecord.tenanted_root_config
        db_path = config.config_adapter.path_for(config.database_for("foo"))

        assert_not(TenantedApplicationRecord.tenant_exist?("foo"))

        ActiveRecord::Tenanted::Mutex::Ready.lock(db_path) do
          assert_not(TenantedApplicationRecord.tenant_exist?("foo"))
          FileUtils.touch(db_path) # pretend the database was created and migrated
        end

        assert(TenantedApplicationRecord.tenant_exist?("foo"))
      end
    end
  end

  describe ".create_tenant" do
    with_scenario(:primary_named_db, :primary_record) do
      describe "failed migration because database is readonly" do
        setup do
          db_config["test"]["tenanted"]["readonly"] = true
          ActiveRecord::Base.configurations = db_config
        end

        it "block is not called, file is deleted, and exception is reraised" do
          called = false

          e = assert_raises(ActiveRecord::StatementInvalid) do
            TenantedApplicationRecord.create_tenant("foo") { called = true }
          end

          assert_kind_of(SQLite3::Exception, e.cause)
          assert_not(called)
          assert_not(TenantedApplicationRecord.tenant_exist?("foo"))
        end
      end
    end

    for_each_scenario do
      test "raises an exception if the tenant already exists" do
        TenantedApplicationRecord.create_tenant("foo")

        called = false
        assert_raises(ActiveRecord::Tenanted::TenantExistsError) do
          TenantedApplicationRecord.create_tenant("foo") { called = true }
        end
        assert_not(called, "Block should not be called when tenant already exists")
      end

      test "does not raise an exception if the tenant already exists and if_not_exists is true" do
        TenantedApplicationRecord.create_tenant("foo")

        called = false
        assert_nothing_raised do
          TenantedApplicationRecord.create_tenant("foo", if_not_exists: true) { called = true }
        end
        assert(called, "Block should be called when if_not_exists is true")
      end

      test "creates the database" do
        assert_not(TenantedApplicationRecord.tenant_exist?("foo"))

        db_config = TenantedApplicationRecord.create_tenant("foo") do
          User.connection_db_config
        end

        assert(TenantedApplicationRecord.tenant_exist?("foo"))
        assert_predicate(db_config.config_adapter, :database_exist?)
      end

      test "creates the database given a symbol" do
        assert_not(TenantedApplicationRecord.tenant_exist?("foo"))

        db_config = TenantedApplicationRecord.create_tenant(:foo) do
          User.connection_db_config
        end

        assert(TenantedApplicationRecord.tenant_exist?("foo"))
        assert_predicate(db_config.config_adapter, :database_exist?)
      end

      test "creates the database given an integer" do
        assert_not(TenantedApplicationRecord.tenant_exist?("12345678"))

        db_config = TenantedApplicationRecord.create_tenant(12345678) do
          User.connection_db_config
        end

        assert(TenantedApplicationRecord.tenant_exist?("12345678"))
        assert_predicate(db_config.config_adapter, :database_exist?)
      end

      test "yields the block in the context of the created tenant" do
        TenantedApplicationRecord.create_tenant("foo") do
          assert_equal("foo", TenantedApplicationRecord.current_tenant)
        end
      end

      test "database should be migrated" do
        ActiveRecord::Migration.verbose = true

        assert_output(/migrating.*create_table/m, nil) do
          TenantedApplicationRecord.create_tenant("foo")
        end

        version = TenantedApplicationRecord.with_tenant("foo") do
          User.connection_pool.migration_context.current_version
        end

        assert_equal(20250203191115, version)
      end

      test "database schema file should be created" do
        schema_path = TenantedApplicationRecord.create_tenant("foo") do
          ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(User.connection_db_config)
        end

        assert(File.exist?(schema_path))
      end

      test "database schema cache file should be created" do
        schema_cache_path = TenantedApplicationRecord.create_tenant("foo") do
          ActiveRecord::Tasks::DatabaseTasks.cache_dump_filename(User.connection_db_config)
        end

        assert(File.exist?(schema_cache_path))
      end

      describe "when schema dump file exists" do
        setup { with_schema_dump_file }

        test "database should load the schema dump file" do
          ActiveRecord::Migration.verbose = true

          assert_silent do
            TenantedApplicationRecord.create_tenant("bar")
          end

          version = TenantedApplicationRecord.with_tenant("bar") do
            User.connection_pool.migration_context.current_version
          end

          assert_equal(20250203191115, version)
        end

        describe "and there are pending migrations" do
          setup { with_new_migration_file }

          test "it runs the migrations after loading the schema" do
            ActiveRecord::Migration.verbose = true

            assert_output(/migrating.*add_column/m, nil) do
              TenantedApplicationRecord.create_tenant("foo")
            end

            version = TenantedApplicationRecord.with_tenant("foo") do
              User.connection_pool.migration_context.current_version
            end

            assert_equal(20250213005959, version)
            assert_same_elements([ "id", "email", "created_at", "updated_at", "age" ],
                                 User.new.attributes.keys)
          end
        end
      end

      describe "when an outdated schema cache dump file exists" do
        setup { with_schema_cache_dump_file }
        setup { with_new_migration_file }

        describe "before a connection is made" do
          test "models can be created but migration is not applied" do
            assert_same_elements([ "id", "email", "created_at", "updated_at" ],
                                 User.new.attributes.keys)
          end
        end

        describe "after a connection is made" do
          test "remaining migrations are applied" do
            ActiveRecord::Migration.verbose = true

            assert_output(/migrating.*add_column/m, nil) do
              TenantedApplicationRecord.create_tenant("foo")
            end

            version = TenantedApplicationRecord.with_tenant("foo") do
              User.connection_pool.migration_context.current_version
            end

            assert_equal(20250213005959, version)
            assert_same_elements([ "id", "email", "created_at", "updated_at", "age" ],
                                 User.new.attributes.keys)
          end
        end
      end
    end
  end

  describe ".destroy_tenant" do
    for_each_scenario do
      test "it returns if the tenant does not exist" do
        assert_nothing_raised do
          TenantedApplicationRecord.destroy_tenant("doesnotexist")
        end
      end

      describe "when the tenant exists" do
        setup { TenantedApplicationRecord.create_tenant("foo") }

        test "it deletes the connection pool" do
          TenantedApplicationRecord.destroy_tenant("foo")

          pool = TenantedApplicationRecord.connection_handler.retrieve_connection_pool(
            TenantedApplicationRecord.connection_specification_name,
            role: TenantedApplicationRecord.current_role,
            shard: "foo",
            strict: false)

          assert_nil(pool)
        end

        test "it logs the deletion" do
          log = capture_log do
            TenantedApplicationRecord.destroy_tenant("foo")
          end
          assert_includes(log.string, "Destroying tenant database")
          assert_includes(log.string, "DESTROY [tenant=foo]")
        end

        test "it deletes the database file" do
          TenantedApplicationRecord.destroy_tenant("foo")

          assert_not(TenantedApplicationRecord.tenant_exist?("foo"))
        end

        test "it deletes the database file for symbols" do
          TenantedApplicationRecord.destroy_tenant(:foo)

          assert_not(TenantedApplicationRecord.tenant_exist?("foo"))
        end

        test "it deletes the database file for integers" do
          TenantedApplicationRecord.create_tenant("12345678")

          TenantedApplicationRecord.destroy_tenant(12345678)

          assert_not(TenantedApplicationRecord.tenant_exist?("12345678"))
        end
      end
    end
  end

  describe ".tenants" do
    for_each_scenario do
      test "it returns an array of existing tenants" do
        assert_empty(TenantedApplicationRecord.tenants)

        TenantedApplicationRecord.create_tenant("foo")

        assert_equal([ "foo" ], TenantedApplicationRecord.tenants)

        TenantedApplicationRecord.create_tenant("bar")

        assert_same_elements([ "foo", "bar" ], TenantedApplicationRecord.tenants)

        TenantedApplicationRecord.destroy_tenant("foo")

        assert_equal([ "bar" ], TenantedApplicationRecord.tenants)
      end
    end

    for_each_scenario(only: { adapter: :sqlite }) do
      test "it does not return tenants that are not ready" do
        config = TenantedApplicationRecord.tenanted_root_config
        db_path = config.config_adapter.path_for(config.database_for("foo"))

        TenantedApplicationRecord.create_tenant("bar")

        ActiveRecord::Tenanted::Mutex::Ready.lock(db_path) do
          assert_equal([ "bar" ], TenantedApplicationRecord.tenants)

          FileUtils.touch(db_path) # pretend the database was created

          assert_equal([ "bar" ], TenantedApplicationRecord.tenants)
        end

        assert_same_elements([ "foo", "bar" ], TenantedApplicationRecord.tenants)
      end
    end
  end

  describe ".with_each_tenant" do
    for_each_scenario do
      test "calls the block in a tenanted context once for each existing tenant" do
        result = []
        TenantedApplicationRecord.with_each_tenant do |tenant|
          result << [ tenant, TenantedApplicationRecord.current_tenant ]
        end
        assert_empty(result)

        TenantedApplicationRecord.create_tenant("foo")
        TenantedApplicationRecord.create_tenant("bar")

        result = []
        TenantedApplicationRecord.with_each_tenant do |tenant|
          result << [ tenant, TenantedApplicationRecord.current_tenant ]
        end
        assert_same_elements([ [ "foo", "foo" ], [ "bar", "bar" ] ], result)
      end

      test "by default does not allow shard swapping" do
        TenantedApplicationRecord.create_tenant("foo")
        TenantedApplicationRecord.create_tenant("bar")

        TenantedApplicationRecord.with_each_tenant do |tenant|
          if tenant != "foo"
            e = assert_raises(ArgumentError) do
              TenantedApplicationRecord.with_tenant("foo") { }
            end
            assert_includes(e.message, "shard swapping is prohibited")
          end
        end
      end

      test "accepts prohibit_shard_swapping kwarg" do
        TenantedApplicationRecord.create_tenant("foo")
        TenantedApplicationRecord.create_tenant("bar")

        TenantedApplicationRecord.with_each_tenant(prohibit_shard_swapping: false) do |tenant|
          if tenant != "foo"
            assert_nothing_raised do
              TenantedApplicationRecord.with_tenant("foo") { }
            end
          end
        end
      end
    end
  end

  describe "connection pools" do
    with_scenario(:primary_named_db, :primary_record) do
      test "handle race conditions when creating a new connection pool" do
        TenantedApplicationRecord.create_tenant("foo") do
          # force creation of a new connection pool later
          TenantedApplicationRecord.remove_connection
        end

        success_log = Concurrent::Array.new

        threads = 5.times.map do |j|
          Thread.new do
            TenantedApplicationRecord.with_tenant("foo") do
              User.count
              success_log << j
            end
          end
        end
        threads.each(&:join)

        assert_equal(5, success_log.size)
      end

      test "connection pools are reaped when they exceed the max" do
        max = ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig::DEFAULT_MAX_CONNECTION_POOLS

        assert_equal 0, TenantedApplicationRecord.tenanted_connection_pools.size

        (1..max).each { |j| TenantedApplicationRecord.create_tenant("tenant#{j}") { User.count } }

        assert_equal max, TenantedApplicationRecord.tenanted_connection_pools.size
        assert TenantedApplicationRecord.tenanted_connection_pools.keys.include?([ "tenant1", :writing ])
        assert TenantedApplicationRecord.tenanted_connection_pools.keys.include?([ "tenant2", :writing ])
        assert TenantedApplicationRecord.tenanted_connection_pools.keys.include?([ "tenant3", :writing ])

        tenant_pools = TenantedApplicationRecord.connection_handler.connection_pools
                         .select { |pool| pool.shard =~ /^tenant/ }
        assert_equal max, tenant_pools.size

        TenantedApplicationRecord.create_tenant "tenant-wafer-thin-mint" do
          User.count

          assert_equal max, TenantedApplicationRecord.tenanted_connection_pools.size
          assert_not TenantedApplicationRecord.tenanted_connection_pools.keys.include?([ "tenant1", :writing ])
          assert TenantedApplicationRecord.tenanted_connection_pools.keys.include?([ "tenant2", :writing ])
          assert TenantedApplicationRecord.tenanted_connection_pools.keys.include?([ "tenant3", :writing ])

          tenant_pools = TenantedApplicationRecord.connection_handler.connection_pools
                           .select { |pool| pool.shard =~ /^tenant/ }
          assert_equal max, tenant_pools.size
        end

        TenantedApplicationRecord.with_tenant("tenant2") { User.count } # so it's no longer the oldest

        TenantedApplicationRecord.create_tenant "tenant-the-cheque-monsieur" do
          User.count

          assert_equal max, TenantedApplicationRecord.tenanted_connection_pools.size
          assert TenantedApplicationRecord.tenanted_connection_pools.keys.include?([ "tenant2", :writing ])
          assert_not TenantedApplicationRecord.tenanted_connection_pools.keys.include?([ "tenant3", :writing ])

          tenant_pools = TenantedApplicationRecord.connection_handler.connection_pools
                           .select { |pool| pool.shard =~ /^tenant/ }
          assert_equal max, tenant_pools.size
        end
      end
    end

    for_each_scenario do
      test "models should share connection pools" do
        TenantedApplicationRecord.create_tenant("foo") do
          assert_same(User.connection_pool, Post.connection_pool)
          assert_same(TenantedApplicationRecord.connection_pool, User.connection_pool)
        end
      end

      describe "with a pending migration" do
        setup do
          TenantedApplicationRecord.create_tenant("foo") do
            # force creation of a new connection pool later
            TenantedApplicationRecord.remove_connection
          end

          with_new_migration_file
        end

        test "pending migrations should raise an error" do
          assert_raises(ActiveRecord::PendingMigrationError) do
            TenantedApplicationRecord.with_tenant("foo") { User.first }
          end
        end

        test ".destroy_tenant should not raise an error" do
          assert_nothing_raised do
            TenantedApplicationRecord.destroy_tenant("foo")
          end
        end
      end
    end
  end

  describe "logging" do
    for_each_scenario do
      test "database logs should emit the tenant name" do
        TenantedApplicationRecord.create_tenant("foo")

        log = capture_log do
          TenantedApplicationRecord.with_tenant("foo") do
            User.count
          end
        end

        assert_includes(log.string, "tenant='foo'")
      end
    end

    with_scenario(:primary_named_db, :primary_record) do
      describe "config log_tenant_tag" do
        describe "true" do
          setup { Rails.application.config.active_record_tenanted.log_tenant_tag = true }

          describe "untenanted" do
            test "logs still work" do
              log = capture_rails_log do
                Rails.logger.info("hello")
              end

              assert_equal("hello", log.string.strip)
            end
          end

          describe "tenanted" do
            test "database logs should emit the tenant name" do
              TenantedApplicationRecord.create_tenant("foo")

              log = capture_rails_log do
                TenantedApplicationRecord.with_tenant("foo") do
                  Rails.logger.info("hello")
                end
              end

              assert_equal("[tenant=foo] hello", log.string.strip)
            end
          end
        end

        describe "false" do
          setup { Rails.application.config.active_record_tenanted.log_tenant_tag = false }

          test "database logs should not emit the tenant name" do
            TenantedApplicationRecord.create_tenant("foo")

            log = capture_rails_log do
              TenantedApplicationRecord.with_tenant("foo") do
                Rails.logger.info("hello")
              end
            end

            assert_equal("hello", log.string.strip)
          end
        end
      end
    end
  end

  describe "#tenant" do
    for_each_scenario do
      describe "created in untenanted context" do
        setup { with_schema_cache_dump_file }

        test "returns nil" do
          user = User.new(email: "user1@example.org")
          assert_nil(user.tenant)
        end
      end

      describe "created in tenanted context" do
        setup { TenantedApplicationRecord.create_tenant("foo") }

        test "returns the tenant name even outside of tenant context" do
          ids = []

          user = TenantedApplicationRecord.with_tenant("foo") do
            User.new(email: "user1@example.org")
          end
          assert_equal("foo", user.tenant)

          user = TenantedApplicationRecord.with_tenant("foo") do
            User.create(email: "user1@example.org")
          end
          assert_equal("foo", user.tenant)
          ids << user.id

          user = TenantedApplicationRecord.with_tenant("foo") do
            User.create!(email: "user1@example.org")
          end
          assert_equal("foo", user.tenant)
          ids << user.id

          TenantedApplicationRecord.with_tenant("foo") do
            ids.each do |id|
              assert_equal("foo", User.find(user.id).tenant)
            end
          end
        end
      end

      describe "created by #load_async in another context" do
        setup do
          TenantedApplicationRecord.create_tenant("foo")
          TenantedApplicationRecord.create_tenant("bar")

          @announcement = Announcement.create!(message: "hello")
          TenantedApplicationRecord.with_tenant("foo") do
            @user = User.create!(email: "foo@example.org")
          end
        end

        test "is set correctly" do
          TenantedApplicationRecord.with_tenant("foo") do
            @users = User.where(email: "foo@example.org").load_async
            @announcements = Announcement.where("message like '%hel%'").load_async

            assert_predicate @users, :scheduled?
            assert_predicate @announcements, :scheduled?
          end

          TenantedApplicationRecord.with_tenant("bar") do
            assert_predicate @users, :scheduled?
            assert_predicate @announcements, :scheduled?

            @users.to_a
            assert_equal [ @user ], @users
            assert_equal "foo", @user.tenant
            assert_equal "foo", @users.first.tenant

            @announcements.to_a
            assert_equal [ @announcement ], @announcements
            assert_nil @announcements.first.instance_variable_get(:@tenant)
          end
        end
      end
    end
  end

  describe "#cache_key" do
    for_each_scenario do
      describe "created in untenanted context" do
        setup { with_schema_cache_dump_file }

        test "does not include the tenant name" do
          user = User.new(email: "user1@example.org")

          assert_equal("users/new", user.cache_key)
        end
      end

      describe "created in tenanted context" do
        test "includes the tenant name" do
          user = TenantedApplicationRecord.create_tenant("foo") do
            User.create!(email: "user1@example.org")
          end

          assert_equal("foo/users/1", user.cache_key)

          TenantedApplicationRecord.with_tenant("foo") do
            assert_equal("foo/users/1", User.find(user.id).cache_key)
          end
        end

        test "handles special characters in tenant names" do
          TenantedApplicationRecord.create_tenant("foo-bar_123") do
            user = User.create!(email: "user1@example.org")
            assert_equal("foo-bar_123/users/1", user.cache_key)
          end
        end
      end
    end
  end

  describe "#inspect" do
    for_each_scenario do
      describe "created in untenanted context" do
        setup { with_schema_cache_dump_file }

        test "does not include tenant name" do
          user = User.new(email: "user1@example.org")

          assert_no_match(/tenant=/, user.inspect)
        end
      end

      describe "created in tenanted context" do
        test "includes the tenant name" do
          user = TenantedApplicationRecord.create_tenant("foo") do
            User.create!(email: "user1@example.org")
          end

          assert_match(/\A#<User tenant: "foo", id:/, user.inspect)
        end
      end
    end
  end
end
