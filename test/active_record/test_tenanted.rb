# frozen_string_literal: true

require "test_helper"

class ActiveRecord::TestTenanted < ActiveRecord::Tenanted::TestCase
  PRIMARY_TENANTED_CONFIG = {
    development: {
      tenanted: true,
      adapter: "sqlite3",
      database: "tmp/storage/primary-%{tenant}.sqlite3",
      migrations_paths: "test/fixtures/migrations",
    }
  }

  SECONDARY_TENANTED_CONFIG = {
    development: {
      primary: {
        adapter: "sqlite3",
        database: "tmp/storage/primary.sqlite3",
      },
      secondary: {
        tenanted: true,
        adapter: "sqlite3",
        database: "tmp/storage/%{tenant_hash4}/secondary-%{tenant}.sqlite3",
        migrations_paths: "test/fixtures/migrations",
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


  test "primary: config handler creates a template config" do
    config = with_stubbed_configurations(PRIMARY_TENANTED_CONFIG) do
      ActiveRecord::Base.configurations.configs_for(include_hidden: true)
    end

    assert_pattern do
      config => [ActiveRecord::Tenanted::DatabaseConfigurations::TemplateConfig]
    end
  end

  test "primary: schema and migrations" do
    Object.const_set :ApplicationRecord, Class.new(ActiveRecord::Base)
    ApplicationRecord.primary_abstract_class
    ApplicationRecord.tenanted

    Object.const_set :Note, Class.new(ApplicationRecord)

    log = StringIO.new
    logger_was, ActiveRecord::Base.logger = ActiveRecord::Base.logger, ActiveSupport::Logger.new(log)

    result = nil
    assert_output(/migrating.*create_table/m, nil) do
      with_stubbed_configurations(PRIMARY_TENANTED_CONFIG) do
        ActiveRecord::Base.connected_to(shard: "foo") do
          result = [Note.create(content: "asdf"), Note.count]
        end
      end
    end

    assert_instance_of Note, result.first
    assert_equal "asdf", result.first.content
    assert_equal 1, result.last
    assert File.exist?("tmp/storage/primary-foo.sqlite3")
    assert File.exist?("tmp/db/schema.rb")
    assert_includes log.string, "[tenant=foo]"

    result = nil
    assert_silent do # no migration, we load the schema instead
      with_stubbed_configurations(PRIMARY_TENANTED_CONFIG) do
        ActiveRecord::Base.connected_to(shard: "bar") do
          result = [Note.create(content: "qwer"), Note.count]
        end
      end
    end

    assert_instance_of Note, result.first
    assert_equal "qwer", result.first.content
    assert_equal 1, result.last
    assert_includes log.string, "[tenant=bar]"
  ensure
    ActiveRecord.application_record_class = nil
    ActiveRecord::Base.logger = logger_was
    Object.send(:remove_const, :Note)
    Object.send(:remove_const, :ApplicationRecord)
  end

  test "primary: shared connection pool" do
    Object.const_set :ApplicationRecord, Class.new(ActiveRecord::Base)
    ApplicationRecord.primary_abstract_class
    ApplicationRecord.tenanted

    Object.const_set :Note, Class.new(ApplicationRecord)
    Object.const_set :Post, Class.new(ApplicationRecord)

    note_pool = nil
    post_pool = nil

    assert_output(/migrating.*create_table/m, nil) do
      with_stubbed_configurations(PRIMARY_TENANTED_CONFIG) do
        ActiveRecord::Base.connected_to(shard: "foo") do
          note_pool = Note.connection_pool
          post_pool = Post.connection_pool
        end
      end
    end

    assert_not_nil note_pool
    assert_same note_pool, post_pool
  ensure
    Object.send(:remove_const, :Note)
    Object.send(:remove_const, :Post)
    Object.send(:remove_const, :ApplicationRecord)
  end

  test "secondary: config handler creates a template config" do
    config = with_stubbed_configurations(SECONDARY_TENANTED_CONFIG) do
      ActiveRecord::Base.configurations.configs_for(include_hidden: true)
    end

    assert_pattern do
      config => [
        ActiveRecord::DatabaseConfigurations::HashConfig,
        ActiveRecord::Tenanted::DatabaseConfigurations::TemplateConfig
      ]
    end
  end

  test "secondary: schema and migrations" do
    Object.const_set :ApplicationRecord, Class.new(ActiveRecord::Base)
    ApplicationRecord.primary_abstract_class

    Object.const_set :SecondaryRecord, Class.new(ActiveRecord::Base)
    SecondaryRecord.abstract_class = true
    SecondaryRecord.tenanted :secondary

    Object.const_set :Note, Class.new(SecondaryRecord)

    log = StringIO.new
    logger_was, ActiveRecord::Base.logger = ActiveRecord::Base.logger, ActiveSupport::Logger.new(log)

    result = nil
    assert_output(/migrating.*create_table/m, nil) do
      with_stubbed_configurations(SECONDARY_TENANTED_CONFIG) do
        SecondaryRecord.connected_to(shard: "foo") do
          result = [Note.create(content: "asdf"), Note.count]
        end
      end
    end

    assert_instance_of Note, result.first
    assert_equal "asdf", result.first.content
    assert_equal 1, result.last

    # MD5 should be considered part of the API contract
    tenant_hash = Digest::MD5.hexdigest("foo")
    hash1 = tenant_hash[0..1]
    hash2 = tenant_hash[2..3]
    hash3 = tenant_hash[4..5]
    hash4 = tenant_hash[6..7]

    path = "tmp/storage/#{hash1}/#{hash2}/#{hash3}/#{hash4}/secondary-foo.sqlite3"
    assert File.exist?(path), "Expected #{path} to exist"
    assert File.exist?("tmp/db/secondary_schema.rb")
    assert_includes log.string, "[tenant=foo]"

    result = nil
    assert_silent do # no migration, we load the schema instead
      with_stubbed_configurations(SECONDARY_TENANTED_CONFIG) do
        SecondaryRecord.connected_to(shard: "bar") do
          result = [Note.create(content: "qwer"), Note.count]
        end
      end
    end

    assert_instance_of Note, result.first
    assert_equal "qwer", result.first.content
    assert_equal 1, result.last
    assert_includes log.string, "[tenant=bar]"
  ensure
    ActiveRecord.application_record_class = nil
    ActiveRecord::Base.logger = logger_was
    Object.send(:remove_const, :Note)
    Object.send(:remove_const, :SecondaryRecord)
    Object.send(:remove_const, :ApplicationRecord)
  end

  test "secondary: shared connection pool" do
    Object.const_set :ApplicationRecord, Class.new(ActiveRecord::Base)
    ApplicationRecord.primary_abstract_class

    Object.const_set :SecondaryRecord, Class.new(ActiveRecord::Base)
    SecondaryRecord.abstract_class = true
    SecondaryRecord.tenanted :secondary

    Object.const_set :Note, Class.new(SecondaryRecord)
    Object.const_set :Post, Class.new(SecondaryRecord)

    note_pool = nil
    post_pool = nil

    assert_output(/migrating.*create_table/m, nil) do
      with_stubbed_configurations(SECONDARY_TENANTED_CONFIG) do
        SecondaryRecord.connected_to(shard: "foo") do
          note_pool = Note.connection_pool
          post_pool = Post.connection_pool
        end
      end
    end

    assert_not_nil note_pool
    assert_same note_pool, post_pool
  ensure
    Object.send(:remove_const, :Note)
    Object.send(:remove_const, :Post)
    Object.send(:remove_const, :SecondaryRecord)
    Object.send(:remove_const, :ApplicationRecord)
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
