# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::Storage do
  describe "DiskService" do
    describe ".root" do
      with_active_storage do
        let(:service) { ActiveStorage::Service::DiskService.new(root: root_path) }

        describe "with a tenanted root path" do
          let(:root_path) { "/path/to/%{tenant}/storage" }

          test "raises exception while untenanted" do
            ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
              assert_raises(ActiveRecord::Tenanted::NoTenantError) do
                service.root
              end
            end
          end

          test "returns current tenant while tenanted" do
            ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
              TenantedApplicationRecord.create_tenant("foo") do
                assert_equal("/path/to/foo/storage", service.root)
              end
            end
          end
        end

        describe "with a non-tenanted root path" do
          let(:root_path) { "/path/to/storage" }

          test "raises exception while untenanted" do
            ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
              assert_raises(ActiveRecord::Tenanted::NoTenantError) do
                service.root
              end
            end
          end

          test "returns current tenant while tenanted" do
            ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
              TenantedApplicationRecord.create_tenant("foo") do
                assert_equal("/path/to/storage", service.root)
              end
            end
          end
        end
      end
    end
  end

  describe "Blob" do
    setup do
      @was_services = ActiveStorage::Blob.services
      ActiveStorage::Blob.services = ActiveStorage::Service::Registry.new({ "disk-service": { service: "Disk", root: "/path/to/storage" } })
    end

    teardown do
      ActiveStorage::Blob.services = @was_services
    end

    let(:service_name) { "disk-service" }

    with_active_storage do
      test "key is prefixed with the tenant" do
        ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
          TenantedApplicationRecord.create_tenant("foo") do
            blob = ActiveStorage::Blob.new(filename: "foo.jpg", byte_size: 100, checksum: "abc123", service_name: service_name)

            assert blob.key.start_with?("foo/")
          end
        end
      end

      test "Disk Service path is tenant-specific" do
        ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
          TenantedApplicationRecord.create_tenant("foo") do
            blob = ActiveStorage::Blob.new(filename: "foo.jpg", byte_size: 100, checksum: "abc123", service_name: service_name)

            _, key = blob.key.split("/", 2)
            expected_path = "/path/to/storage/foo/#{key[0..1]}/#{key[2..3]}/#{key}"
            assert_equal expected_path, blob.service.path_for(blob.key)
          end
        end
      end

      test "Disk Service path_for falls back for keys without tenant prefix" do
        ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
          TenantedApplicationRecord.create_tenant("foo") do
            blob = ActiveStorage::Blob.new(filename: "foo.jpg", byte_size: 100, checksum: "abc123", service_name: service_name)

            # Keys from ActiveStorage::FixtureSet don't have tenant prefix
            non_tenanted_key = "abc123def456"
            expected_path = "/path/to/storage/ab/c1/#{non_tenanted_key}"
            assert_equal expected_path, blob.service.path_for(non_tenanted_key)
          end
        end
      end
    end

    describe "path traversal" do
      with_active_storage do
        let(:service) { ActiveStorage::Service::DiskService.new(root: "/path/to/%{tenant}/storage") }

        [
          [ "directory escape",   "../../../../etc/passwd",   "key has path traversal segments" ],
          [ "head fake escape",   "foo/../../../etc/passwd",  "key has path traversal segments" ],
          [ "sibling directory",  "../secret/token",          "key has path traversal segments" ],
          [ "invalid . segment",  "foo/./bar",                "key has path traversal segments" ],
          [ "invalid .. segment", "foo/../foo/bar",           "key has path traversal segments" ],
          [ "folder_for escape",  "foo/....secret",           "key is outside of disk service root" ],
          [ "embedded null byte", "foo/bar\x00.jpg",          "key is an invalid string" ],
          [ "empty key",          "foo/",                     "key has a blank segment" ],
          [ "empty tenant",       "/token",                   "key has a blank segment" ],
          [ "incompat encoding",  "a/b".encode("UTF-16LE"),   "key has incompatible encoding" ],
        ].each do |test_title, malicious_key, error_message|
          test "path_for raises InvalidKeyError for #{test_title}" do
            ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
              TenantedApplicationRecord.create_tenant("foo") do
                e = assert_raises(ActiveStorage::InvalidKeyError) do
                  service.path_for(malicious_key)
                end

                assert_includes e.message, error_message
              end
            end
          end
        end

        test "path_for keeps a benign tenant key inside the resolved root" do
          ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
            TenantedApplicationRecord.create_tenant("foo") do
              path = service.path_for("foo/abc123def456")
              assert path.start_with?(File.expand_path(service.root) + "/")
            end
          end
        end
      end
    end
  end
end
