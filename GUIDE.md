# Active Record Tenanting

This file will eventually become a complete "Rails Guide"-style document explaining Active Record tenanting with this gem.

In the meantime, it is a work-in-progress containing:

- skeleton outline for documentation
- functional roadmap represented as to-do checklists


## Introduction

Documentation:
- this gem primarily extends Active Record,
  - essentially creating a new Connection Pool for each tenant,
  - and extending horizontal shard swapping to support these pools.
  - also provides test helpers to make it easy to handle tenanting in your test suite
- but also touches many other parts of Rails
  - integrations for Middleware, Action View Caching, Active Job, Action Cable, Active Storage, Action Mailbox, and Action Text
  - support and documentation for Solid Cache, Solid Queue, Solid Cable, and Turbo Rails
- a Tenant is just a string that is used for:
  - the sqlite database filename
  - the subdomain (or path element)
  - fragment cache disambiguation
  - global id disambiguation
- talk a bit about busted assumptions about shared state
  - database ids are no longer unique
  - global ids are no longer global
  - cache is no longer global
- and what we do in this gem to help manage "shard" state


## Active Record

### Configuration

Documentation:
- how to configure database.yml for tenanting a primary database
- how to configure database.yml for tenanting a non-primary database
- how to make a class that inherits from ActiveRecord::Base "sublet" from a tenanted database
  - and note how we do it out of the box for Rails records
- how to run database tasks and what's changed
- demonstrate how to configure an app for subdomain tenants
  - app.config.hosts
  - example TenantSelector proc

TODO:
- implement `AR::Tenanted::DatabaseConfigurations::RootConfig` (name?)
  - [ ] `#database_path_for(tenant_name)`
  - [ ] `#tenants` returns all the tenants on disk (for iteration)

- implement `AR::Tenanted::DatabaseConfigurations::TenantConfig` (name?)
  - [ ] make sure the logs include the tenant name (via `#new_connection`)

- Active Record class methods
  - [ ] `.tenanted`
    - extends with `Base`
    - sets `Tenant.base_class=`
    - must only be set ONCE in the application
  - [ ] `.tenanted_with`
    - extends with `Sublet`
    - should error if self is not an abstract base class or if target is not tenanted abstract base class
    - is the name right? should we have to provide the name of the tenanted class?
  - [ ] `.tenanted?`
  - [ ] `.tenanted_class` nil or the abstract base class
  - [ ] all the creation and schema migration complications (we have existing tests for this)
    - think about race conditions here, maybe use a file lock to figure it out
      - running migrations (they are done in a transaction, but the second thread's migration may fail resulting in a 500?)
      - loading schemas (if the first thread loads the schema and inserts data, can the second thread accidentally drop/load causing data loss?)
  - [ ] feature to turn off automatic creation/migration
    - make sure we pay attention to Rails.config.active_record.migration_error when we turn off auto-migrating

- database tasks
  - [ ] make `db:migrate:tenants` iterate over all the tenants on disk
  - [ ] make `db:migrate AR_TENANT=asdf` run migrations on just that tenant
  - [ ] do that for all (?) the database tasks like `db:create`, `db:prepare`, `db:seeds`, etc.

- tenant selector
  - [ ] rebuild `AR::Tenanted::TenantSelector` to take a proc
    - make sure it sets the tenant and prohibits shard swapping
    - or explicitly untenanted, we allow shard swapping
    - or else 404s if an unrecognized tenant

- `Tenant`
  - `.current`
  - `.current=`
  - `.while_tenanted`
  - `.exist?`
  - `.all`
  - `.create`
    - think about race conditions here, maybe use a file lock to figure it out
  - `.destroy`
    - think about race conditions here, maybe use a file lock to figure it out
    - should delete the wal and shm files, too
    - we need to be close existing connections / statements / transactions(?)
      - relevant adapter code https://github.com/rails/rails/blob/91d456366638ac6c3f6dec38670c8ada5e7c69b1/activerecord/lib/active_record/tasks/sqlite_database_tasks.rb#L23-L26
      - relevant issue/pull-request https://github.com/rails/rails/pull/53893

- installation
  - [ ] install a variation on the default database.yml with primary tenanted and non-primary "global" untenanted
  - initializer
    - [ ] install `TenantSelector` and configure it with a proc
    - [ ] commented line like `Tenant = ActiveRecord::Tenanted::Tenant`

- pruning connections and connection pools
  - [ ] look into whether the proposed Reaper changes will allow us to set appropriate connection min/max/timeouts
    - and if not, figure out how to prune unused/timed-out connections
  - [ ] we should also look into how to cap the number of connection pools, and prune them


### Tenanting in your application

Documentation:
- introduce the `Tenant` module
  - demonstrate how to create a tenant, destroy a tenant, etc.
- troubleshooting: what errors you might see in your app and how to deal with it
  - specifically when running untenanted


### Testing

Documentation:
- explain the concept of a default tenant
- explain `while_untenanted`


TODO:
- testing
  - [ ] set up test helper to default to a tenanted named "test-tenant"
  - [ ] set up test helpers to deal with parallelized tests, too (e.g. "test-tenant-19")
  - [ ] allow the creation of tenants within transactional tests if we can?
    - either by cleaning up properly (hard)
    - or by providing a test helper that does `ensure ... Tenant.destroy`
  - [ ] a `while_untenanted` test helper


## Caching

Documentation:
- explain why we need to be careful

TODO:
- [ ] need to do some exploration on how to make sure all caching is tenanted
  - and then we can have belt-and-suspenders like we do with ActiveJob


## Action View Fragment Caching

TODO:
- [ ] extend `#cache_key` on Base
- [ ] extend `#cache_key` on Sublet


### Solid Cache

Documentation:
- describe one-big-cache and cache-in-the-tenanted-database strategies
- how to configure Solid Cache for one-big-cache
- how to configure Solid Cache for tenanted-cache

TODO:
- upstream
  - [ ] feature: make shard swap prohibition database-specific
    - which would work around Solid Cache config wonkiness caused by https://github.com/rails/solid_cache/pull/219


## Active Job

Documentation:
- explain why we need to be careful
- explain belt-and-suspenders of
  - ActiveJob including the current tenant,
  - and any passed record being including the tenant in global_id


TODO:
- [ ] extend `to_global_id` and friends for Base
- [ ] extend `to_global_id` and friends for Sublet
- [ ] extend `ActiveJob` to set the tenant in `perform_now`


## Active Storage

Documentation:
- explain why we need to be careful
- how to configure Disk Service so that each client is in a tenanted subdirectory
- how to configure S3 so that each client is in a tenanted bucket

TODO:
- [ ] still have to do some exploration here to figure out how best to tackle it
  - and then we can have belt-and-suspenders like we do with ActiveJob (hopefully)


## Action Cable

Documentation:
- explain why we need to be careful
- how to make a channel "tenant safe"
 - identified_by
- how the global id contains tenant also
- do we need to document each adapter?
  - async
  - test
  - solid_cable
  - redis?

TODO:
- [ ] explore if there's something we can/should do in Channel base case to automatically tenant
  - and then we can have belt-and-suspenders like we do with ActiveJob
- [ ] understand action_cable_meta_tag
- [ ] config.action_cable.log_tags set up with tenant?


### Turbo Rails

Documentation:
- explain why we need to be careful

TODO:
- [ ] some testing around global id would be good here


## ActionMailbox

TODO:
- [ ] I need a use case here around mail routing before I tackle it
