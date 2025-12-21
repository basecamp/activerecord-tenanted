# frozen_string_literal: true

require "test_helper"

# This file tests the PostgreSQL adapter factory and default behavior
# For detailed tests of each strategy, see:
# - database_adapters_postgresql_schema_test.rb
# - database_adapters_postgresql_database_test.rb
# - database_adapters_postgresql_base_test.rb
# - database_adapters_postgresql_factory_test.rb

describe "ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL" do
  describe "default adapter" do
    test "creates Database adapter by default" do
      config_hash = { adapter: "postgresql", database: "myapp" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapter.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Database, adapter
    end

    test "creates Schema adapter when schema_name_pattern is set" do
      config_hash = { adapter: "postgresql", database: "myapp_%{tenant}", schema_name_pattern: "%{tenant}" }
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)

      adapter = ActiveRecord::Tenanted::DatabaseAdapter.new(db_config)

      assert_instance_of ActiveRecord::Tenanted::DatabaseAdapters::PostgreSQL::Schema, adapter
    end
  end
end
