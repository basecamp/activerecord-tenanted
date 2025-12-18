# Active Record Tenanting

> [!NOTE]
> This file will eventually become a complete "Rails Guide"-style document explaining Active Record tenanting with this gem.
>
> In the meantime, it is a work-in-progress containing:
>
> - skeleton outline for documentation
> - functional roadmap represented as to-do checklists

## Contents

<!-- regenerate TOC with `rake toc` -->

<!-- toc -->

- [1. What is Active Record Tenanted?](#1-what-is-active-record-tenanted)
  * [1.1 Guiding design principles](#11-guiding-design-principles)
  * [1.2 High-level implementation](#12-high-level-implementation)
  * [1.3 Concepts](#13-concepts)
  * [1.4 Prior Art](#14-prior-art)
  * [1.5 Shared state (WIP)](#15-shared-state-wip)
- [2. Application Configuration](#2-application-configuration)
  * [2.1 The Default Configuration](#21-the-default-configuration)
  * [2.2 Configuring the Database](#22-configuring-the-database)
  * [2.3 Configuring `max_connection_pools`](#23-configuring-max_connection_pools)
  * [2.4 Configuring the Connection Class](#24-configuring-the-connection-class)
  * [2.5 Configuring the Tenant Resolver](#25-configuring-the-tenant-resolver)
  * [2.6 Other Tenant Configuration](#26-other-tenant-configuration)
  * [2.7 Related Rails Configurations](#27-related-rails-configurations)
- [Documentation "work in progress"](#documentation-work-in-progress)
  * [Active Record API](#active-record-api)
  * [Caching](#caching)
  * [Action View Fragment Caching](#action-view-fragment-caching)
  * [Action Cable](#action-cable)
  * [Active Job](#active-job)
  * [Active Storage](#active-storage)
  * [ActionMailer](#actionmailer)
  * [ActionMailbox](#actionmailbox)
  * [Console](#console)
  * [Metrics](#metrics)

<!-- tocstop -->

## 1. What is Active Record Tenanted?

> [!TIP]
> If you're not familiar with how Rails's built-in horizontal sharding works, it may be worth reading the Rails Guide on [Multiple Databases with Active Record](https://guides.rubyonrails.org/active_record_multiple_databases.html#setting-up-your-application) before proceeding.

Active Record Tenanted extends the Rails framework to enable an application to have many tenant-specific databases. It provides data isolation by logically separating each tenant's data, by providing safety mechanisms to help ensure safe usage of Active Record, and by modifying the behavior of many parts of Rails such as fragment caching, Active Job, Action Cable, Active Storage, Global ID, and database tasks. By providing integrated framework support for tenanting, Active Record Tenanted ensures that developers can write the majority of their code as if they were in a single-tenant application without putting tenant privacy and data security at risk.

### 1.1 Guiding design principles

The design of Active Record Tenanted is rooted in a few guiding principles in order to safely allow multiple tenants to share a Rails application instance:

- Data "at rest" is persisted in a separate store for each tenant's data, isolated either physically or logically from other tenants.
- Data "in transit" is only sent to users with authenticated access to the tenant instance.
- All tenant-related code execution must happen within a well-defined isolated tenant context with controls around data access and transmission.

Another guiding principle, though, is:

- Developing a multi-tenant Rails app should be as easy as developing a single-tenant app.

The goal is that developers will rarely need to think about managing tenant isolation.


### 1.2 High-level implementation

Active Record Tenanted extends Active Record to dynamically create a Connection Pool for a tenant on demand. It does this in a thread-safe way by relying heavily on Rails' horizontal sharding features.

It extends Rails' testing frameworks so that tests don't need to explicitly set up a tenant or otherwise be aware of tenanting (unless tenanting behavior is explicitly being tested).

It also provides integrations with Action Dispatch's Rack middleware, Action View Caching, Active Job, Action Cable, Turbo frames and streams, Active Storage, Action Mailbox, and Action Text to ensure that code is always aware of its "tenant context".


### 1.3 Concepts

A "tenant ID" is simply a string (or an integer) that uniquely identifies a subset of data. For example, this may be a subdomain, or a user-chosen name, or a foreign key into a customer database. It's used as part of the name of the database (e.g., the file path to a SQLite file on disk, or the name of a MySQL database) and so there are constraints on the tenant ID.

A "tenant context" refers to the "current tenant" during code execution. For code running in a Rails server, the tenant context is set automatically by Active Record Tenanted's middleware; but in other situations, such as in the Rails console, the context can be set by calling `.with_tenant`:

``` ruby
# When no tenant context is set, "current tenant" is nil:
ApplicationRecord.current_tenant   # => nil

ApplicationRecord.with_tenant("tenant-one") do
  # Inside this block, code runs within "tenant-one"'s context
  ApplicationRecord.current_tenant # => "tenant-one"
  User.current_tenant              # => "tenant-one"

  # ... and uses a connection to "tenant-one"'s database.
  User.connection_pool.db_config.database
  # => storage/tenants/development/tenant-one/db/main.sqlite3

  # ... so that SQL queries are executed on "tenant-one"'s database
  user = User.find(1)
  # User Load [tenant=tenant-one] (1.3ms)  SELECT "users".* FROM "users" WHERE "users"."id" = ? LIMIT ?  [["id", 1], ["LIMIT", 1]]
end
```

Note that a "tenant attribute" is set on all model instances, to reflect the tenant to which it belongs:

``` ruby
ApplicationRecord.with_tenant("tenant-one") do
  user = User.find(1)
  user.tenant                      # => "tenant-one"
end
```

Access to the database without a tenant context raises an exception:

``` ruby
ApplicationRecord.current_tenant   # => nil
User.find(1)                       # raises ActiveRecord::Tenanted::NoTenantError
```


### 1.4 Prior Art

Released in 2008, the [`acts_as_tenant`](https://github.com/ErwinM/acts_as_tenant) gem allows an application to isolate tenant data that is commingled in a single database. It relies on Active Record associations and applies tenant constraints using scopes, and offers middleware tenant resolution. It provides very limited integration with the rest of the Rails framework.

In 2009, Guy Naor spoke at Acts As conference on [Writing Multi-tenant Applications in Rails 2](https://www.youtube.com/watch?v=0QstBE0Bfj8), which provides details on many aspects of multi-tenancy.

Released in 2011, the [`apartment`](https://github.com/rails-on-services/apartment) gem extends Active Record to make dynamic connections to tenant-specific databases. It provides more substantial data isolation than However, it relies on a primitive reconnection mechanism that pre-dates Rails 6.1's thread-safe sharding model. It also provides only limited integration with the rest of the Rails framework.

In December 2020, [Rails 6.1 was released](https://guides.rubyonrails.org/6_1_release_notes.html) with support for horizontal sharding and multi-database. This functionality provided new thread-safe capabilities for connection switching in Rails.

In early 2025, Julik Tarkhanov published a [tenanting implementation named "Shardine"](https://blog.julik.nl/2025/04/a-can-of-shardines) that uses the Rails sharding API. However, it also provided very limited integration with the rest of the Rails framework.


### 1.5 Shared state (WIP)

- when we talk about "integration with the rest of rails" we're talking about Rails' assumptions about shared state
- some of these assumptions are now busted
  - database ids are no longer unique
  - global ids are no longer global
  - cache is no longer global
  - cable channels are no longer global
  - jobs are no longer global


## 2. Application Configuration

This gem offers an "omakase" configuration that specifies:

1. All models inheriting from `ApplicationRecord` will be tenanted.
2. The subdomain of the request will be used to determine the tenant context.

These defaults can be overridden using the configuration options:

- `config.active_record_tenanted.connection_class`
- `config.active_record_tenanted.tenant_resolver`

This gem also introduces behavior changes into Rails to accommodate tenanting. All of these behavior changes can be disabled by setting `config.active_record_tenanted.connection_class` to `nil`.


### 2.1 The Default Configuration

To install this gem into an application with the defaults, first add the gem:

``` diff
--- a/Gemfile
+++ b/Gemfile
@@ -3,6 +3,7 @@ git_source(:bc) { |repo| "https://github.com/basecamp/#{repo}" }
 ruby file: ".ruby-version"

 gem "rails", github: "rails/rails", branch: "main"
+gem "activerecord-tenanted"

 # Assets & front end
 gem "importmap-rails"
```

Extend your ApplicationRecord models:

``` diff
--- a/app/models/application_record.rb
+++ b/app/models/application_record.rb
@@ -1,3 +1,4 @@
 class ApplicationRecord < ActiveRecord::Base
   primary_abstract_class
+  tenanted
 end
```

Extend your database configuration:

``` diff
--- a/config/database.yml
+++ b/config/database.yml
@@ -12,7 +12,8 @@ default: &default
 production:
   primary:
     <<: *default
-    database: storage/production.sqlite3
+    database: storage/production/%{tenant}/main.sqlite3
+    tenanted: true
   cable:
     <<: *default
     database: storage/production_cable.sqlite3
```

In this configuration, `ApplicationRecord` classes and instances will be extended with tenant behavior:

``` ruby
class User < ApplicationRecord ; end

ApplicationRecord.current_tenant   # => nil

ApplicationRecord.with_tenant("tenant-one") do
  ApplicationRecord.current_tenant # => "tenant-one"
  User.current_tenant              # => "tenant-one"
  user = User.find(1)
  user.tenant                      # => "tenant-one"
end
```

And in this configuration, the `TenantSelector` middleware will automatically set the tenant context base on the request subdomain. A request to `tenant-one.example.com` will resolve to tenant ID `"tenant-one"`, and all code that runs in the application as part of request handling will automatically be in this context:

``` ruby
class BooksController < ApplicationController
  def index
    Book.current_tenant # => "tenant-one" for a request to "tenant-one.example.com"
  end
end
```


### 2.2 Configuring the Database

By default, Active Record Tenanted will connect `ApplicationRecord` to tenanted shards based on the `primary` database configuration.

This can be overridden with an argument to `tenanted` with the name of the database. For example, if the `database.yml` file contained this configuration:

``` yaml
production:
  primary:
    adapter: mysql2
    database: primary_db
  secondary:
    adapter: sqlite3
    database: "storage/tenants/%{tenant}/main.sqlite3"
    tenanted: true
```

then the models could be configured as follows:

``` ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  tenanted "secondary"
end
```

This approach also works for primary database that aren't named "primary":

``` yaml
production:
  tenant_db:
    adapter: sqlite3
    database: "storage/tenants/%{tenant}/main.sqlite3"
    tenanted: true
  secondary:
    adapter: mysql2
    database: primary_db
```

``` ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  tenanted "tenant_db"
end
```

#### 2.2.1 PostgreSQL Multi-Tenancy Strategies

PostgreSQL supports two isolation strategies, configurable via the `postgresql_strategy` option in `database.yml`.

##### Schema-Based Multi-Tenancy (Default)

Uses PostgreSQL schemas within a single database. This is the default strategy and is recommended for most use cases.

**Configuration:**

``` yaml
production:
  primary:
    adapter: postgresql
    tenanted: true
    # postgresql_strategy: schema  # Optional - this is the default
    database: myapp_%{tenant}
    host: localhost
```

In this configuration:
- A single PostgreSQL database named `myapp_tenanted` is created
- Each tenant gets its own schema: `myapp_foo`, `myapp_bar`, etc.
- The `schema_search_path` is set automatically to isolate tenants
- All tables and data are stored within the tenant-specific schema

**Advantages:**
- **Resource Efficient**: Single database process serves all tenants
- **Lower Memory Usage**: Shared buffer cache across tenants
- **Simpler Backup**: One database to backup/restore
- **Better for Scale**: Supports thousands of tenants efficiently
- **PostgreSQL Best Practice**: Aligns with PostgreSQL's schema design

**Considerations:**
- Connection limits are shared across all tenants
- Schema-level isolation (not database-level)
- All tenants must use the same PostgreSQL version/settings

##### Database-Based Multi-Tenancy

Creates separate PostgreSQL databases for each tenant. Similar to how MySQL and SQLite work in this gem.

**Configuration:**

``` yaml
production:
  primary:
    adapter: postgresql
    tenanted: true
    postgresql_strategy: database  # Explicitly use database-per-tenant
    database: myapp_%{tenant}
    host: localhost
```

In this configuration:
- Each tenant gets its own PostgreSQL database: `myapp_foo`, `myapp_bar`, etc.
- Each database has independent schemas, users, and settings
- Complete isolation between tenants at the database level

**Advantages:**
- **Stronger Isolation**: Complete database-level separation
- **Independent Configuration**: Each tenant can have different settings
- **Easier Data Export**: Simple to dump/restore individual tenants
- **Familiar Pattern**: Consistent with MySQL/SQLite behavior

**Considerations:**
- Higher resource usage (more database processes)
- Higher memory usage (separate buffer cache per database)
- More complex backup/restore operations
- PostgreSQL may have limits on number of databases
- Not recommended for hundreds of tenants

##### Performance Comparison

| Metric | Schema Strategy | Database Strategy |
|--------|----------------|-------------------|
| **Connection Overhead** | Low (single DB) | Medium (multiple DBs) |
| **Memory Usage** | Low (shared cache) | High (cache per DB) |
| **Query Performance** | Excellent | Excellent |
| **Tenant Isolation** | Schema-level | Database-level |
| **Backup/Restore** | Simple (one DB) | Complex (many DBs) |
| **Tenant Limit** | Thousands | Hundreds |
| **Resource Efficiency** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Data Isolation** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

##### Choosing a Strategy

**Use Schema Strategy (default) when:**
- You have many tenants (dozens to thousands)
- Resource efficiency is important
- You're following PostgreSQL best practices
- Tenants share the same configuration needs
- You want simpler operations (backup, monitoring, etc.)

**Use Database Strategy when:**
- You have few tenants (less than 100)
- You need database-level isolation for compliance
- Each tenant needs different database settings
- You need to easily export individual tenant databases
- You want consistency with MySQL/SQLite behavior

##### Migration Between Strategies

To change strategies, you'll need to:

1. Export data from existing tenants
2. Update `database.yml` with new `postgresql_strategy`
3. Create new tenant databases/schemas
4. Import data into new structure

**Note:** There is no automated migration tool. Plan strategy choice carefully before production deployment.

### 2.3 Configuring `max_connection_pools`

By default, Active Record Tenanted will cap the number of tenanted connection pools to 50. Setting a limit on the number of "live" connection pools at any one time provides control over the number of file descriptors used for database connections. For SQLite databases, it's also an important control on the amount of memory used.

The cap on the number of connection pools is configurable in `config/database.yml` by setting a `max_connection_pools` parameter:

``` yaml
production:
  primary:
    adapter: sqlite3
    database: "storage/tenants/%{tenant}/main.sqlite3"
    tenanted: true
    max_connection_pools: 20
```

Active Record Tenanted will reap the least-recently-used connection pools when this limit is surpassed. Developers are encouraged to tune this parameter with care, since setting it too low may lead to increased request latency due to frequently re-establishing database connections, while setting it too high may consume precious file descriptors and memory resources.


### 2.4 Configuring the Connection Class

By default, Active Record Tenanted assumes that `ApplicationRecord` is the tenanted abstract base class:

``` ruby
# Set this in an initializer if you're tenanting a connection class other than
# ApplicationRecord. This value indicates the connection class that this gem uses to integrate
# with a broad set of Rails subsystems, including:
#
# - Active Job
# - Active Storage
# - Action Cable
# - Action Dispatch middleware (Tenant Selector)
# - Test frameworks and fixtures
#
# Defaults to "ApplicationRecord", but this can be set to `nil` to turn off the integrations
# entirely.
config.active_record_tenanted.connection_class = "ApplicationRecord"
```

Applications may override this to tenant a different abstract connection class. For example, to connect some models to the "secondary" database in this configuration:

``` yaml
production:
  primary:
    adapter: mysql2
    database: primary_db
  secondary:
    adapter: sqlite3
    database: "storage/tenants/%{tenant}/main.sqlite3"
    tenanted: true
```

A new abstract connection class could be defined and configured as follows:

``` ruby
# define the abstract connection class
class TenantedApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  tenanted "secondary"
end

# concrete tenanted models inherit from TenantedApplicationRecord
class User < TenantedApplicationRecord ; end

# make sure the Rails integrations use the desired connection class
Rails.application.configure do
  config.active_record_tenanted.connection_class = "TenantedApplicationRecord"
end
```


### 2.5 Configuring the Tenant Resolver

Active Record Tenanted's default tenant resolver uses the request's subdomain:

``` ruby
# Set this to a lambda that takes a request object and returns the tenant name. It's used by:
#
# - Action Dispatch middleware (Tenant Selector)
# - Action Cable connections
#
# Defaults to the request subdomain.
config.active_record_tenanted.tenant_resolver = ->(request) { request.subdomain }
```

Applications may override this with their own lambda that wraps more complex tenant resolution logic. For example:

``` ruby
module TenantSlug
  def self.resolve(request)
    # complex behavior to pull the tenant out of the request path
  end
end

# configure Active Record Tenanted in an initializer
Rails.application.configure do
  config.active_record_tenanted.tenant_resolver = ->(request) { TenantSlug.resolve(request) }
end
```

### 2.6 Other Tenant Configuration

TODO:

- talk about connection_class and disabling integrations
- `tenanted_rails_records`
- `log_tenant_tag`
- `default_tenant`


### 2.7 Related Rails Configurations

TODO:

- explain why we set some options
  - `active_record.use_schema_cache_dump = true`
  - `active_record.check_schema_cache_dump_version = false`


## Documentation "work in progress"

### Active Record API

Documentation outline:

- setting the tenant
  - `.with_tenant` and `.current_tenant=`
    - and the callbacks for each, `:with_tenant` and `:set_current_tenant`
  - validation
    - invalid characters in a tenant name (which is database-dependent)
    - and how the application may want to do additional validation (e.g. ICANN subdomain restrictions)
  - `#tenant` is a readonly attribute on all tenanted model instances
  - `.current_tenant` returns the execution context for the model connection class
- and what we do in this gem to help manage that "current tenant" state
- logging
  - SQL query logs - see rdocs in connection_adapter.rb
    - set `config.active_record.query_log_tags = [ :tenant ]`
    - must also have `config.active_record.query_log_tags_enabled = true`
  - TaggedLogging and config.log_tenant_tag
  - suggest how to add to structured logs if people are doing that
- migrations
  - create_tenant migrates the new database
  - but otherwise, creation of the connection pool for a tenant that has pending migrations will raise a PendingMigrationError
- database rake tasks (where DBNAME is the name of the database configuration, e.g. `primary`)
  - db:migrate:DBNAME
    - dependency of db:migrate and db:prepare
    - it operates on all tenants by default
    - if there are no tenants it will create a database for the default tenant
    - the ARTENANT env var can be specified to run against a specific tenant
  - db:drop:DBNAME replaces db:drop:tenant
    - dependency of db:drop
    - it operates on all tenants by default
    - the ARTENANT env var can be specified to run against a specific tenant
  - db:reset:DBNAME replaces db:reset:tenant
    - dependency of db:reset
    - it operates on all tenants by default
    - the ARTENANT env var can be specified to run against a specific tenant

TODO:

- implement `AR::Tenanted::DatabaseConfigurations::BaseConfig`
  - [x] create the specialized BaseConfig for `tenanted: true` databases
  - [x] BaseConfig disables database tasks initially
  - [x] BaseConfig raises if a connection is attempted
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
  - [x] make `db:migrate:__dbname__` migrate all the existing tenants
  - [x] make `db:migrate:__dbname__ ARTENANT=asdf` run migrations on just that tenant
  - [x] make `db:drop:__dbname__` drop all the existing tenants
  - [x] make `db:drop:__dbname__ ARTENANT=asdf` drop just that tenant
  - [x] make `db:migrate` run `db:migrate:__dbname__`
  - [x] make `db:prepare` run `db:migrate:__dbname__`
  - [x] make `db:drop` run `db:drop:__dbname__`
  - [x] make a decision on what output tasks should emit, and whether we need a separate verbose setting
  - [x] use the database name instead of "tenant", e.g. "db:migrate:primary"
  - [ ] make the implicit migration opt-in
  - [ ] fully implement all the relevant database tasks - see https://github.com/basecamp/activerecord-tenanted/issues/222

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
    - [x] should delete the wal and shm files, too
      - relevant adapter code https://github.com/rails/rails/blob/91d456366638ac6c3f6dec38670c8ada5e7c69b1/activerecord/lib/active_record/tasks/sqlite_database_tasks.rb#L23-L26
    - [ ] we need to be close existing connections / statements / transactions(?)
      - relevant issue/pull-request https://github.com/rails/rails/pull/53893

- pruning connections and connection pools
  - [x] look into how to cap the number of connection pools, and prune them

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


#### Tenanting in your application

Documentation outline:

- introduce the basics
  - explain `.tenanted` and the `ActiveRecord::Tenanted::Tenant` module
  - explain `.subtenant_of` and the `ActiveRecord::Tenanted::Subtenant` module
  - explain `.with_tenant`, `.with_each_tenant`, `.current_tenant=`, and `current_tenant`
  - demonstrate how to create a tenant, destroy a tenant, etc.
- troubleshooting: what errors you might see in your app and how to deal with it
  - specifically when running untenanted


#### Testing

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


### Caching

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

### Action View Fragment Caching

Documentation outline:

- explain how it works (cache keys)

TODO:

- [x] extend `#cache_key` on Base
- [x] extend `#cache_key` on Subtenant


#### Solid Cache

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


### Action Cable

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


#### Turbo Rails

Documentation outline:

- explain why we need to be careful
- explain how it works (global IDs)

TODO:

- [x] extend `to_global_id` and friends for Base
- [x] extend `to_global_id` and friends for Subtenant
- [x] some testing around global id would be good here
- [x] system test of a broadcast update


### Active Job

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


### Active Storage

Documentation outline:

- explain why we need to be careful
- explain how it works
  - if `connection_class` is set, then Active Storage will insert the tenant into the blob key
    - and the disk service will include the tenant in the path on disk in the root location, like: 'foobar/ab/cd/abcd12345678abcd'
- Disk Service can also have a tenanted root path, but it's optional

TODO:

- [x] extend Disk Service to change the path on disk
- [x] extend Blob to have tenanted keys


### ActionMailer

Documentation outline:

- explain how to configure the action mailer default host if needed, with a "%{tenant}" format specifier.


TODO:

- [x] Interpolate the tenant into a host set in config.action_mailer.default_url_options
- [ ] Do we need to do something similar for the asset host?
  - I'm going to wait until someone needs it, because it's not trivial to hijack.
- [ ] Do we need to do something similar for explicit host parameters to url helpers?
  - I don't think so.
  - I'm going to wait until someone needs it, because it's not trivial to hijack.


### ActionMailbox

TODO:

- [ ] I need a use case here around mail routing before I tackle it


### Console

Documentation outline:

- explain the concept of a "default tenant"
- explain usage of the `ARTENANT` environment variable to control startup


### Metrics

Some places we should add instrumentation:

- Creating a new tenant database
- Migrating a tenant database
- Destroying a tenant database
- Creating a tenanted connection pool
- Reaping a tenanted connection pool
