# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::Base do
  let(:adapter_class) do
    Class.new(ActiveRecord::Tenanted::DatabaseAdapters::Base) do
      def valid_tenant_name?(tenant_name)
        tenant_name == "foo"
      end
    end
  end
  let(:adapter) { adapter_class.new(Object.new) }

  describe "#validate_tenant_name" do
    test "accepts a name the adapter says is valid" do
      assert_nothing_raised { adapter.validate_tenant_name("foo") }
    end

    test "raises BadTenantNameError on a name the adapter says is invalid" do
      error = assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
        adapter.validate_tenant_name("bar")
      end

      assert_includes(error.message, "\"bar\"")
    end
  end
end
