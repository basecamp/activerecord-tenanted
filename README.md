# ActiveRecord::Tenanted

Enable a Rails application to host multiple isolated tenants.

> [!NOTE]
> Currently supported database adapters: SQLite3, MySQL (mysql2/trilogy), and PostgreSQL. PostgreSQL supports both schema-based (default) and database-based multi-tenancy strategies. If you have a use case for tenanting other databases supported by Rails, please reach out to the maintainers!

## Summary

### What is "multi-tenancy"?

A "multi-tenant application" can be informally defined as:

> ... a single instance of a software application (and its underlying database and hardware)
> serv[ing] multiple tenants (or user accounts).
>
> A tenant can be an individual user, but more frequently, it’s a group of users — such as a
> customer organization — that shares common access to and privileges within the application
> instance. Each tenant’s data is isolated from, and invisible to, the other tenants sharing the
> application instance, ensuring data security and privacy for all tenants.
>
> -- [IBM.com, "What is multi-tenant?"](https://www.ibm.com/think/topics/multi-tenant)

This gem's design is rooted in a few guiding principles in order to safely allow multiple tenants to share a Rails application instance:

- Data "at rest" is persisted in a separate store for each tenant's data, isolated either physically or logically from other tenants.
- Data "in transit" is only sent to users with authenticated access to the tenant instance.
- All tenant-related code execution must happen within a well-defined isolated tenant context with controls around data access and transmission.


### Making it dead simple.

Another guiding principle, though, is:

- Developing a multi-tenant Rails app should be as easy as developing a single-tenant app.

Your code shouldn't have to know about tenanting! The hope is that you will rarely need to think about managing tenant isolation, and that as long as you're following Rails conventions, this gem and the framework will keep your tenants' data safe.

This gem extends or integrates tightly with Rails to ensure that any data persisted or transmitted happens within an isolated tenant context — without developers having to think about it.


## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add activerecord-tenanted
```


## Usage

For detailed configuration and usage, see [GUIDE.md](./GUIDE.md).


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/basecamp/activerecord-tenanted. The tests are split between:

- fast unit tests run by `bin/test-unit`
- slower integration tests run by `bin/test-integration`

For a full test feedback loop, run `bin/ci`.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
