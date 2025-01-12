module ActiveRecord
  module Tenanted
    module Job
      extend ActiveSupport::Concern

      prepended do
        attr_accessor :tenant

        def serialize
          super.merge!({"tenant" => ActiveRecord::Tenanted::Tenant.current})
        end

        def deserialize(job_data)
          super
          self.tenant = job_data["tenant"]
        end

        def perform_now
          ActiveRecord::Tenanted::Tenant.while_tenanted(tenant) do
            super
          end
        end
      end
    end
  end
end

ActiveSupport.on_load(:active_job) do
  prepend ActiveRecord::Tenanted::Job
end
