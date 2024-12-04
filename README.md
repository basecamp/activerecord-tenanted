# ActiveRecord::Tenanted

Enable a Rails application to have separate sqlite database files for each tenant.

## Summary

This gem relies upon Rails's built-in sharding functionality, but does not require shards to be statically declared in `config/database.yml`. If a new tenant is created, then the database will be created and the schema applied at runtime.

Only sqlite is supported.


## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add active_record-tenanted
```

## Usage

⚠ If you're not familiar with how Rails's built-in horizontal sharding works, it may be worth reading the Rails Guide on [Multiple Databases with Active Record](https://guides.rubyonrails.org/active_record_multiple_databases.html#setting-up-your-application) before proceeding.

### Configuring `database.yml`

There are two changes needed to your `config/database.yml` file to tenant a database:

1. add `tenanted: true` as an additional configuration key
2. template the database file name using `%{tenant}`

For example, if you're tenanting your primary database, it might look like this:

``` yaml
development:
  <<: *default
  database: storage/development_%{tenant}.sqlite3
  tenanted: true

production:
  <<: *default
  database: storage/production_%{tenant}.sqlite3
  tenanted: true
```

In this case:

- the database file for tenant "foo" would be located on disk at `storage/production_foo.sqlite3`.
- the schema file (once created, see below) will be located at the default location `db/schema.rb`
- migrations will be located at the default location `db/migrate/`


Or if you're tenanting a secondary database:

``` yaml
development:
  primary:
    <<: *default
    database: storage/development.sqlite3
  secondary:
    <<: *default
    database: storage/development_tenant/%{tenant}.sqlite3
    migrations_paths: db/secondary_migrate
    tenanted: true

production:
  primary:
    <<: *default
    database: storage/production.sqlite3
  secondary:
    <<: *default
    database: storage/production_tenant/%{tenant}.sqlite3
    migrations_paths: db/secondary_migrate
    tenanted: true
```

In this case:

- the database file for tenant "foo" would be located on disk at `storage/production_tenant/foo.sqlite3`.
- the schema file (once created, see below) will be located at `db/secondary_schema.rb`.
- migrations will be located under `db/secondary_migrate/`


#### Hashed directory structure

For applications with a large number of tenants, it may be preferable to use a "hashed directory structure" to avoid having many database files in the same directory.

For the purposes of creating nesteed directories, the following format specifiers are available (in addition to `tenant`:

- `tenant_hash1` - first two hexadecimal characters of the MD5 signature of the tenant
- `tenant_hash2` - next two characters as a subdirectory of hash1
- `tenant_hash3` - next two characters as a subdirectory of hash2
- `tenant_hash4` - next two characters as a subdirectory of hash3

So, for example, for a tenant of `foo` which hashes to `acbd18db4cc2f85cedef654fccc4a4d8`:

- `tenant_hash1` = `ac`
- `tenant_hash2` = `ac/bd`
- `tenant_hash3` = `ac/bd/18`
- `tenant_hash4` = `ac/bd/18/db`

And so for a database config of:

> `storage/%{tenant_hash4}/%{tenant}.sqlite3`

the application could have 4.2 billion tenants without exceeding 255 entries in any directory.


### Configuring Active Record

The primary database may be configured as tenanted in ApplicationRecord this way:

``` ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  tenanted
end
```

where any tenanted models should then inherit from that common abstract connection class:

``` ruby
class PrivateNotes < ApplicationRecord
  # this model will be stored in a tenanted primary database file
end
```


Or a secondary database may be configured as tenanted this way:

``` ruby
class TenantedRecord < ApplicationRecord
  self.abstract_class = true

  tenanted :secondary # the database key from `config/database.yml`
end
```

where any tenanted models should then inherit from that common abstract class:

``` ruby
class PrivateNotes < TenantedRecord
  # this model will be stored in a tenanted secondary database file
end
```

### Configuring Active Storage to use the tenanted database

It's possible to set up Active Storage to use the tenanted database. In an initializer:

``` ruby
ActiveSupport.on_load(:active_storage_record) do
  tenanted_with "TenantedRecord"
end
```

where `"TenantedRecord"` is the name of the abstract base class for the tenanted models.


### Automatic tenant switching

Because the tenant behavior is built on top of Rails's sharding functionality, we can use the [`ShardSelector` middleware](https://guides.rubyonrails.org/active_record_multiple_databases.html#activating-automatic-shard-switching) to set the tenant for the duration of a request.

First, create a new file `config/initializers/tenanted_db.rb` with the following contents:

``` ruby
Rails.application.configure do
  config.active_record.shard_selector = { lock: true }
  config.active_record.shard_resolver = ->(request) { your_code_here }
end
```

⚠ Note that until Rails 8.1, automatic tenant switching is only supported for the primary database, due to a limitation in Rails's `ShardSelector` middleware. In Rails 8.1 you can specify the abstract connection class:

``` ruby
Rails.application.configure do
  config.active_record.shard_selector = { lock: true, class_name: "TenantedRecord" }
  config.active_record.shard_resolver = ->(request) { your_code_here }
end
```

Applications must provide the code for the resolver as it depends on application specific models. An example resolver that uses per-tenant subdomains might look like this:

``` ruby
Rails.application.configure do
  config.active_record.shard_selector = { lock: true }
  config.active_record.shard_resolver = ->(request) { request.subdomain }
end
```


### Granular database connection switching

If you need to access multiple tenants, you can use `ActiveRecord::Base.connected_to` to dynamically change tenant:

``` ruby
# fetch the first note for tenant "foo"
tenant1_note = ActiveRecord::Base.connected_to(shard: "foo") { Note.first }

# fetch the first note for tenant "bar"
tenant2_note = ActiveRecord::Base.connected_to(shard: "bar") { Note.first }
```


### Logging

All logs emitted by tenanted database connections will automaticaly contain the tenant identifier, for example:

```
Note Load [tenant=foo] (0.1ms)  SELECT "notes".* FROM "notes" ORDER BY "notes"."id" ASC LIMIT 1 /*application='Exploration'*/
           ^^^^^^^^^^
```


### Setting up testing

For testing, it's necessary to set up a "default" tenant that will be used implicitly for all the tests

In non-parallel testing, add code like this to your test helper:

``` ruby
TenantedRecord.connecting_to(shard: "default")
```

For parallel testing, add code like this to your test helper:

``` ruby
module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    parallelize_setup do |j|
      TenantedRecord.connecting_to(shard: j)
    end
  end
end
```


### Database tasks, schemas, and migrations

The nature of the tenanted database file is that it's created when the tenant is first accessed. This requires that the schema file also be created dynamically, and migrations to be applied at runtime. So some differences you'll notice in a tenanted database:

#### Database tasks are disabled

The normal database tasks like `db:create`, `db:prepare`, `db:migrate`, etc. will not run on the tenanted database.

#### The schema file is generated when the database is first accessed

When the database is first accessed a few things happen before the SQL statement is run:

1. The database file is created (i.e., `db:create`)
2. If the schema migrations table is missing and the schema file exists, the schema is loaded (i.e., `db:schema:load`)
3. Any pending migrations are run (i.e., `db:migrate`)
4. (⚠ `development` only) If any migrations were run, the schema is written to file (i.e., `db:schema:dump`)

Only after those steps have completed will queries be run against the database.


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/basecamp/active_record-tenanted. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/basecamp/active_record-tenanted/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the ActiveRecord::Tenanted project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/basecamp/active_record-tenanted/blob/main/CODE_OF_CONDUCT.md).
