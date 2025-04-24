# frozen_string_literal: true

namespace :db do
  desc "Migrate the database for tenant ARTENANT"
  task "migrate:tenant" => "load_config" do
    unless ActiveRecord::Tenanted.connection_class
      warn "ActiveRecord::Tenanted integration is not configured via connection_class"
      next
    end

    unless ActiveRecord::Tenanted::DatabaseTasks.root_database_config
      warn "WARNING: No tenanted database found, skipping tenanted migration"
    else
      begin
        verbose_was = ActiveRecord::Migration.verbose
        ActiveRecord::Migration.verbose = ActiveRecord::Tenanted::DatabaseTasks.verbose?

        ActiveRecord::Tenanted::DatabaseTasks.migrate_tenant
      ensure
        ActiveRecord::Migration.verbose = verbose_was
      end
    end
  end

  desc "Migrate the database for all existing tenants"
  task "migrate:tenant:all" => "load_config" do
    unless ActiveRecord::Tenanted.connection_class
      warn "ActiveRecord::Tenanted integration is not configured via connection_class"
      next
    end

    verbose_was = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = ActiveRecord::Tenanted::DatabaseTasks.verbose?

    ActiveRecord::Tenanted::DatabaseTasks.migrate_all
  ensure
    ActiveRecord::Migration.verbose = verbose_was
  end

  desc "Drop and recreate all tenant databases from their schema for the current environment"
  task "reset:tenant" => [ "db:drop:tenant", "db:migrate:tenant" ]

  desc "Drop all tenanted databases for the current environment"
  task "drop:tenant" => "load_config" do
    unless ActiveRecord::Tenanted::DatabaseTasks.root_database_config
      warn "WARNING: No tenanted database found, skipping tenanted reset"
    else
      begin
        verbose_was = ActiveRecord::Migration.verbose
        ActiveRecord::Migration.verbose = ActiveRecord::Tenanted::DatabaseTasks.verbose?

        ActiveRecord::Tenanted::DatabaseTasks.drop_all
      ensure
        ActiveRecord::Migration.verbose = verbose_was
      end
    end
  end

  desc "Set the current tenant to ARTENANT if present, else the environment default"
  task "tenant" => "load_config" do
    unless ActiveRecord::Tenanted.connection_class
      warn "ActiveRecord::Tenanted integration is not configured via connection_class"
      next
    end

    ActiveRecord::Tenanted::DatabaseTasks.set_current_tenant
  end
end

# Decorate database tasks with the tenanted version.
task "db:migrate" => "db:migrate:tenant:all"
task "db:prepare" => "db:migrate:tenant:all"
task "db:reset"   => "db:reset:tenant"
task "db:drop"    => "db:drop:tenant"

# Ensure a default tenant is set for database tasks that may need it.
task "db:fixtures:load" => "db:tenant"
task "db:seed"          => "db:tenant"
