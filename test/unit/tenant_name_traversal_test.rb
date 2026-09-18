# frozen_string_literal: true

require "test_helper"

describe "tenant name path traversal" do
  def tenanted_config
    TenantedApplicationRecord.tenanted_root_config
  end

  def database_path_for(tenant_name)
    tenanted_config.config_adapter.path_for(tenanted_config.database_for(tenant_name))
  end

  def database_basename
    File.basename(database_path_for("sentinel"))
  end

  def tenant_root
    File.dirname(File.dirname(database_path_for("sentinel")))
  end

  def escaped_path
    File.join(File.dirname(tenant_root), database_basename)
  end

  def decoy_paths
    [ escaped_path,
      "#{escaped_path}-wal",
      "#{escaped_path}-shm",
      "#{escaped_path}.ready_lock",
      File.join(tenant_root, database_basename) ]
  end

  def plant_decoys
    FileUtils.mkdir_p(tenant_root)
    decoy_paths.each { |path| File.write(path, "decoy") }
  end

  def storage_tree
    Dir.glob(File.join(storage_path, "**", "*"), File::FNM_DOTMATCH)
      .reject { |path| File.basename(path).match?(/\A\.\.?\z/) }
      .sort
      .map { |path| [ path, File.file?(path) ? File.size(path) : :directory ] }
  end

  [
    [ "a parent directory",         ".." ],
    [ "the tenant root",            "." ],
    [ "a multi-segment traversal",  "../.." ],
    [ "an empty name",              "" ],
    [ "a hidden directory",         ".hidden" ],
    [ "a percent-escaped traversal", "%2e%2e" ],
    [ "a URI query separator",      "foo?bar" ],
    [ "a URI fragment separator",   "foo#bar" ],
    [ "a name that is not a URI",   "a[b" ],
    [ "a path separator",           "foo/bar" ],
    [ "a null byte",                "a\0b" ],
    [ "an invalid byte sequence",   "a\xFF".dup.force_encoding("UTF-8") ],
    [ "a UTF-16 name",              "a".encode("UTF-16LE") ],
  ].each do |description, tenant_name|
    [ :primary_db, :primary_uri_db ].each do |db_scenario|
      with_scenario(db_scenario, :primary_record) do
        setup { plant_decoys }

        test "create_tenant refuses #{description} and writes nothing" do
          before = storage_tree

          assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
            TenantedApplicationRecord.create_tenant(tenant_name)
          end

          assert_equal(before, storage_tree)
        end

        test "destroy_tenant refuses #{description} and deletes nothing" do
          before = storage_tree

          assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
            TenantedApplicationRecord.destroy_tenant(tenant_name)
          end

          assert_equal(before, storage_tree)
        end

        test "tenant_exist? reports #{description} as nonexistent" do
          assert_not(TenantedApplicationRecord.tenant_exist?(tenant_name))
        end

        test "with_tenant refuses #{description}" do
          assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
            TenantedApplicationRecord.with_tenant(tenant_name) { flunk("entered the tenant context") }
          end
        end
      end
    end
  end

  with_scenario(:primary_db, :primary_record) do
    test "current_tenant= refuses a traversing name" do
      assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
        TenantedApplicationRecord.current_tenant = "../.."
      end
    end

    test "a database whose tenant name is invalid is skipped with a warning" do
      FileUtils.mkdir_p(File.join(tenant_root, "legacy name"))
      FileUtils.touch(File.join(tenant_root, "legacy name", database_basename))

      log = capture_rails_log { assert_empty(tenanted_config.tenants) }

      assert_match(/invalid tenant name "legacy name"/, log.string)
    end
  end

  describe "Active Storage" do
    with_active_storage do
      let(:service) { ActiveStorage::Service::DiskService.new(root: "/path/to/tenants/%{tenant}/storage") }

      test "a traversing tenant never reaches the disk service root" do
        ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
          assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
            TenantedApplicationRecord.with_tenant("../../shared") { service.root }
          end
        end
      end

      test "a traversing tenant installed with connected_to never reaches the disk service root" do
        ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
          TenantedApplicationRecord.connected_to(shard: "../../shared", role: ActiveRecord.writing_role) do
            assert_raises(ActiveRecord::Tenanted::BadTenantNameError) do
              service.path_for("abcdef123456")
            end
          end
        end
      end
    end
  end

  describe "reachability over HTTP" do
    let(:fake_app) do
      Class.new do
        def call(env)
          [ 200, {}, [ "OK" ] ]
        end
      end.new
    end

    let(:selector) { ActiveRecord::Tenanted::TenantSelector.new(fake_app) }
    let(:env) { Rack::MockRequest.env_for("http://...example.com/") }

    setup do
      Rails.application.config.active_record_tenanted.connection_class = "TenantedApplicationRecord"
    end

    with_scenario(:primary_db, :primary_record) do
      test "the default subdomain resolver returns '..' for a triple-dot host" do
        resolver = Rails.application.config.active_record_tenanted.tenant_resolver

        assert_equal("..", resolver.call(ActionDispatch::Request.new(env)))
      end

      test "a request for a traversing subdomain is a missing tenant, not an error" do
        assert_raises(ActiveRecord::Tenanted::TenantDoesNotExistError) { selector.call(env) }
      end
    end
  end
end
