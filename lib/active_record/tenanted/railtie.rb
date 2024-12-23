# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    class Railtie < ::Rails::Railtie
      initializer "active_record-tenanted.development_subdomains" do |app|
        app.config.hosts << /.*\..*\.localhost/ if Rails.env.development?
      end

      initializer "active_record-tenanted.middleware" do |app|
        app.middleware.use ActiveRecord::Tenanted::TenantSelector
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  extend ActiveRecord::Tenanted::Stub

  ActiveRecord::DatabaseConfigurations.register_db_config_handler do |env_name, name, _, config|
    next unless config.fetch(:tenanted, false)
    ActiveRecord::Tenanted::DatabaseConfigurations::TemplateConfig.new(env_name, name, config)
  end
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

ActiveSupport.on_load(:active_support_test_case) do
  parallelize_setup do |worker|
    ::Tenant.current = "#{Rails.env}-tenant-#{worker}"
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  setup do
    integration_session.host = "#{Tenant.current}.example.com"
  end
end

ActiveSupport.on_load(:after_initialize) do
  ::Tenant.current = "#{Rails.env}-tenant" if Rails.env.local?
end
