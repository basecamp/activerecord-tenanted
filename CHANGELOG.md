# `activerecord-tenanted` Changelog

## next / unreleased

### Fixed

- `Tenanted::GlobalId::Locator` now inherits from `GlobalID::Locator::UnscopedLocator`, which is the locator Rails uses by default. Two behavior changes follow: GlobalID lookups no longer apply a model's `default_scope`, matching Rails; and `#locate_many` is now implemented, which Active Job on Rails edge requires to deserialize GlobalID arguments. `#locate_many` enforces the same tenant safety checks as `#locate`. @flavorjones
- `Tenanted::GlobalId::Locator` no longer emits a deprecation warning from GlobalID 1.4.0 about the missing `model_class` method. @flavorjones


## v0.7.0 / 2026-06-08

### Security

- Fixed this gem's override of `ActiveStorage::Service::DiskService#path_for` to match the upstream Rails 8.1.2.1 behavior preventing path traversal. See https://github.com/basecamp/activerecord-tenanted/security/advisories/GHSA-pmwx-rm49-xv39 for more information. @flavorjones

### Dependencies

- Bumped the minimum Rails version requirement to `>= 8.1.2.1` to simplify the `DiskService#path_for` fix. @flavorjones

### Added

- Add callbacks for `:with_tenant` which are invoked when `.with_tenant` is called. @flavorjones
- Add callbacks for `:set_current_tenant` which are invoked when `.current_tenant=` is called. @flavorjones

### Fixed

- `.current_tenant = nil` now clears the tenant context, properly setting the shard to `UNTENANTED_SENTINEL` instead of `""` @flavorjones
- `Tenanted::DiskService#path_for` now handles keys without a tenant prefix (e.g., from `ActiveStorage::FixtureSet.blob`) by falling back to standard DiskService behavior. @flavorjones

### Developer infrastructure

- Hardened Github Actions workflows. @flavorjones
- Added matrix testing against Rails 8.1 and Rails edge. @flavorjones


## v0.6.0 / 2025-11-05

### Breaking change: Rake tasks

Some rake task changes to rename tasks for the database name (like Rails does it):

- `db:migrate:DBNAME` replaces `db:migrate:tenant` and `db:migrate:tenant:all`
  - it operates on all tenants by default
  - if there are no tenants it will create a database for the default tenant
  - the `ARTENANT` env var can be specified to run against a specific tenant
- `db:drop:DBNAME` replaces `db:drop:tenant`
  - it operates on all tenants by default
  - NEW: the `ARTENANT` env var can be specified to run against a specific tenant
- `db:reset:DBNAME` replaces `db:reset:tenant`
  - it operates on all tenants by default
  - NEW: the `ARTENANT` env var can be specified to run against a specific tenant
- `Tenanted::DatabaseTasks.base_config` has been removed

Some additional changes:

- `Tenanted::DatabaseTasks` is now a class that takes a tenanted base config as a constructor parameter.
- `ActiveRecord::Tenanted.base_configs` is a new utility method that returns all the tenanted base configs for the current environment.


### Breaking change: SQL query logging

Recent cascading changes on Rails `main` related to structured logging have made it challenging to continue to support log output like this:

```
# old log structure
Account Count [tenant=686465299] (0.1ms)  SELECT COUNT(*) FROM "accounts"
```

This version of the gem moves to using a query log tag named `:tenant`, which is more in line with how Rails wants extensions to inject content into the query logs. To use it, set this in your application config:

```ruby
Rails.application.config.active_record.query_log_tags_enabled = true
Rails.application.config.active_record.query_log_tags = [ :tenant ]
```

When configured, the application will emit logs like this:

```
# new log structure
Account Count (0.3ms)  SELECT COUNT(*) FROM "accounts" /*tenant='686465299'*/
```

Read the [Rails Guide documentation on `config.active_record.query_log_tags`](https://guides.rubyonrails.org/configuring.html#config-active-record-query-log-tags) for more information on query logs in general.


### Added

- `UntenantedConnectionPool#size` returns the database configuration's `max_connections` value, so that code (like Solid Queue) can inspect config params without a tenant context.


## v0.5.0 / 2025-10-12

### Fixed

- Handle the new parallel testing behavior introduced by rails/rails#55769, unblocking Rails edge upgrades. #216 @flavorjones


### Changed

- The return value from an Active Record model `#cache_key` has changed from `users/1?tenant=foo` to `foo/users/1`. For existing applications, this will invalidate any relevant cache entries. #187 @miguelmarcondesf
- Renamed `ActiveRecord::Tenanted::DatabaseTasks.tenanted_config` to `.base_config`.


### Improved

- SQLite-specific code has been extracted into an adapter object. #204 #215 @andrewmarkle @flavorjones
- For tenanted model instances, `#inspect` now outputs the tenant attribute first, before the column attributes. #191 @lairtonmendes
- The `debug` gem is now available during testing. #200 @andrewmarkle


## v0.4.1 / 2025-09-17

No functional changes from v0.4.0.


## v0.4.0 / 2025-09-17

### Added

- Introduce `max_connection_pools` database configuration to limit the number of tenanted databases with open connections. Pools are reaped in least-recently-used order. #182 @flavorjones
- Documentation: Improved `GUIDE.md`. @flavorjones


### Changed

- Rename `ActiveRecord::Tenanted::DatabaseConfigurations::RootConfig` to `BaseConfig`. @flavorjones
- Rails dependency bumped to `>= 8.1.beta` #172 @andrewmarkle


## v0.3.0 / 2025-09-09

### Improved

- `#inspect` on instances of tenanted models includes the tenant. #155 @miguelmarcondesf @flavorjones
- `TenantSelector` middleware no longer directly renders a 404. Instead, it configures ActionDispatch::ShowExceptions middlware and raises an appropriate exception. #167 @flavorjones


## v0.2.0 / 2025-09-04

First release.


## v0.1.0

Empty gem file to claim the name.
