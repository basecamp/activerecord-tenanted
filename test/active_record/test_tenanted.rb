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
        database: "tmp/storage/secondary-%{tenant}.sqlite3",
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
    super
  end


  test "primary: config handler creates a template config" do
    config = with_stubbed_configurations(PRIMARY_TENANTED_CONFIG) do
      ActiveRecord::Base.configurations.configs_for(include_hidden: true)
    end
    assert_instance_of ActiveRecord::Tenanted::DatabaseConfigurations::TemplateConfig, config.first
  end

  test "primary: schema and migrations" do
    Object.const_set :ApplicationRecord, Class.new(ActiveRecord::Base)
    ApplicationRecord.primary_abstract_class
    ApplicationRecord.tenanted

    Object.const_set :Note, Class.new(ApplicationRecord)

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

    result = nil
    assert_silent do
      with_stubbed_configurations(PRIMARY_TENANTED_CONFIG) do
        ActiveRecord::Base.connected_to(shard: "bar") do
          result = [Note.create(content: "qwer"), Note.count]
        end
      end
    end

    assert_instance_of Note, result.first
    assert_equal "qwer", result.first.content
    assert_equal 1, result.last
  ensure
    ActiveRecord.application_record_class = nil
    Object.send(:remove_const, :Note)
    Object.send(:remove_const, :ApplicationRecord)
  end

  test "secondary: config handler creates a template config" do
    config = with_stubbed_configurations(SECONDARY_TENANTED_CONFIG) do
      ActiveRecord::Base.configurations.configs_for(include_hidden: true)
    end
    assert_instance_of ActiveRecord::DatabaseConfigurations::HashConfig, config.first
    assert_instance_of ActiveRecord::Tenanted::DatabaseConfigurations::TemplateConfig, config.last
  end

  test "secondary: schema and migrations" do
    Object.const_set :ApplicationRecord, Class.new(ActiveRecord::Base)
    ApplicationRecord.primary_abstract_class

    Object.const_set :SecondaryRecord, Class.new(ActiveRecord::Base)
    SecondaryRecord.abstract_class = true
    SecondaryRecord.tenanted :secondary

    Object.const_set :Note, Class.new(SecondaryRecord)

    result = nil
    assert_output(/migrating.*create_table/m, nil) do
      with_stubbed_configurations(SECONDARY_TENANTED_CONFIG) do
        ActiveRecord::Base.connected_to(shard: "foo") do
          result = [Note.create(content: "asdf"), Note.count]
        end
      end
    end

    assert_instance_of Note, result.first
    assert_equal "asdf", result.first.content
    assert_equal 1, result.last
    assert File.exist?("tmp/storage/secondary-foo.sqlite3")
    assert File.exist?("tmp/db/secondary_schema.rb")

    result = nil
    assert_silent do
      with_stubbed_configurations(SECONDARY_TENANTED_CONFIG) do
        ActiveRecord::Base.connected_to(shard: "bar") do
          result = [Note.create(content: "qwer"), Note.count]
        end
      end
    end

    assert_instance_of Note, result.first
    assert_equal "qwer", result.first.content
    assert_equal 1, result.last
  ensure
    ActiveRecord.application_record_class = nil
    Object.send(:remove_const, :Note)
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
