# frozen_string_literal: true

require "active_record"

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem_extension(ActiveRecord)
loader.inflector.inflect(
  "sqlite" => "SQLite",
  "mysql" => "MySQL",
  "postgresql" => "PostgreSQL",
)
loader.setup

module ActiveRecord
  module Tenanted
    # Base exception class for the library.
    class Error < StandardError; end

    # Raised when database access is attempted without a current tenant having been set.
    class NoTenantError < Error; end

    # Raised when database access is attempted on a record whose tenant does not match the current tenant.
    class WrongTenantError < Error; end

    # Raised when attempting to locate a GlobalID without a tenant.
    class MissingTenantError < Error; end

    # Raised when attempting to create a tenant that already exists.
    class TenantExistsError < Error; end

    # Raised when attempting to create a tenant with illegal characters in it.
    class BadTenantNameError < Error; end

    # Raised when the application's tenant configuration is invalid.
    class TenantConfigurationError < Error; end

    # Raised when implicit creation is disabled and a tenant is referenced that does not exist
    class TenantDoesNotExistError < Error; end

    # Raised when the Rails integration is being invoked but has not been configured.
    class IntegrationNotConfiguredError < Error; end

    # Raised when an unsupported database adapter is used.
    class UnsupportedDatabaseError < Error; end

    # Return the constantized connection class configured in `config.active_record_tenanted.connection_class`,
    # or nil if none is configured.
    def self.connection_class
      # TODO: cache this / speed this up
      Rails.application.config.active_record_tenanted.connection_class&.constantize
    end

    # Return an Array of the tenanted database configurations.
    def self.base_configs(configurations = ActiveRecord::Base.configurations)
      configurations
        .configs_for(env_name: ActiveRecord::Tasks::DatabaseTasks.env, include_hidden: true)
        .select { |c| c.configuration_hash[:tenanted] }
    end
  end
end

loader.eager_load

ActiveSupport.run_load_hooks :active_record_tenanted, ActiveRecord::Tenanted
