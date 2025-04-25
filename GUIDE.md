# Active Record Tenanting

> [!NOTE]
> This file will eventually become a complete "Rails Guide"-style document explaining Active Record tenanting with this gem.
>
> In the meantime, it is a work-in-progress containing:
>
> - skeleton outline for documentation
> - functional roadmap represented as to-do checklists


## Introduction

> [!TIP]
> If you're not familiar with how Rails's built-in horizontal sharding works, it may be worth reading the Rails Guide on [Multiple Databases with Active Record](https://guides.rubyonrails.org/active_record_multiple_databases.html#setting-up-your-application) before proceeding.

Documentation outline:

- this gem primarily extends Active Record,
  - essentially creating a new Connection Pool for each tenant,
  - and extending horizontal shard swapping to support these pools.
  - also provides test helpers to make it easy to handle tenanting in your test suite
- but also touches many other parts of Rails
  - integrations for Middleware, Action View Caching, Active Job, Action Cable, Active Storage, Action Mailbox, and Action Text
  - support and documentation for Solid Cache, Solid Queue, Solid Cable, and Turbo Rails
- a Tenant is just a string that is used for:
  - the sqlite database filename (or perhaps the pg/mysql database name in the future)
  - configuring either tenant-by-subdomain or a tenant-by-root-path-element
  - fragment cache disambiguation
  - global id disambiguation
  - invalid characters in a tenant name
    - and how the application may want to do additional validation (e.g. ICANN subdomain restrictions)
  - `#tenant` is a readonly attribute on all tenanted model instances
  - `.current_tenant` returns the execution context for the model connection class
- talk a bit about busted assumptions about shared state
  - database ids are no longer unique
  - global ids are no longer global
  - cache is no longer global
  - cable channels are no longer global
  - jobs are no longer global
- and what we do in this gem to help manage that "current tenant" state
- reference existing approaches/projects, maybe talk about differences
  - discussion at https://www.reddit.com/r/rails/comments/1ik7caq/multitenancy_vs_multi_instances/
  - [Kolide's 30 Line Rails Multi-Tenant Strategy](https://www.kolide.com/blog/kolide-s-30-line-rails-multi-tenant-strategy)
  - [citusdata/activerecord-multi-tenant: Rails/ActiveRecord support for distributed multi-tenant databases like Postgres+Citus](https://github.com/citusdata/activerecord-multi-tenant)
  - [rails-on-services/apartment: Database multi-tenancy for Rack (and Rails) applications](https://github.com/rails-on-services/apartment)
  - [ErwinM/acts_as_tenant: Easy multi-tenancy for Rails in a shared database setup.](https://github.com/ErwinM/acts_as_tenant)
- logging
  - SQL query logs
  - TaggedLogging and config.log_tenant_tag
  - suggest how to add to structured logs if people are doing that

## Active Record

### Configuration

Documentation outline:

- how to configure database.yml
  - for tenanting a primary database
  - for tenanting a non-primary database

- how to configure model classes and records
  - variations for primary or non-primary records
  - how to make a class that inherits from ActiveRecord::Base "subtenant" from a tenanted database
    - and note how we do it out of the box for Rails records

- Rails configuration
  - explain why we set some options
    - `active_record.use_schema_cache_dump = true`
    - `active_record.check_schema_cache_dump_version = false`
  - explain gem railtie config options
    - `connection_class`
    - `tenant_resolver`
    - `tenanted_rails_records`
    - `log_tenant_tag`
  - demonstrate how to configure an app with subdomain tenanting
    - app.config.hosts
    - example TenantSelector config
  - demonstrate how to configure an app with root path tenanting
    - app.config.hosts
    - example TenantSelector config

- migrations
  - create_tenant migrates the new database
  - but otherwise, creation of the connection pool for a tenant that has pending migrations will raise a PendingMigrationError
  - `db:migrate` will migrate all tenants

TODO:

- implement `AR::Tenanted::DatabaseConfigurations::RootConfig`
  - [x] create the specialized RootConfig for `tenanted: true` databases
  - [x] RootConfig disables database tasks initially
  - [x] RootConfig raises if a connection is attempted
  - [x] `#database_path_for(tenant_name)`
  - [x] `#tenants` returns all the tenants on disk (for iteration)
  - [x] raise an exception if tenant name contains a path separator
  - [ ] bucketed database paths

- implement `AR::Tenanted::DatabaseConfigurations::TenantConfig`
  - [x] make sure the logs include the tenant name (via `#new_connection`)

- Active Record class methods
  - [x] `.tenanted`
    - [x] mixin `Tenant`
    - [x] should error if self is not an abstract base class
    - [x] `Tenant.with_tenant` and `.current_tenant`
    - [x] `Tenant#tenant`
    - [x] use a sentinel value to avoid needing a protoshard
    - [x] `tenant_config_name` and `.tenanted?`
  - [x] `.tenanted_with`
    - [x] mixin `Subtenant`
    - [x] should error if self is not an abstract base class or if target is not tenanted abstract base class
    - [x] `.tenanted?`
    - [x] `#tenanted?`
  - [x] shared connection pools
  - [x] all the creation and schema migration complications (we have existing tests for this)
    - [x] read and write to the schema dump file
    - [x] write to the schema cache dump file
    - [x] make sure we read from the schema cache dump file when untenanted
    - [x] test production eager loading of the schema cache from dump files
  - [ ] UntenantedConnectionPool should peek at its stack and if it happened during schema cache load, output a friendly message to let people know what to do
  - [x] concrete class usage, e.g.: `User.current_tenant=` or `User.with_tenant { ... }`
  - [x] make it OK to call `with_tenant("foo") { with_tenant("foo") { ... } }`
  - [x] rename `while_tenanted` to `with_tenant`
  - [x] introduce `.with_each_tenant` which is sugar for `ApplicationRecord.tenants.each { ApplicationRecord.with_tenant(_1) { } }`

- tenant selector
  - [x] rebuild `AR::Tenanted::TenantSelector` to take a proc
    - [x] make sure it sets the tenant and prohibits shard swapping
    - [x] or explicitly untenanted, we allow shard swapping
    - [x] or else 404s if an unrecognized tenant

- old `Tenant` singleton methods that need to be migrated to the AR model
  - [x] `.current_tenant`
  - [x] `.current_tenant=`
  - [x] `.tenant_exist?`
  - [x] `.with_tenant`
  - [x] `.create_tenant`
    - [x] which should roll back gracefully if it fails for some reason
  - [x] `.destroy_tenant`

- autoloading and configuration hooks
  - [x] create a zeitwerk loader
  - [x] install a load hook

- database tasks
  - [x] make `db:migrate:tenant:all` iterate over all the tenants on disk
  - [x] make `db:migrate:tenant ARTENANT=asdf` run migrations on just that tenant
  - [x] make `db:migrate:tenant` run migrations on `development-tenant` in dev
  - [x] make `db:migrate` run `db:migrate:tenant` in dev
  - [x] make `db:prepare` run `db:migrate:tenant` in dev
  - [x] make a decision on what output tasks should emit, and whether we need a separate verbose setting
  - [ ] make the implicit migration opt-in
  - [ ] use the database name instead of "tenant", e.g. "db:migrate:primary"
  - [ ] fully implement all the relevant database tasks:
    - [~] `db:_dump`
      - forwards to "db:schema:dump"
    - [~] `db:_dump:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - forwards to "db:schema:dump:__name__"
    - [ ] `db:abort_if_pending_migrations`
      - uses DatabaseTasks.with_temporary_pool_for_each to iterate over db configs
    - [ ] `db:abort_if_pending_migrations:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(env: Rails.env, name: name)
    - [ ] `db:charset`
      - only seems to work against "primary"
      - error caused by nil returned from configs_for(env_name: env_name, name: db_name)
      - maybe we don't need to support this immediately?
    - [ ] `db:check_protected_environments`
      - loops over configs_for(env_name: environment)
      - we probably do not want or need to check all of the tenant databases. maybe check just the first tenant?
    - [ ] `db:collation`
      - only seems to work against "primary"
      - error caused by nil returned from configs_for(env_name: env_name, name: db_name)
      - maybe we don't need to support this immediately?
    - [ ] `db:create`
      - forwards to ActiveRecord::Tasks::DatabaseTasks.create_current
    - [ ] `db:create:all`
      - forwards to ActiveRecord::Tasks::DatabaseTasks.create_all
    - [ ] `db:create:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: name)
    - [ ] `db:drop`
      - forwards to "db:drop:_unsafe"
    - [ ] `db:drop:_unsafe`
      - forwards to ActiveRecord::Tasks::DatabaseTasks.drop_current
    - [ ] `db:drop:all`
      - forwards to ActiveRecord::Tasks::DatabaseTasks.drop_all
    - [ ] `db:drop:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: name)
    - [~] `db:encryption:init`
      - orthogonal to tenanting
    - [ ] `db:environment:set`
      - uses ActiveRecord::Tasks::DatabaseTasks.migration_connection_pool which raises NoTenantError if tenanted is primary
    - [~] `db:fixtures:identify`
      - orthogonal to tenanting
    - [ ] `db:fixtures:load`
      - I think the current behavior is the desired behavior: use ARTENANT (fallback to default tenant) as the target database
    - [ ] `db:forward` with support for STEP
      - **migration**
      - calls ActiveRecord::Tasks::DatabaseTasks.migration_connection_pool.migration_context.forward(step)
    - [~] `db:load_config`
      - orthogonal to tenanting
    - [ ] `db:migrate` with support for VERSION and SCOPE
      - **migration**
      - calls ActiveRecord::Tasks::DatabaseTasks.migrate_all
    - [ ] `db:migrate:down` with support for VERSION
      - **migration**
      - calls ActiveRecord::Tasks::DatabaseTasks.migration_connection_pool.migration_context.run(:down, target_version)
    - [ ] `db:migrate:down:__name__`
      - **migration**
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with DatabaseTasks.with_temporary_pool_for_each(env: Rails.env, name: name)
      - calls pool.migration_context.run(:down, ActiveRecord::Tasks::DatabaseTasks.target_version)
    - [ ] `db:migrate:__name__`
      - **migration**
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(env: Rails.env, name: name)
      - calls ActiveRecord::Tasks::DatabaseTasks.migrate
    - [ ] `db:migrate:redo` with support for STEP and VERSION
      - **migration**
      - forwards to either:
        - "db:migrate:down" + "db:migrate:up"
        - "db:rollback" + "db:migrate"
    - [ ] `db:migrate:redo:__name__`
      - **migration**
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - forwards to either:
        - "db:migrate:down:__name__" + "db:migrate:up:__name__"
        - "db:rollback:__name__" + "db:migrate:__name__"
    - [~] `db:migrate:reset`
      - invokes "db:drop", "db:create", "db:schema:dump", "db:migrate"
    - [ ] `db:migrate:status`
      - implemented with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each
      - calls ActiveRecord::Tasks::DatabaseTasks.migrate_status
    - [ ] `db:migrate:status:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(env: Rails.env, name: name)
      - calls ActiveRecord::Tasks::DatabaseTasks.migrate_status
    - [ ] `db:migrate:up` with support for VERSION
      - **migration**
      - calls ActiveRecord::Tasks::DatabaseTasks.migration_connection_pool.migration_context.run(:up, target_version)
    - [ ] `db:migrate:up:__name__`
      - **migration**
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with DatabaseTasks.with_temporary_pool_for_each(env: Rails.env, name: name)
      - calls pool.migration_context.run(:up, ActiveRecord::Tasks::DatabaseTasks.target_version)
    - [ ] `db:prepare`
      - forwards to ActiveRecord::Tasks::DatabaseTasks.prepare_all
    - [ ] `db:purge` (see Known Issues below)
      - forwards to ActiveRecord::Tasks::DatabaseTasks.purge_current
    - [ ] `db:purge:all` (see Known Issues below)
      - forwards to ActiveRecord::Tasks::DatabaseTasks.purge_all
    - [ ] `db:reset`
      - forwards to "db:drop", "db:create", "db:schema:dump", "db:migrate"
    - [ ] `db:reset:all`
      - forwards to "db:drop", "db:setup"
    - [ ] `db:reset:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - forwards to "db:drop:__name__", "db:setup:__name__"
    - [ ] `db:rollback` with support for STEP
      - **migration**
      - calls ActiveRecord::Tasks::DatabaseTasks.migration_connection_pool.migration_context.rollback(step)
    - [ ] `db:rollback:__name__`
      - **migration**
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(env: Rails.env, name: name)
      - calls pool.migration_context.rollback(step)
    - [ ] `db:schema:cache:clear`
      - iterates with ActiveRecord::Base.configurations.configs_for(env_name: ActiveRecord::Tasks::DatabaseTasks.env).each
      - we can probably skip implementing this since the gem needs the schema cache to operate, but whatever, maybe it's useful to force a re-dump
    - [ ] `db:schema:cache:dump`
      - iterates with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each
      - we can probably skip implementing this since the gem automatically dumps the schema cache for tenanted databases
    - [ ] `db:schema:dump`
      - forwards to ActiveRecord::Tasks::DatabaseTasks.dump_all
      - I think we can skip this? Check that the gem always dumps the schema.
    - [ ] `db:schema:dump:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - iterates with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(name: name)
      - calls ActiveRecord::Tasks::DatabaseTasks.dump_schema
      - I think we can skip this? Check that the gem always dumps the schema.
    - [ ] `db:schema:load`
      - forwards to ActiveRecord::Tasks::DatabaseTasks.load_schema_current(nil, ENV["SCHEMA"])
    - [ ] `db:schema:load:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(name: name)
      - calls ActiveRecord::Tasks::DatabaseTasks.load_schema
      - I think we can skip this since the schema is automatically applied at tenant creation time
    - [ ] `db:seed`
      - forwards to ActiveRecord::Tasks::DatabaseTasks.load_seed
      - I think the current behavior is the desired behavior: use ARTENANT (fallback to default tenant) as the target database
    - [ ] `db:seed:replant`
      - forwards to :load_config, :truncate_all, :seed
    - [ ] `db:setup`
      - forwards to "db:create", :environment, "db:schema:load", :seed
    - [ ] `db:setup:all`
      - forwards to "db:create", :environment, "db:schema:load", :seed
    - [ ] `db:setup:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - forwards to "db:create:__name__", :environment, "db:schema:load:__name__", "db:seed"
    - [ ] `db:test:load_schema`
      - implemented with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(env: "test")
      - calls ActiveRecord::Tasks::DatabaseTasks.load_schema
    - [ ] `db:test:load_schema:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(env: "test", name: name)
      - calls ActiveRecord::Tasks::DatabaseTasks.load_schema
    - [ ] `db:test:prepare`
      - forwards to "db:test:load_schema"
    - [ ] `db:test:prepare:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - forwards to "db:test:load_schema:__name__"
    - [ ] `db:test:purge`
      - implemented with ActiveRecord::Base.configurations.configs_for(env_name: "test")
      - calls ActiveRecord::Tasks::DatabaseTasks.purge(db_config)
    - [ ] `db:test:purge:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(env: "test", name: name)
      - calls ActiveRecord::Tasks::DatabaseTasks.purge(db_config)
    - [ ] `db:truncate_all`
      - forwards to ActiveRecord::Tasks::DatabaseTasks.truncate_all
    - [ ] `db:version`
      - implemented with ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(env: Rails.env)
    - [ ] `db:version:__name__`
      - created by ActiveRecord::Tasks::DatabaseTasks.for_each(databases)
      - implemented with ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: name)

- installation
  - [ ] install a variation on the default database.yml with primary tenanted and non-primary "global" untenanted
  - [ ] initializer: commented lines with default values and some docstrings
  - [ ] mailer URL defaults (setting `%{tenant}` for subdomain tenanting)

- [ ] think about race conditions
  - maybe use a file lock to figure it out?
  - [x] create
    - if two threads are racing
    - in a parallel test suite, `with_each_tenant` returning a not-yet-ready tenant from another process
  - [x] migrations
    - not sure this matters, since they're done in a transaction
  - [x] schema load
    - if first thread loads the schema and inserts data, can the second thread accidentally drop/load causing data loss?
  - [ ] destroy
    - should delete the wal and shm files, too
    - we need to be close existing connections / statements / transactions(?)
      - relevant adapter code https://github.com/rails/rails/blob/91d456366638ac6c3f6dec38670c8ada5e7c69b1/activerecord/lib/active_record/tasks/sqlite_database_tasks.rb#L23-L26
      - relevant issue/pull-request https://github.com/rails/rails/pull/53893

- pruning connections and connection pools
  - [ ] look into whether the proposed Reaper changes will allow us to set appropriate connection min/max/timeouts
    - and if not, figure out how to prune unused/timed-out connections
  - [ ] we should also look into how to cap the number of connection pools, and prune them

- integration test coverage
  - [x] connection_class
    - [x] fixture tenant
    - [x] fixture tenant in parallel suite
    - [x] clean up non-default tenants
    - [x] integration test session host
    - [x] integration test session verbs
  - [x] fixtures are loaded
  - [x] tenanted_rails_records

- additional configuration
  - [x] default_tenant (local only)


### Tenanting in your application

Documentation outline:

- introduce the basics
  - explain `.tenanted` and the `ActiveRecord::Tenanted::Tenant` module
  - explain `.subtenant_of` and the `ActiveRecord::Tenanted::Subtenant` module
  - explain `.with_tenant`, `.with_each_tenant`, `.current_tenant=`, and `current_tenant`
  - demonstrate how to create a tenant, destroy a tenant, etc.
- troubleshooting: what errors you might see in your app and how to deal with it
  - specifically when running untenanted


### Testing

Documentation outline:

- explain the concept of a default tenant
  - and that database connection is wrapped in a transaction
- explain creating a new tenant
  - and how that database is NOT wrapped in a transaction during the test,
  - but those non-fixture databases will be cleaned up at the start of the test suite
- explain `without_tenant`
- example of:
  - unit test with fixtures
  - integration test
  - sytem test

TODO:

- testing
  - [x] a `without_tenant` test helper
  - [x] set up test helper to default to a tenanted named "test-tenant"
  - [x] set up test helpers to deal with parallelized tests, too (e.g. "test-tenant-19")
  - [x] set up integration tests to do the right things ...
    - [x] set the domain name in integration tests
    - [x] wrap the HTTP verbs with `without_tenant`
    - [x] set the domain name in system tests
  - [x] allow the creation of tenants within transactional tests


## Caching

Documentation outline:

- explain why we need to be careful
- explain how active record objects' cache keys have tenanting built in
- explain why we're not worried about collection caching and partial caching (?)
- explain why we're not worried about russian doll caching
- explain why calling Rails.cache directly requires care that it's either explicitly tenanted or global
- explain why we're not worried about sql query caching (it belongs to the connection pool)


TODO:

- [x] make basic fragment caching work
- [x] investigate: is collection caching going to be tenanted properly
- [x] investigate: make sure the QueryCache executor is clearing query caches for tenanted pool
- [x] do we need to do some exploration on how to make sure all caching is tenanted?
  - I'm making the call not to pursue this. Rails.cache is a primitive. Just document it.

## Action View Fragment Caching

Documentation outline:

- explain how it works (cache keys)

TODO:

- [x] extend `#cache_key` on Base
- [x] extend `#cache_key` on Subtenant


### Solid Cache

Documentation outline:

- describe one-big-cache and cache-in-the-tenanted-database strategies
  - note that cache-in-the-tenanted-database means there is no global cache
  - note that cache-in-the-tenanted-database is not easily purgeable (today)
  - and so we recommend (?) one big cache in a dedicated database
- how to configure Solid Cache for one-big-cache
- how to configure Solid Cache for tenanted-cache

TODO:

- upstream
  - [ ] feature: make shard swap prohibition database-specific
    - which would work around Solid Cache config wonkiness caused by https://github.com/rails/solid_cache/pull/219


## Action Cable

Documentation outline:

- explain why we need to be careful
- how to tenant a channel
  - make sure to call `super` if you override `#connect`
- how the global id also contains the tenant
- do we need to document each adapter?
  - async
  - test
  - solid_cable
  - redis?

TODO:

- [x] extend the base connection to support tenanting with a `tenanted_connection` method
- [x] reconsider the current API using `tenanted_connection` if we can figure out how to reliably wrap `#connect`
  - did this! prefer to force the app to call super() from `#connect`, it's simpler
- [ ] test disconnection
  - `ActionCable.server.remote_connections.where(current_tenant: "foo", current_user: User.find(1)).disconnect`
  - can we make this easier to use by implying the current tenant?
- [ ] add tenant to the action_cable logger tags
- [ ] add integration testing around executing a command (similar to Job testing)


### Turbo Rails

Documentation outline:

- explain why we need to be careful
- explain how it works (global IDs)

TODO:

- [x] extend `to_global_id` and friends for Base
- [x] extend `to_global_id` and friends for Subtenant
- [x] some testing around global id would be good here
- [x] system test of a broadcast update


## Active Job

Documentation outline:

- explain why we need to be careful
- explain belt-and-suspenders of
  - ActiveJob including the current tenant,
  - and any passed record being including the tenant in global_id


TODO:

- [x] extend `ActiveJob` to set the tenant in `perform_now`
- [x] extend `to_global_id` and friends for Base
- [x] extend `to_global_id` and friends for Subtenant
- [x] create a tenanted GlobalID locator
- [x] inject the tenanted GlobalID locator as the default app locator
- [x] make sure the test helper `perform_enqueued_jobs` wraps everything in a `without_tenant` block


## Active Storage

Documentation outline:

- explain why we need to be careful
- explain how it works
  - if `connection_class` is set, then Active Storage will insert the tenant into the blob key
    - and the disk service will include the tenant in the path on disk in the root location, like: 'foobar/ab/cd/abcd12345678abcd'
- Disk Service can also have a tenanted root path, but it's optional

TODO:

- [x] extend Disk Service to change the path on disk
- [x] extend Blob to have tenanted keys


## ActionMailer

Documentation outline:

- explain how to configure the action mailer default host if needed, with a "%{tenant}" format specifier.


TODO:

- [x] Interpolate the tenant into a host set in config.action_mailer.default_url_options
- [ ] Do we need to do something similar for the asset host?
  - I'm going to wait until someone needs it, because it's not trivial to hijack.
- [ ] Do we need to do something similar for explicit host parameters to url helpers?
  - I don't think so.
  - I'm going to wait until someone needs it, because it's not trivial to hijack.


## ActionMailbox

TODO:

- [ ] I need a use case here around mail routing before I tackle it


## Console

Documentation outline:

- explain the concept of a "default tenant"
- explain usage of the `ARTENANT` environment variable to control startup
