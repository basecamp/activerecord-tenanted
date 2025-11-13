# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    class Railtie < ::Rails::Railtie
      config.active_record_tenanted = ActiveSupport::OrderedOptions.new

      # Set this in an initializer if you're tenanting a connection class other than
      # ApplicationRecord. This value indicates the connection class that this gem uses to integrate
      # with a broad set of Rails subsystems, including:
      #
      # - Active Job
      # - Active Storage
      # - Action Cable
      # - Action Dispatch middleware (Tenant Selector)
      # - Test frameworks and fixtures
      #
      # Defaults to "ApplicationRecord", but this can be set to `nil` to turn off the integrations
      # entirely.
      config.active_record_tenanted.connection_class = "ApplicationRecord"

      # Set this to a lambda that takes a request object and returns the tenant name. It's used by:
      #
      # - Action Dispatch middleware (Tenant Selector)
      # - Action Cable connections
      #
      # Defaults to the request subdomain.
      config.active_record_tenanted.tenant_resolver = ->(request) { request.subdomain }

      # Set this to false in an initializer if you don't want Rails records to share a connection
      # pool with the tenanted connection class.
      #
      # By default, this gem will configure ActionMailbox::Record, ActiveStorage::Record, and
      # ActionText::Record to create/use tables in the database associated with the
      # `connection_class`, and will share a connection pool with that class.
      #
      # This should only be turned off if your primary database configuration is not tenanted, and
      # that is where you want Rails to create the tables for these records.
      #
      # Defaults to `true`.
      config.active_record_tenanted.tenanted_rails_records = true

      # Set this to control whether the Rails logger will include the tenant name in a tag in each
      # log line.
      #
      # Defaults to false in development and test environments, and true in all other environments.
      config.active_record_tenanted.log_tenant_tag = !Rails.env.local?

      # Set this to override the default tenant name used in development and test environments.
      #
      # This is the default tenant name used by database tasks and in the Rails console. In both
      # cases, this can be overridden at runtime by setting the `ARTENANT` environment variable.
      #
      # Notably, it's also the tenant name used by the testing frameworks, so you may need to set
      # this if you have application-specific constraints on tenant names.
      #
      # Defaults to "development-tenant" in development and "test-tenant" in test environments.
      config.active_record_tenanted.default_tenant = Rails.env.local? ? "#{Rails.env}-tenant" : nil

      # Set this to true to allow Active Storage to work without a tenant context.
      #
      # When enabled, Active Storage will fall back to default behavior (non-tenanted storage)
      # when there is no current tenant. This allows models in the primary database to use
      # Active Storage alongside tenanted models.
      #
      # When disabled (default), Active Storage will raise NoTenantError if accessed without
      # a tenant context, maintaining strict tenant isolation.
      #
      # Defaults to `false`.
      config.active_record_tenanted.allow_untenanted_active_storage = false

      config.before_configuration do
        ActiveSupport.on_load(:active_record_database_configurations) do
          ActiveRecord::Tenanted::DatabaseConfigurations.register_db_config_handler
        end
      end

      config.before_initialize do
        Rails.application.configure do
          if config.active_record_tenanted.connection_class.present?
            config.middleware.use ActiveRecord::Tenanted::TenantSelector
          end
        end
      end

      initializer "active_record_tenanted.active_record_base" do
        ActiveSupport.on_load(:active_record) do
          prepend ActiveRecord::Tenanted::Base
          ActiveRecord::Relation.prepend ActiveRecord::Tenanted::Relation
        end
      end

      initializer("active_record_tenanted.active_record_schema_cache",
                  before: "active_record.copy_schema_cache_config") do
        # Rails must be able to load the schema for a tenanted model without a database connection
        # (e.g., boot-time eager loading, or calling User.new to build a form). This gem relies on
        # reading from the schema cache dump to do that.
        #
        # Rails defaults use_schema_cache_dump to true, but we explicitly re-set it here because if
        # this is ever turned off, Rails will not work as expected.
        config.active_record.use_schema_cache_dump = true

        # The schema cache version check needs to query the database, which isn't always possible
        # for tenanted models.
        config.active_record.check_schema_cache_dump_version = false
      end

      initializer "active_record_tenanted.monkey_patches" do
        ActiveSupport.on_load(:active_record) do
          prepend ActiveRecord::Tenanted::Patches::Attributes
          ActiveRecord::Tasks::DatabaseTasks.prepend ActiveRecord::Tenanted::Patches::DatabaseTasks
        end
      end

      initializer "active_record_tenanted.active_job" do
        ActiveSupport.on_load(:active_job) do
          prepend ActiveRecord::Tenanted::Job
        end
      end

      initializer "active_record_tenanted.action_cable_connection" do
        ActiveSupport.on_load(:action_cable_connection) do
          prepend ActiveRecord::Tenanted::CableConnection::Base
        end
      end

      initializer "active_record_tenanted.global_id", after: "global_id" do
        ::GlobalID.prepend ActiveRecord::Tenanted::GlobalId
        ::GlobalID::Locator.use GlobalID.app, ActiveRecord::Tenanted::GlobalId::Locator.new
      end

      initializer "active_record_tenanted.active_storage", after: "active_storage.services" do
        # TODO: Add a hook for Disk Service. Without that, there's no good way to include this
        # module into the class before the service is initialized.
        # As a workaround, explicitly require this file.
        require "active_storage/service/disk_service"
        ActiveStorage::Service::DiskService.prepend ActiveRecord::Tenanted::Storage::DiskService
      end

      initializer "active_record_tenanted.active_storage_blob" do
        ActiveSupport.on_load(:active_storage_blob) do
          prepend ActiveRecord::Tenanted::Storage::Blob
        end
      end

      initializer "active_record_tenanted.active_record_connection_adapter" do
        ActiveSupport.on_load(:active_record) do
          ActiveRecord::ConnectionAdapters::AbstractAdapter.prepend ActiveRecord::Tenanted::ConnectionAdapter
        end
      end

      initializer "active_record_tenanted.action_mailer" do
        ActiveSupport.on_load(:action_mailer) do
          prepend ActiveRecord::Tenanted::Mailer
        end
      end

      initializer "active_record_tenanted.action_dispatch", before: "action_dispatch.configure" do
        config.action_dispatch.rescue_responses["ActiveRecord::Tenanted::TenantDoesNotExistError"] = :not_found
      end

      config.after_initialize do
        ActiveRecord::QueryLogs.taggings = ActiveRecord::QueryLogs.taggings.merge(
          tenant: ->(context) { context[:connection].tenant }
        )

        if defined?(Rails::Console)
          require "rails/commands/console/irb_console"
          Rails::Console::IRBConsole.prepend ActiveRecord::Tenanted::Console::IRBConsole
          Rails::Console::ReloadHelper.prepend ActiveRecord::Tenanted::Console::ReloadHelper
        end

        ActiveSupport.on_load(:action_mailbox_record) do
          if Rails.application.config.active_record_tenanted.connection_class.present? &&
             Rails.application.config.active_record_tenanted.tenanted_rails_records
            subtenant_of Rails.application.config.active_record_tenanted.connection_class
          end
        end

        ActiveSupport.on_load(:active_storage_record) do
          if Rails.application.config.active_record_tenanted.connection_class.present? &&
             Rails.application.config.active_record_tenanted.tenanted_rails_records
            subtenant_of Rails.application.config.active_record_tenanted.connection_class
          end
        end

        ActiveSupport.on_load(:action_text_record) do
          if Rails.application.config.active_record_tenanted.connection_class.present? &&
             Rails.application.config.active_record_tenanted.tenanted_rails_records
            subtenant_of Rails.application.config.active_record_tenanted.connection_class
          end
        end

        if Rails.env.test?
          ActiveSupport.on_load(:active_support_test_case) do
            prepend ActiveRecord::Tenanted::Testing::ActiveSupportTestCase
          end

          ActiveSupport.on_load(:action_dispatch_integration_test) do
            prepend ActiveRecord::Tenanted::Testing::ActionDispatchIntegrationTest
            ActionDispatch::Integration::Session.prepend ActiveRecord::Tenanted::Testing::ActionDispatchIntegrationSession
          end

          ActiveSupport.on_load(:action_dispatch_system_test_case) do
            prepend ActiveRecord::Tenanted::Testing::ActionDispatchSystemTestCase
          end

          ActiveSupport.on_load(:active_record_fixtures) do
            prepend ActiveRecord::Tenanted::Testing::ActiveRecordFixtures
          end

          ActiveSupport.on_load(:active_job_test_case) do
            prepend ActiveRecord::Tenanted::Testing::ActiveJobTestCase
          end

          ActiveSupport.on_load(:action_cable_connection_test_case) do
            prepend ActiveRecord::Tenanted::Testing::ActionCableTestCase
          end
        end
      end

      rake_tasks do
        load File.expand_path(File.join(__dir__, "../../tasks/active_record/tenanted_tasks.rake"))
      end
    end
  end
end
