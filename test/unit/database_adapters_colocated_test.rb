# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::Colocated do
  # Create a minimal class that includes the Colocated module
  let(:minimal_class) do
    Class.new do
      include ActiveRecord::Tenanted::DatabaseAdapters::Colocated

      attr_reader :db_config

      def initialize(db_config)
        @db_config = db_config
      end
    end
  end

  let(:db_config) do
    config_hash = { adapter: "postgresql", database: "myapp_%{tenant}" }
    ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config_hash)
  end

  let(:adapter) { minimal_class.new(db_config) }

  describe "#colocated?" do
    test "returns true when module is included" do
      assert_equal true, adapter.colocated?
    end
  end

  describe "#create_colocated_database" do
    test "raises NotImplementedError if not implemented" do
      error = assert_raises(NotImplementedError) do
        adapter.create_colocated_database
      end

      assert_match(/must implement #create_colocated_database/, error.message)
    end
  end

  describe "#drop_colocated_database" do
    test "raises NotImplementedError if not implemented" do
      error = assert_raises(NotImplementedError) do
        adapter.drop_colocated_database
      end

      assert_match(/must implement #drop_colocated_database/, error.message)
    end
  end

  describe "when methods are implemented" do
    let(:implemented_class) do
      Class.new do
        include ActiveRecord::Tenanted::DatabaseAdapters::Colocated

        attr_reader :db_config, :created, :dropped

        def initialize(db_config)
          @db_config = db_config
          @created = false
          @dropped = false
        end

        def create_colocated_database
          @created = true
        end

        def drop_colocated_database
          @dropped = true
        end
      end
    end

    let(:implemented_adapter) { implemented_class.new(db_config) }

    test "create_colocated_database works when implemented" do
      assert_equal false, implemented_adapter.created
      implemented_adapter.create_colocated_database
      assert_equal true, implemented_adapter.created
    end

    test "drop_colocated_database works when implemented" do
      assert_equal false, implemented_adapter.dropped
      implemented_adapter.drop_colocated_database
      assert_equal true, implemented_adapter.dropped
    end
  end
end
