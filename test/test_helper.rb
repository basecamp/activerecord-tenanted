# frozen_string_literal: true

require "rails"
require "active_record"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "active_record/tenanted"

require "minitest/autorun"

class ActiveRecord::Tenanted::TestCase < ActiveSupport::TestCase
  DBCONFIG_FIXTURES = {
    primary_tenanted: {
      development: {
        tenanted: true,
        adapter: "sqlite3",
        database: "tmp/storage/primary-%{tenant}.sqlite3",
        migrations_paths: "test/fixtures/migrations",
      }
    },

    secondary_tenanted: {
      development: {
        primary: {
          adapter: "sqlite3",
          database: "tmp/storage/primary.sqlite3",
          migrations_paths: "test/fixtures/migrations",
        },
        secondary: {
          tenanted: true,
          adapter: "sqlite3",
          database: "tmp/storage/%{tenant_hash4}/secondary-%{tenant}.sqlite3",
          migrations_paths: "test/fixtures/migrations",
        }
      }
    }
  }

  def setup
    super
    FileUtils.rm_rf("tmp")
  end

  def teardown
    FileUtils.rm_rf("tmp")
    ActiveRecord::Base.connection_handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
    super
  end

  def dbconfig(name)
    DBCONFIG_FIXTURES.fetch(name)
  end

  private
    def with_stubbed_configurations(configurations = config)
      old_configurations = ActiveRecord::Base.configurations
      ActiveRecord::Base.configurations = configurations

      yield
    ensure
      ActiveRecord::Base.configurations = old_configurations
    end
end

ActiveRecord::Tasks::DatabaseTasks.db_dir = "tmp/db"
ActiveRecord::Migration.verbose = true
