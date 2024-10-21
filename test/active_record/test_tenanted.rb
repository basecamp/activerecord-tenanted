# frozen_string_literal: true

require "test_helper"

class ActiveRecord::TestTenanted < Minitest::Test
  def test_that_it_has_a_version_number
    assert_not_nil ::ActiveRecord::Tenanted::VERSION
  end

  def test_it_does_something_useful
    assert false
  end
end
