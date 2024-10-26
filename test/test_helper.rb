# frozen_string_literal: true

require "rails"
require "active_record"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "active_record/tenanted"

require "minitest/autorun"

class ActiveRecord::Tenanted::TestCase < ActiveSupport::TestCase
end

ActiveRecord::Tasks::DatabaseTasks.db_dir = "tmp/db"
ActiveRecord::Migration.verbose = true
