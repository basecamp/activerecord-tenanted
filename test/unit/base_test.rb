# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::Base do
  test "it is mixed into ActiveRecord::Base" do
    assert_includes(ActiveRecord::Base.ancestors, ActiveRecord::Tenanted::Base)
  end

  describe ".tenanted" do
    with_scenario(:vanilla, :tenanted_primary) do
      test "it sets database configuration name to 'primary' by default" do
        assert_equal("primary", TenantedApplicationRecord.tenanted_config_name)
      end
    end

    with_scenario(:vanilla_named_primary, :tenanted_primary) do
      test "it sets database configuration name" do
        assert_equal("tenanted", TenantedApplicationRecord.tenanted_config_name)
      end
    end

    with_scenario(:vanilla, :tenanted_primary) do
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
    end

    with_each_scenario do
      test "it includes the Tenant module" do
        assert_includes(TenantedApplicationRecord.ancestors, ActiveRecord::Tenanted::Tenant)
        assert_includes(User.ancestors, ActiveRecord::Tenanted::Tenant)

        assert_not_includes(SharedApplicationRecord.ancestors, ActiveRecord::Tenanted::Tenant)
        assert_not_includes(Announcement.ancestors, ActiveRecord::Tenanted::Tenant)
      end

      test "it sets itself as a connection class" do
        assert(TenantedApplicationRecord.connection_class)
        assert_not(User.connection_class)
      end

      test "it implements #tenanted?" do
        assert_predicate(TenantedApplicationRecord, :tenanted?)
        assert_predicate(User, :tenanted?)

        assert_not(SharedApplicationRecord.tenanted?)
        assert_not(Announcement.tenanted?)
      end
    end
  end
end
