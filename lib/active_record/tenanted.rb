# frozen_string_literal: true

require "active_record"

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem_extension(ActiveRecord)
loader.setup

module ActiveRecord
  module Tenanted
    # Base exception class for the library.
    class Error < StandardError; end

    # Raised when database access is attempted without a current tenant having been set.
    class NoTenantError < Error; end
  end
end

loader.eager_load

ActiveSupport.run_load_hooks :active_record_tenanted, ActiveRecord::Tenanted
