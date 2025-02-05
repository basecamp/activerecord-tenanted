# Load the Rails application.
require_relative "application"

# turn off the Rails integrations
ActiveSupport.on_load(:active_record_tenanted) do
  Rails.application.config.active_record_tenanted.connection_class = nil
end

# Initialize the Rails application.
Rails.application.initialize!
