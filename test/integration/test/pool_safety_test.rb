require "application_system_test_case"

class TestTenantPoolCapacity < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "a busy tenant pool survives eviction while an idle pool makes room" do
    root_config = ApplicationRecord.tenanted_root_config
    tenant_a = "pool-safety-success-a"
    tenant_b = "pool-safety-success-b"
    tenant_c = "pool-safety-success-c"

    root_config.stub :max_connection_pools, 2 do
      ApplicationRecord.create_tenant(tenant_a) { User.count }
      pool_a = ApplicationRecord.with_tenant(tenant_a) { User.connection_pool }
      handler = ApplicationRecord.connection_handler

      ApplicationRecord.with_tenant(tenant_a, prohibit_shard_swapping: false) do
        pool_a.with_connection do |connection_a|
          ApplicationRecord.create_tenant(tenant_b) { User.count }
          ApplicationRecord.with_tenant(tenant_b, prohibit_shard_swapping: false) do
            assert_kind_of ActiveRecord::ConnectionAdapters::ConnectionPool, User.connection_pool
          end
          ApplicationRecord.create_tenant(tenant_c) { User.count }

          assert_equal 1, connection_a.select_value("SELECT 1")
          assert_same pool_a, tenant_pool(handler, tenant_a)
          assert_nil tenant_pool(handler, tenant_b)
          pool_c = tenant_pool(handler, tenant_c)
          assert_kind_of ActiveRecord::ConnectionAdapters::ConnectionPool, pool_c
          assert_equal 2, registered_tenant_pool_count(handler)
        end
      end
    end
  end

  test "all busy tenant pools reject creation with a capacity error" do
    root_config = ApplicationRecord.tenanted_root_config
    tenant_a = "pool-safety-reject-a"
    tenant_b = "pool-safety-reject-b"
    tenant_c = "pool-safety-reject-c"

    root_config.stub :max_connection_pools, 2 do
      ApplicationRecord.create_tenant(tenant_a) { User.count }
      pool_a = ApplicationRecord.with_tenant(tenant_a) { User.connection_pool }
      handler = ApplicationRecord.connection_handler
      tenant_c_config = root_config.new_tenant_config(tenant_c)

      ApplicationRecord.with_tenant(tenant_a, prohibit_shard_swapping: false) do
        pool_a.with_connection do |connection_a|
          ApplicationRecord.create_tenant(tenant_b) { User.count }
          pool_b = ApplicationRecord.with_tenant(tenant_b, prohibit_shard_swapping: false) { User.connection_pool }
          ApplicationRecord.with_tenant(tenant_b, prohibit_shard_swapping: false) do
            pool_b.with_connection do |connection_b|
              assert_raises(ActiveRecord::Tenanted::ConnectionPoolCapacityError) do
                ApplicationRecord.create_tenant(tenant_c)
              end

              assert_not File.exist?(tenant_c_config.database)
              assert_same pool_a, tenant_pool(handler, tenant_a)
              assert_same pool_b, tenant_pool(handler, tenant_b)
              assert_nil tenant_pool(handler, tenant_c)
              assert_equal 2, registered_tenant_pool_count(handler)
              assert_equal 1, connection_a.select_value("SELECT 1")
              assert_equal 1, connection_b.select_value("SELECT 1")
            end
          end
        end
      end
    end
  end

  private
    def registered_tenant_pool_count(handler)
      pool_manager = handler.send(:get_pool_manager, ApplicationRecord.connection_specification_name)
      pool_manager.pool_configs.count do |pool_config|
        pool_config.db_config.is_a?(ActiveRecord::Tenanted::DatabaseConfigurations::TenantConfig)
      end
    end

    def tenant_pool(handler, tenant)
      handler.retrieve_connection_pool(
        ApplicationRecord.connection_specification_name,
        role: :writing,
        shard: tenant,
        strict: false
      )
    end
end
