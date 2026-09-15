# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::Base do
  test "it is mixed into ActiveRecord::Base" do
    assert_includes(ActiveRecord::Base.ancestors, ActiveRecord::Tenanted::Base)
  end

  test "normally has a default shard of :default" do
    assert_equal(:default, ActiveRecord::Base.default_shard)
  end

  describe ".tenanted" do
    with_scenario(:primary_db, :primary_record) do
      test "it can only be called once" do
        e = assert_raises(ActiveRecord::Tenanted::Error) do
          TenantedApplicationRecord.tenanted
        end
        assert_includes(e.message, "already tenanted")
      end

      test "it can only be called on abstract classes" do
        e = assert_raises(ActiveRecord::Tenanted::Error) do
          Announcement.tenanted
        end
        assert_includes(e.message, "not an abstract connection class")
      end

      test "raises if the database configuration does not exist" do
        FakeRecord.abstract_class = true
        e = assert_raises(ActiveRecord::AdapterNotSpecified) do
          FakeRecord.tenanted(:does_not_exist)
        end
        assert_includes(e.message, "database is not configured")
      end

      test "only tenanted database configurations can be targetted" do
        FakeRecord.abstract_class = true
        e = assert_raises(ActiveRecord::Tenanted::Error) do
          FakeRecord.tenanted(:shared)
        end
        assert_includes(e.message, "database is not configured as tenanted")
      end
    end

    for_each_scenario do
      test "it includes the Tenant module" do
        assert_includes(TenantedApplicationRecord.ancestors, ActiveRecord::Tenanted::Tenant)
        if models_scenario == :subtenant_record
          assert_includes(User.ancestors, ActiveRecord::Tenanted::Subtenant)
        else
          assert_includes(User.ancestors, ActiveRecord::Tenanted::Tenant)
        end

        assert_not_includes(SharedApplicationRecord.ancestors, ActiveRecord::Tenanted::Tenant)
        assert_not_includes(Announcement.ancestors, ActiveRecord::Tenanted::Tenant)
      end

      test "it sets itself as a connection class" do
        assert(TenantedApplicationRecord.connection_class)
        assert_not(User.connection_class)
      end

      test "it implements .tenanted?" do
        assert_not(SharedApplicationRecord.tenanted?)
        assert_not(Announcement.tenanted?)

        assert_predicate(TenantedApplicationRecord, :tenanted?)
        assert_predicate(User, :tenanted?)
      end

      test "it implements #tenanted?" do
        assert_not(Announcement.new.tenanted?)
        TenantedApplicationRecord.create_tenant("foo") do
          assert_predicate(User.new, :tenanted?)
        end
      end
    end
  end

  describe "schema operations before database connections are made" do
    for_each_scenario do
      describe "without a schema cache dump file" do
        test "models can not be created" do
          assert_raises(ActiveRecord::Tenanted::NoTenantError) do
            User.new
          end
        end

        test "schema cache can not be loaded" do
          assert_raises(ActiveRecord::Tenanted::NoTenantError) do
            User.schema_cache.columns("users")
          end
        end

        test "the active record railtie will fail to eager load the schema" do
          # the code here should mirror the "active_record.define_attribute_methods" initializer
          assert_not(User.connection_pool.schema_reflection.cached?(User.table_name))
        end
      end

      describe "when schema cache dump file exists" do
        setup { with_schema_cache_dump_file }

        test "models can be created" do
          user = User.new

          assert_same_elements([ "id", "email", "created_at", "updated_at" ],
                               user.attributes.keys)
          assert_same_elements([ "id", "email", "created_at", "updated_at" ],
                               User.column_names)
        end

        test "schema cache can be loaded" do
          assert_same_elements([ "id", "email", "created_at", "updated_at" ],
                               User.schema_cache.columns("users")&.map(&:name))
        end

        test "the active record railtie will eager load the schema" do
          # the code here should mirror the "active_record.define_attribute_methods" initializer
          assert(User.connection_pool.schema_reflection.cached?(User.table_name))
          assert(User.define_attribute_methods)

          assert_same_elements([ "id", "email", "created_at", "updated_at" ],
                               User.schema_cache.columns("users")&.map(&:name))
        end

        test "no warning is emitted" do
          assert_silent do
            User.new
          end
        end
      end

      describe "when an outdated schema cache dump file exists" do
        setup { with_schema_cache_dump_file }
        setup { with_new_migration_file }

        test "the schema cache dump is ignored and models can not be created" do
          assert_output(nil, /Ignoring .*schema_cache\.yml because it has expired/) do
            assert_raises(ActiveRecord::Tenanted::NoTenantError) do
              User.new
            end
          end
        end

        test "the active record railtie will not eager load the schema" do
          # the code here should mirror the "active_record.define_attribute_methods" initializer
          assert_output(nil, /Ignoring .*schema_cache\.yml because it has expired/) do
            assert_not(User.connection_pool.schema_reflection.cached?(User.table_name))
          end
        end
      end
    end
  end
end
