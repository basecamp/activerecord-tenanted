# frozen_string_literal: true

require_relative "lib/active_record/tenanted/version"

Gem::Specification.new do |spec|
  spec.name        = "active_record-tenanted"
  spec.version     = ActiveRecord::Tenanted::VERSION
  spec.authors     = [ "Mike Dalessio" ]
  spec.email       = [ "mike@37signals.com" ]
  spec.license     = "MIT"
  spec.homepage    = "https://github.com/basecamp/active_record-tenanted"
  spec.summary     = "Enable a Rails application to have separate databases for each tenant."
  spec.description = <<~TEXT
    Enable a Rails application to have separate databases for each tenant.

    This gem primarily extends Active Record, creating a new connection pool for each tenant and
    using horizontal sharding to swap between them. It also provides integrations for middleware
    tenant selection, Action View Caching, Active Job, Action Cable, Active Storage, Action Mailbox,
    and Action Text, with support and documentation for Solid Cache, Solid Queue, Solid Cable, and
    Turbo Rails.
  TEXT

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "railties", ">= 8.1.alpha"
  spec.add_dependency "activerecord", ">= 8.1.alpha"
end
