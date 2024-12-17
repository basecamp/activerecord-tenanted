module ActiveRecord
  module Tenanted
    module Tenant
      extend ActiveSupport::Concern

      class_methods do
        def connecting_to(tenant_name)
          ApplicationRecord.connecting_to(shard: tenant_name)
        end

        def connected_to(tenant_name, &block)
          ApplicationRecord.connected_to(shard: tenant_name, &block)
        end

        def current
          ApplicationRecord.current_shard
        end

        def exist?(tenant_name)
          File.exist?(config.database_path_for(tenant_name))
        end

        def extract_slug(request)
          request.subdomain
        end

        def config
          @config ||= ApplicationRecord.configurations
              .configs_for(env_name: Rails.env, include_hidden: true)
              .find { |c| c.instance_of?(ActiveRecord::Tenanted::DatabaseConfigurations::TemplateConfig) }
        end
      end
    end
  end
end
