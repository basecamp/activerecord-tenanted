module ActiveRecord
  module Tenanted
    module Tenant
      extend ActiveSupport::Concern

      class_methods do
        def connecting_to(tenant_name)
          ApplicationRecord.connecting_to(shard: tenant_name, role: ActiveRecord.writing_role)
        end

        def connected_to(tenant_name, &block)
          ApplicationRecord.connected_to(shard: tenant_name, role: ActiveRecord.writing_role) do
            ApplicationRecord.prohibit_shard_swapping(true, &block)
          end
        end

        def while_untenanted(&block)
          ApplicationRecord.connected_to(shard: PROTOSHARD, role: ActiveRecord.reading_role, &block)
        end

        def untenanted?
          ApplicationRecord.current_shard == PROTOSHARD
        end

        def current
          ApplicationRecord.current_shard
        end

        def exist?(tenant_name)
          File.exist?(config.database_path_for(tenant_name))
        end

        def create!(tenant_name)
          raise TenantAlreadyExistsError if exist?(tenant_name)
          connected_to(tenant_name) do
            ApplicationRecord.connection_pool
            yield if block_given?
          end
        end

        def destroy(tenant_name)
          return unless exist?(tenant_name)

          ApplicationRecord.connected_to(shard: tenant_name, role: ActiveRecord.writing_role) do
            ApplicationRecord.lease_connection.log("/* destroying tenant database */", "DESTROY [tenant=#{tenant_name}]")
            ApplicationRecord.remove_connection
          end

          FileUtils.rm(config.database_path_for(tenant_name))
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
