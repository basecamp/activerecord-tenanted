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
end

ActiveSupport.on_load(:active_storage_record) do
  tenanted_with "ApplicationRecord"
end

ActiveSupport.on_load(:active_support_test_case) do
  parallelize_setup do |worker|
    Tenant.connecting_to("#{Rails.env}-tenant-#{worker}")
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  setup do
    integration_session.host = "#{Tenant.current}.example.com"
  end
end

ActiveSupport.on_load(:after_initialize) do
  ::Tenant.connecting_to("#{Rails.env}-tenant") if Rails.env.local?
end
