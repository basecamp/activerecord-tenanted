# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    class NoCurrentTenantError < StandardError; end
    class TenantAlreadyExistsError < StandardError; end
  end
end

require_relative "tenanted/base"
require_relative "tenanted/database_configurations"
require_relative "tenanted/patches"
require_relative "tenanted/railtie"
require_relative "tenanted/tenant"
require_relative "tenanted/tenant_selector"
require_relative "tenanted/version"
