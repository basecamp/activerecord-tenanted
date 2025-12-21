# frozen_string_literal: true

require "test_helper"

describe "PostgreSQL Colocated Schema Strategy" do
  with_scenario("postgresql/colocated_schema", :primary_record) do
    describe "schema_name_pattern configuration" do
      test "creates tenants with simple schema names in a static database" do
        # Verify the configuration is set correctly
        config = TenantedApplicationRecord.tenanted_root_config
        assert_equal "%{tenant}", config.configuration_hash[:schema_name_pattern]

        # Database name should not contain %{tenant}
        assert_match(/test_colocated$/, config.database)

        # Create a tenant
        TenantedApplicationRecord.create_tenant("customer-abc-123")

        # Verify tenant exists
        assert TenantedApplicationRecord.tenant_exist?("customer-abc-123")

        # Verify we can use the tenant
        TenantedApplicationRecord.with_tenant("customer-abc-123") do
          user = User.create!(email: "test@example.com")
          assert_equal "customer-abc-123", user.tenant
          assert_equal 1, User.count
        end
      end

      test "creates multiple tenants in the same database" do
        # Create multiple tenants
        TenantedApplicationRecord.create_tenant("tenant-1")
        TenantedApplicationRecord.create_tenant("tenant-2")
        TenantedApplicationRecord.create_tenant("tenant-3")

        # All tenants should exist
        assert TenantedApplicationRecord.tenant_exist?("tenant-1")
        assert TenantedApplicationRecord.tenant_exist?("tenant-2")
        assert TenantedApplicationRecord.tenant_exist?("tenant-3")

        # Add data to each tenant
        TenantedApplicationRecord.with_tenant("tenant-1") do
          User.create!(email: "user1@tenant1.com")
        end

        TenantedApplicationRecord.with_tenant("tenant-2") do
          User.create!(email: "user1@tenant2.com")
          User.create!(email: "user2@tenant2.com")
        end

        TenantedApplicationRecord.with_tenant("tenant-3") do
          User.create!(email: "user1@tenant3.com")
          User.create!(email: "user2@tenant3.com")
          User.create!(email: "user3@tenant3.com")
        end

        # Verify data isolation
        TenantedApplicationRecord.with_tenant("tenant-1") do
          assert_equal 1, User.count
          assert_equal "user1@tenant1.com", User.first.email
        end

        TenantedApplicationRecord.with_tenant("tenant-2") do
          assert_equal 2, User.count
        end

        TenantedApplicationRecord.with_tenant("tenant-3") do
          assert_equal 3, User.count
        end
      end

      test "handles UUID-based tenant names" do
        uuid = "550e8400-e29b-41d4-a716-446655440000"

        TenantedApplicationRecord.create_tenant(uuid)
        assert TenantedApplicationRecord.tenant_exist?(uuid)

        TenantedApplicationRecord.with_tenant(uuid) do
          User.create!(email: "uuid@example.com")
          assert_equal 1, User.count
        end
      end

      test "schema names match the tenant names exactly" do
        tenant_name = "exact-match-test"
        TenantedApplicationRecord.create_tenant(tenant_name)

        # Get the actual schema name from the database
        TenantedApplicationRecord.with_tenant(tenant_name) do
          schema_name = User.connection.select_value(
            "SELECT current_schema()"
          )
          assert_equal tenant_name, schema_name
        end
      end

      test "all tenants share the same base database" do
        TenantedApplicationRecord.create_tenant("shared-1")
        TenantedApplicationRecord.create_tenant("shared-2")

        db_name_1 = nil
        db_name_2 = nil

        TenantedApplicationRecord.with_tenant("shared-1") do
          db_name_1 = User.connection.select_value(
            "SELECT current_database()"
          )
        end

        TenantedApplicationRecord.with_tenant("shared-2") do
          db_name_2 = User.connection.select_value(
            "SELECT current_database()"
          )
        end

        # Both tenants should be in the same database
        assert_equal db_name_1, db_name_2
        assert_match(/test_colocated$/, db_name_1)
      end

      test "supports tenant names with special characters" do
        # PostgreSQL allows hyphens and underscores in identifiers
        tenants = [
          "tenant-with-hyphens",
          "tenant_with_underscores",
          "tenant-123-numbers",
        ]

        tenants.each do |tenant_name|
          TenantedApplicationRecord.create_tenant(tenant_name)
          assert TenantedApplicationRecord.tenant_exist?(tenant_name)

          TenantedApplicationRecord.with_tenant(tenant_name) do
            User.create!(email: "test@#{tenant_name}.com")
            assert_equal 1, User.count
          end
        end
      end
    end
  end
end
