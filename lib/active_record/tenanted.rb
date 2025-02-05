# frozen_string_literal: true

require "active_record"

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem_extension(ActiveRecord)
loader.setup

module ActiveRecord
  module Tenanted
    # Set this in an initializer if you're tenanting a connection class other than
    # ApplicationRecord. This value controls how Rails integrates with your tenanted application.
    #
    # By default, Rails will configure the test database, test fixtures to use "ApplicationRecord",
    # but this can be set to `nil` to turn off the integrations entirely, including Rails records
    # (see ActiveRecord::Tenanted.tenanted_rails_records).
    mattr_accessor :connection_class, default: "ApplicationRecord"

    # Set this to false in an initializer if you don't want Rails records to share a connection pool
    # with the tenanted connection class.
    #
    # By default, this gem will configure ActionMailbox::Record, ActiveStorage::Record, and
    # ActionText::Record to create/use tables in the database associated with the
    # `connection_class`, and will share a connection pool with that class.
    #
    # This should only be turned off if your primary database configuration is not tenanted, and
    # that is where you want Rails to create the tables for these records.
    mattr_accessor :tenanted_rails_records, default: true

    # Base exception class for the library.
    class Error < StandardError; end

    # Raised when database access is attempted without a current tenant having been set.
    class NoTenantError < Error; end
  end
end

loader.eager_load

ActiveSupport.run_load_hooks :active_record_tenanted, ActiveRecord::Tenanted
