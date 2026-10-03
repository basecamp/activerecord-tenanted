# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::TenantPoolConfig do
  with_scenario(:primary_named_db, :primary_record) do
    test "tenant pool configs publish a tenant-aware pool on their first read" do
      tenant_config = base_config.new_tenant_config("factory")
      pool_config = ActiveRecord::ConnectionAdapters::PoolConfig.new(User, tenant_config, :writing, "factory")

      pool = pool_config.pool

      assert_instance_of ActiveRecord::Tenanted::TenantConnectionPool, pool
      assert_same pool, pool_config.pool
    end

    test "non-tenant pool configs still publish Rails' standard connection pool" do
      shared_config = all_configs.find { |config| !config.is_a?(ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig) }
      pool_config = ActiveRecord::ConnectionAdapters::PoolConfig.new(Announcement, shared_config, :writing, :default)

      pool = pool_config.pool

      assert_instance_of ActiveRecord::ConnectionAdapters::ConnectionPool, pool
      assert_not_kind_of ActiveRecord::Tenanted::TenantConnectionPool, pool
      assert_same pool, pool_config.pool
    end

    test "an unsupported tenant PoolConfig shape raises a configuration error" do
      config = ActiveRecord::Tenanted::DatabaseConfigurations::BaseConfig.new(
        "test", "tenanted", { adapter: "sqlite3", database: "tenants/%{tenant}.sqlite3" }
      ).new_tenant_config("factory")
      unsupported = Object.new
      unsupported.define_singleton_method(:db_config) { config }
      unsupported.extend(ActiveRecord::Tenanted::TenantPoolConfig)

      error = assert_raises(ActiveRecord::Tenanted::TenantConfigurationError) { unsupported.pool }

      assert_includes error.message, "unsupported Active Record connection pool configuration"
    end
  end
end
