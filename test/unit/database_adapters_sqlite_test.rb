# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::DatabaseAdapters::SQLite do
  let(:adapter) { ActiveRecord::Tenanted::DatabaseAdapters::SQLite.new(Object.new) }
  let(:dir) { Dir.mktmpdir }

  describe "path_for" do
    test "file path" do
      database = "storage/db/tenanted/foo/main.sqlite3"
      expected = "storage/db/tenanted/foo/main.sqlite3"
      assert_equal(expected, adapter.path_for(database))
    end

    test "absolute URI" do
      database = "file:#{dir}/storage/db/tenanted/foo/main.sqlite3"
      expected = "#{dir}/storage/db/tenanted/foo/main.sqlite3"
      assert_equal(expected, adapter.path_for(database))
    end

    test "absolute URI with query params" do
      database = "file:#{dir}/storage/db/tenanted/foo/main.sqlite3?vfs=unix-dotfile"
      expected = "#{dir}/storage/db/tenanted/foo/main.sqlite3"
      assert_equal(expected, adapter.path_for(database))
    end

    test "relative URI" do
      database = "file:storage/db/tenanted/foo/main.sqlite3"
      expected = "storage/db/tenanted/foo/main.sqlite3"
      assert_equal(expected, adapter.path_for(database))
    end

    test "relative URI with query params" do
      database = "file:storage/db/tenanted/foo/main.sqlite3?vfs=unix-dotfile"
      expected = "storage/db/tenanted/foo/main.sqlite3"
      assert_equal(expected, adapter.path_for(database))
    end
  end

  describe "test_workerize" do
    test "file path" do
      database = "storage/db/tenanted/foo/main.sqlite3"
      expected = "storage/db/tenanted/foo/main.sqlite3_99"
      assert_equal(expected, adapter.test_workerize(database, 99))
    end

    test "file path that has the suffix" do
      database = "storage/db/tenanted/foo/main.sqlite3_99"
      assert_equal(database, adapter.test_workerize(database, 99))
    end

    test "URI" do
      database = "file:storage/db/tenanted/foo/main.sqlite3"
      expected = "file:storage/db/tenanted/foo/main.sqlite3_99"
      assert_equal(expected, adapter.test_workerize(database, 99))
    end

    test "URI with query params" do
      database = "file:storage/db/tenanted/foo/main.sqlite3?vfs=unix-dotfile"
      expected = "file:storage/db/tenanted/foo/main.sqlite3_99?vfs=unix-dotfile"
      assert_equal(expected, adapter.test_workerize(database, 99))
    end

    test "URI with query params that has the suffix" do
      database = "file:storage/db/tenanted/foo/main.sqlite3_99?vfs=unix-dotfile"
      assert_equal(database, adapter.test_workerize(database, 99))
    end
  end
end
