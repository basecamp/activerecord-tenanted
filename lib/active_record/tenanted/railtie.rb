# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    class Railtie < ::Rails::Railtie
      config.before_configuration do
        ActiveSupport.on_load(:active_record) do
          ActiveRecord::DatabaseConfigurations.register_db_config_handler do |env_name, name, _, config|
            next unless config.fetch(:tenanted, false)
            ActiveRecord::Tenanted::DatabaseConfigurations::TemplateConfig.new(env_name, name, config)
          end
        end
      end

      # TODO this should go in a generated file in the app
      initializer "active_record-tenanted.development_subdomains" do |app|
        app.config.hosts << /.*\..*\.localhost/ if Rails.env.development?
      end

      # TODO this should go in a generated file in the app
      initializer "active_record-tenanted.middleware" do |app|
        app.middleware.use ActiveRecord::Tenanted::TenantSelector
      end

      initializer "active_record-tenanted.base_records" do
        ActiveSupport.on_load(:active_record) do
          prepend ActiveRecord::Tenanted::Stub
        end

        ActiveSupport.on_load(:active_storage_record) do
          # ActiveStorage::Record needs to share a connection with ApplicationRecord
          tenanted_with "ApplicationRecord"
        end

        ActiveSupport.on_load(:action_text_record) do
          # ActionText::Record needs to share a connection with ApplicationRecord
          tenanted_with "ApplicationRecord"
        end

        ActiveSupport.on_load(:action_mailbox_record) do
          # ActionMailbox::Record needs to share a connection with ApplicationRecord
          tenanted_with "ApplicationRecord"
        end
      end

      initializer "active_record-tenanted.test_framework" do
        ActiveSupport.on_load(:active_support_test_case) do
          parallelize_setup do |worker|
            ActiveRecord::Tenanted::Tenant.current = "#{Rails.env}-tenant-#{worker}"
          end
        end

        ActiveSupport.on_load(:action_dispatch_integration_test) do
          setup do
            integration_session.host = "#{ActiveRecord::Tenanted::Tenant.current}.example.com"
          end
        end

        ActiveSupport.on_load(:after_initialize) do
          ActiveRecord::Tenanted::Tenant.current = "#{Rails.env}-tenant" if Rails.env.local?
        end
      end

      initializer "active_record-tenanted.monkey_patches.active_record" do
        ActiveSupport.on_load(:active_record) do
          require "rails/generators/active_record/migration.rb"
          ActiveRecord::Generators::Migration.prepend(ActiveRecord::Tenanted::Patches::Migration)
          ActiveRecord::Tasks::DatabaseTasks.prepend(ActiveRecord::Tenanted::Patches::DatabaseTasks)
        end

        ActiveSupport.on_load(:active_record_fixtures) do
          include(ActiveRecord::Tenanted::Patches::TestFixtures)
        end
      end
    end
  end
end
