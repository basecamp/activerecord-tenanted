# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseConfigurations do
  for_each_db_config do
    test "it instantiates a RootConfig for the tenanted database" do
      config = ActiveRecord::Base.configurations.configs_for(include_hidden: true)

      assert_equal(
        {
          "isolated" => ActiveRecord::Tenanted::DatabaseConfigurations::RootConfig,
          "shared" => ActiveRecord::DatabaseConfigurations::HashConfig,
        },
        config.each_with_object({}) { |c, h| h[c.name] = c.class }
      )
    end
  end
end
