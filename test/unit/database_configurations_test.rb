# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseConfigurations do
  let(:all_configs) { ActiveRecord::Base.configurations.configs_for(include_hidden: true) }

  with_scenario(:vanilla_named_primary, :tenanted_primary) do
    test "it instantiates a RootConfig for the tenanted database" do
      assert_equal(
        {
          "tenanted" => ActiveRecord::Tenanted::DatabaseConfigurations::RootConfig,
          "shared" => ActiveRecord::DatabaseConfigurations::HashConfig,
        },
        all_configs.each_with_object({}) { |c, h| h[c.name] = c.class }
      )
    end

    test "the RootConfig has tasks turned off by default" do
      tenanted_config = all_configs.find { |c| c.name == "tenanted" }

      assert_not tenanted_config.database_tasks?
    end
  end
end
