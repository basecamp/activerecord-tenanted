# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    class Railtie < ::Rails::Railtie
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::DatabaseConfigurations.register_db_config_handler do |env_name, name, _, config|
    next unless config.fetch(:tenanted, false)
    ActiveRecord::Tenanted::DatabaseConfigurations::RootConfig.new(env_name, name, config)
  end
end
