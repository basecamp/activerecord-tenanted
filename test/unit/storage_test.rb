# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::Storage do
  describe "DiskService" do
    let(:allow_untenanted_active_storage) { false }

    setup do
      @old_allow_untenanted = Rails.application.config.active_record_tenanted.allow_untenanted_active_storage
      Rails.application.config.active_record_tenanted.allow_untenanted_active_storage = allow_untenanted_active_storage
    end

    teardown do
      Rails.application.config.active_record_tenanted.allow_untenanted_active_storage = @old_allow_untenanted
    end

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

          describe "with allow_untenanted_active_storage enabled" do
            let(:allow_untenanted_active_storage) { true }

            test "allows access without tenant" do
              ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
                assert_equal("/path/to/%{tenant}/storage", service.root)
              end
            end

            test "uses tenant when available" do
              ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
                TenantedApplicationRecord.create_tenant("foo") do
                  assert_equal("/path/to/foo/storage", service.root)
                end
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

        describe "with allow_untenanted_active_storage enabled" do
          let(:allow_untenanted_active_storage) { true }
          let(:root_path) { "/path/to/storage" }

          test "allows access while untenanted" do
            ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
              assert_equal("/path/to/storage", service.root)
            end
          end

          test "uses current tenant while tenanted" do
            ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
              TenantedApplicationRecord.create_tenant("foo") do
                assert_equal("/path/to/storage", service.root)
              end
            end
          end
        end
      end
    end

    describe ".path_for" do
      with_active_storage do
        let(:service) { ActiveStorage::Service::DiskService.new(root: "/path/to/storage") }

        describe "with allow_untenanted_active_storage enabled" do
          let(:allow_untenanted_active_storage) { true }

          test "handles non-tenanted keys" do
            ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
              non_tenanted_key = "abc123"

              expected_path = "/path/to/storage/ab/c1/#{non_tenanted_key}"
              assert_equal expected_path, service.path_for(non_tenanted_key)
            end
          end
        end

        test "handles tenanted keys" do
          ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
            TenantedApplicationRecord.create_tenant("foo") do
              tenanted_key = "foo/abc123"

              expected_path = "/path/to/storage/foo/ab/c1/abc123"
              assert_equal expected_path, service.path_for(tenanted_key)
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

      test "raises exception without tenant when flag is disabled" do
        ActiveRecord::Tenanted.stub(:connection_class, TenantedApplicationRecord) do
          assert_raises(ActiveRecord::Tenanted::NoTenantError) do
            ActiveStorage::Blob.new(filename: "foo.jpg", byte_size: 100, checksum: "abc123", service_name: service_name).key
          end
        end
      end
    end
  end
end
