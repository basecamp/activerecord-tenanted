# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module Patches
      # TODO: upstream this `include_hidden:` patch
      module Migration
        private
          def configured_migrate_path
            return unless database = options[:database]

            config = ActiveRecord::Base.configurations.configs_for(
              env_name: Rails.env,
              name: database,
              include_hidden: true
            )

            Array(config&.migrations_paths).first
          end
      end

      # TODO: I think this is needed because there was no followup to rails/rails#46270.
      # See rails/rails@901828f2 from that PR for background.
      module DatabaseTasks
        private
          def with_temporary_pool(db_config, clobber: false)
            original_db_config = begin
              migration_class.connection_db_config
            rescue ActiveRecord::ConnectionNotDefined
              nil
            end

            begin
              pool = migration_class.connection_handler.establish_connection(db_config, clobber: clobber)

              yield pool
            ensure
              migration_class.connection_handler.establish_connection(original_db_config, clobber: clobber) if original_db_config
            end
          end
      end
    end
  end
end

require "rails/generators/active_record/migration.rb"
ActiveRecord::Generators::Migration.prepend(ActiveRecord::Tenanted::Patches::Migration)
ActiveRecord::Tasks::DatabaseTasks.prepend(ActiveRecord::Tenanted::Patches::DatabaseTasks)
