# frozen_string_literal: true

require "test_helper"

class ActiveRecord::TestTenantedFixtures < ActiveRecord::Tenanted::TestCase
  setup do
    @klass = Class.new do
      include(ActiveRecord::TestFixtures)
    end
  end

  # I know this is a private method, but it's the easiest place to test right now.
  test "transactional_tests_for_pool? should return false for the TemplateConfig" do
    test_object = @klass.new

    template_pool = pool_for_config(ActiveRecord::Tenanted::DatabaseConfigurations::TemplateConfig.new("test", "a", {}))
    tenant_pool = pool_for_config(ActiveRecord::Tenanted::DatabaseConfigurations::TenantConfig.new("test", "b", {}))
    normal_pool = pool_for_config(ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "c", {}))

    assert(test_object.send(:transactional_tests_for_pool?, normal_pool))
    assert(test_object.send(:transactional_tests_for_pool?, tenant_pool))
    assert_not(test_object.send(:transactional_tests_for_pool?, template_pool))
  end

  private
    def pool_for_config(db_config)
      ActiveRecord::ConnectionAdapters::ConnectionPool.new(
        ActiveRecord::ConnectionAdapters::PoolConfig.new(ActiveRecord::Base, db_config, :writing, :default)
      )
    end
end
