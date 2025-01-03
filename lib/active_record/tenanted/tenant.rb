# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module Tenant
      def self.current=(tenant_name)
        ApplicationRecord.connecting_to(shard: tenant_name, role: ActiveRecord.writing_role)
      end

      def self.current
        ApplicationRecord.current_shard
      end

      def self.while_tenanted(tenant_name, &block)
        ApplicationRecord.connected_to(shard: tenant_name, role: ActiveRecord.writing_role) do
          ApplicationRecord.prohibit_shard_swapping(true, &block)
        end
      end

      def self.while_untenanted(&block)
        ApplicationRecord.connected_to(shard: PROTOSHARD, role: ActiveRecord.reading_role, &block)
      end

      def self.untenanted?
        ApplicationRecord.current_shard == PROTOSHARD
      end

      def self.exist?(tenant_name)
        File.exist?(config.database_path_for(tenant_name))
      end

      def self.create(tenant_name)
        raise TenantAlreadyExistsError if exist?(tenant_name)

        while_tenanted(tenant_name) do
          ApplicationRecord.connection_pool
          yield if block_given?
        end
      end

      def self.destroy(tenant_name)
        return unless exist?(tenant_name)

        while_tenanted(tenant_name) do
          ApplicationRecord.lease_connection.log("/* destroying tenant database */", "DESTROY [tenant=#{tenant_name}]")
        ensure
          ApplicationRecord.remove_connection
        end

        FileUtils.rm(config.database_path_for(tenant_name))
      end

      def self.requested_tenant(request)
        request.subdomain
      end

      def self.config
        @config ||= ApplicationRecord.configurations
                      .configs_for(env_name: Rails.env, include_hidden: true)
                      .find { |c| c.instance_of?(ActiveRecord::Tenanted::DatabaseConfigurations::TemplateConfig) }
      end
    end
  end
end
