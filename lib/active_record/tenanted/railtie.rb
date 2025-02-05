# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    class Railtie < ::Rails::Railtie
      config.active_record_tenanted = ActiveSupport::OrderedOptions.new

      # Set this in an initializer if you're tenanting a connection class other than
      # ApplicationRecord. This value controls how Rails integrates with your tenanted application.
      #
      # By default, Rails will configure the test database, test fixtures to use
      # "ApplicationRecord", but this can be set to `nil` to turn off the integrations entirely,
      # including Rails records (see `tenanted_rails_records` below).
      config.active_record_tenanted.connection_class = "ApplicationRecord"

      # Set this to false in an initializer if you don't want Rails records to share a connection
      # pool with the tenanted connection class.
      #
      # By default, this gem will configure ActionMailbox::Record, ActiveStorage::Record, and
      # ActionText::Record to create/use tables in the database associated with the
      # `connection_class`, and will share a connection pool with that class.
      #
      # This should only be turned off if your primary database configuration is not tenanted, and
      # that is where you want Rails to create the tables for these records.
      config.active_record_tenanted.tenanted_rails_records = true

      config.before_configuration do
        ActiveSupport.on_load(:active_record) do
          ActiveRecord::DatabaseConfigurations.register_db_config_handler do |env_name, name, _, config|
            next unless config.fetch(:tenanted, false)
            ActiveRecord::Tenanted::DatabaseConfigurations::RootConfig.new(env_name, name, config)
          end
        end
      end

      initializer "active_record_tenanted.active_record_base" do
        ActiveSupport.on_load(:active_record) do
          prepend ActiveRecord::Tenanted::Base
        end
      end

      initializer "active_record-tenanted.monkey_patches" do
        ActiveSupport.on_load(:active_record) do
          # require "rails/generators/active_record/migration.rb"
          # ActiveRecord::Generators::Migration.prepend(ActiveRecord::Tenanted::Patches::Migration)
          ActiveRecord::Tasks::DatabaseTasks.prepend(ActiveRecord::Tenanted::Patches::DatabaseTasks)
        end

        ActiveSupport.on_load(:active_record_fixtures) do
          include(ActiveRecord::Tenanted::Patches::TestFixtures)
        end
      end

      config.after_initialize do
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

        ActiveSupport.on_load(:active_support_test_case) do
          if Rails.application.config.active_record_tenanted.connection_class.present?
            klass = Rails.application.config.active_record_tenanted.connection_class.constantize

            klass.current_tenant = "#{Rails.env}-tenant" if Rails.env.test?
            parallelize_setup do |worker|
              klass.current_tenant = "#{Rails.env}-tenant-#{worker}"
            end
          end
        end
      end
    end
  end
end
