# frozen_string_literal: true

require_relative "tenanted/version"

module ActiveRecord
  module Tenanted
  end
end

require_relative "tenanted/database_configurations"

require_relative "tenanted/railtie"
