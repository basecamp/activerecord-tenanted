# `activerecord-tenanted` Changelog

## next / unreleased

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


### Added

- Add callbacks for `:with_tenant` which are invoked when `.with_tenant` is called.
- Add callbacks for `:set_current_tenant` which are invoked when `.current_tenant=` is called.
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
