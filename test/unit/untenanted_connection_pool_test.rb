# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::UntenantedConnectionPool do
  with_scenario(:primary_db, :primary_record) do
    let(:config) { Object.new }
    let(:subject) { ActiveRecord::Tenanted::UntenantedConnectionPool.new(config, User) }

    [ :lease_connection,
      :checkout,
      :with_connection,
      :new_connection,
    ].each do |method|
      test "#{method} raises NoTenantError" do
        e = assert_raises(ActiveRecord::Tenanted::NoTenantError) do
          subject.send(method)
        end
        assert_equal("Cannot connect to a tenanted database while untenanted (User).", e.message)
      end
    end

    test "size returns max_connections from db_config" do
      def config.max_connections; 42; end
      assert_equal 42, subject.size
    end

    test "clear_query_cache does nothing" do
      assert_nil subject.clear_query_cache
    end

    describe "schema_reflection" do
      let(:subject) { ActiveRecord::Tenanted::UntenantedConnectionPool.new(base_config, User) }

      test "checks the schema cache dump against the migration files" do
        assert_instance_of(ActiveRecord::Tenanted::UntenantedConnectionPool::SchemaReflection, subject.schema_reflection)
        assert_equal(File.join(db_path, "tenanted_migrations"), subject.migrations_paths)
      end
    end
  end
end
