# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    class Railtie < ::Rails::Railtie
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
          if ActiveRecord::Tenanted.connection_class.present? && ActiveRecord::Tenanted.tenanted_rails_records
            subtenant_of ActiveRecord::Tenanted.connection_class
          end
        end

        ActiveSupport.on_load(:active_storage_record) do
          if ActiveRecord::Tenanted.connection_class.present? && ActiveRecord::Tenanted.tenanted_rails_records
            subtenant_of ActiveRecord::Tenanted.connection_class
          end
        end

        ActiveSupport.on_load(:action_text_record) do
          if ActiveRecord::Tenanted.connection_class.present? && ActiveRecord::Tenanted.tenanted_rails_records
            subtenant_of ActiveRecord::Tenanted.connection_class
          end
        end

        ActiveSupport.on_load(:active_support_test_case) do
          if ActiveRecord::Tenanted.connection_class.present?
            klass = ActiveRecord::Tenanted.connection_class.constantize

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
