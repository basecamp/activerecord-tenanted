# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    module DatabaseAdapters
      module PostgreSQL
        # Base class for PostgreSQL multi-tenancy strategies
        #
        # PostgreSQL supports two isolation strategies:
        # 1. Schema-based: Multiple schemas within a single database (default)
        # 2. Database-based: Separate databases per tenant
        #
        # This base class provides common functionality for both strategies.
        class Base
          attr_reader :db_config

          def initialize(db_config)
            @db_config = db_config
          end

          # Abstract methods - must be implemented by subclasses
          def tenant_databases
            raise NotImplementedError, "#{self.class.name} must implement #tenant_databases"
          end

          def create_database
            raise NotImplementedError, "#{self.class.name} must implement #create_database"
          end

          def drop_database
            raise NotImplementedError, "#{self.class.name} must implement #drop_database"
          end

          def database_exist?
            raise NotImplementedError, "#{self.class.name} must implement #database_exist?"
          end

          def database_path
            raise NotImplementedError, "#{self.class.name} must implement #database_path"
          end

          # Shared validation logic for PostgreSQL identifiers
          def validate_tenant_name(tenant_name)
            return if tenant_name == "%" || tenant_name == "(.+)"

            identifier = identifier_for(tenant_name)
            return if identifier.include?("%{") || identifier.include?("%}")

            # PostgreSQL identifier max length is 63 bytes
            if identifier.length > 63
              raise ActiveRecord::Tenanted::BadTenantNameError,
                "PostgreSQL identifier too long (max 63 characters): #{identifier.inspect}"
            end

            # PostgreSQL identifiers: letters, numbers, underscores, dollar signs, hyphens
            if identifier.match?(/[^a-z0-9_$-]/i)
              raise ActiveRecord::Tenanted::BadTenantNameError,
                "PostgreSQL identifier contains invalid characters " \
                "(only letters, numbers, underscores, $, and hyphens allowed): #{identifier.inspect}"
            end

            # Must start with letter or underscore
            unless identifier.match?(/^[a-z_]/i)
              raise ActiveRecord::Tenanted::BadTenantNameError,
                "PostgreSQL identifier must start with a letter or underscore: #{identifier.inspect}"
            end
          end

          # Returns the identifier (database or schema name) for validation
          # Subclasses can override if needed
          def identifier_for(tenant_name)
            sprintf(db_config.database, tenant: tenant_name.to_s)
          end

          def database_ready?
            database_exist?
          end

          def acquire_ready_lock(&block)
            # No file-system locking needed for server-based databases
            yield
          end

          def ensure_database_directory_exists
            # No directory needed for server-based databases
            true
          end

          def test_workerize(db, test_worker_id)
            test_worker_suffix = "_#{test_worker_id}"

            if db.end_with?(test_worker_suffix)
              db
            else
              db + test_worker_suffix
            end
          end

          def path_for(name)
            # For PostgreSQL, path is just the name (database or schema)
            name
          end
        end
      end
    end
  end
end
