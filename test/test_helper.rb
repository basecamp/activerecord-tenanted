# frozen_string_literal: true

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require "rails"
require "rails/test_help"

require "minitest/spec"

module ActiveRecord
  module Tenanted
    class TestCase < ActiveSupport::TestCase
      extend Minitest::Spec::DSL
    end
  end
end

# make TestCase the default
Minitest::Spec.register_spec_type(//, ActiveRecord::Tenanted::TestCase)
