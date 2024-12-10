# frozen_string_literal: true

require_relative "lib/active_record/tenanted/version"

Gem::Specification.new do |spec|
  spec.name = "active_record-tenanted"
  spec.version = ActiveRecord::Tenanted::VERSION
  spec.authors = ["37signals, LLC"]

  spec.summary = "Enable a Rails application to have separate sqlite database files for each tenant."
  spec.description = <<~TEXT
    Enable a Rails application to have separate sqlite database files for each tenant.

    This gem relies upon Rails's built-in sharding functionality, but does not require shards to be
    statically declared in `config/database.yml`. If a new tenant is created, then the database will
    be created and the schema applied at runtime.
  TEXT
  spec.homepage = "https://github.com/basecamp/active_record-tenanted"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = %w[
    README.md
    LICENSE.txt
    lib/active_record/tenanted.rb
    lib/active_record/tenanted/version.rb
    lib/active_record/tenanted/database_configurations.rb
    lib/active_record/tenanted/patches.rb
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.1.0.alpha"
  spec.add_dependency "activerecord", ">= 8.1.0.alpha"
end
