# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::Tenant do
  describe ".while_tenanted" do
    with_each_scenario do
      describe ".current_tenant" do
        test "returns nil by default" do
          assert_nil(TenantedApplicationRecord.current_tenant)
        end

        test "returns the string name of the tenant if in a tenant context " do
          TenantedApplicationRecord.while_tenanted(:foo) do
            assert_equal("foo", TenantedApplicationRecord.current_tenant)
          end

          TenantedApplicationRecord.while_tenanted("foo") do
            assert_equal("foo", TenantedApplicationRecord.current_tenant)
          end
        end

        test "subclasses see the same tenant" do
          assert_nil(User.current_tenant)

          TenantedApplicationRecord.while_tenanted("foo") do
            assert_equal("foo", User.current_tenant)
          end
        end
      end

      test "raise NoTenantError on database access if there is no current tenant" do
        assert_raises(ActiveRecord::Tenanted::NoTenantError) do
          User.first
        end
      end

      test "raise if switching tenants in a while_tenanted block" do
        TenantedApplicationRecord.while_tenanted("foo") do
          # an odd exception to raise here IMHO, but that's the current behavior of Rails
          e = assert_raises(ArgumentError) do
            TenantedApplicationRecord.while_tenanted("bar") { }
          end
          assert_includes(e.message, "shard swapping is prohibited")
        end
      end
    end
  end
end
