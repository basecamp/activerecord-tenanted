# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::Tenant do
  describe "#to_global_id" do
    for_each_scenario do
      let(:user) do
        TenantedApplicationRecord.create_tenant("foo") do
          User.create!(email: "user1@example.org")
        end
      end

      test "#to_global_id" do
        assert_equal("gid://dummy/User/1?tenant=foo", user.to_global_id.uri.to_s)
        assert_equal("gid://dummy/User/1?x=y&tenant=foo", user.to_global_id(x: "y").uri.to_s)
      end

      test "#to_gid" do
        assert_equal("gid://dummy/User/1?tenant=foo", user.to_gid.uri.to_s)
        assert_equal("gid://dummy/User/1?x=y&tenant=foo", user.to_gid(x: "y").uri.to_s)
      end

      test "#to_signed_global_id" do
        assert_equal("gid://dummy/User/1?tenant=foo", user.to_signed_global_id.uri.to_s)
        assert_equal("gid://dummy/User/1?x=y&tenant=foo", user.to_signed_global_id(x: "y").uri.to_s)
      end

      test "#to_sgid" do
        assert_equal("gid://dummy/User/1?tenant=foo", user.to_sgid.uri.to_s)
        assert_equal("gid://dummy/User/1?x=y&tenant=foo", user.to_sgid(x: "y").uri.to_s)
      end
    end
  end
end

describe GlobalID do
  describe "#tenant" do
    with_scenario(:primary_db, :primary_record) do
      test "on a tenanted model is the tenant" do
        gid = TenantedApplicationRecord.create_tenant("foo") do
          User.create!(email: "user1@example.org").to_global_id
        end

        assert_equal("foo", gid.tenant)
      end

      test "on an untenanted model is nil" do
        gid = Announcement.create!(message: "hello").to_global_id

        assert_nil(gid.tenant)
      end
    end
  end
end

describe ActiveRecord::Tenanted::GlobalId::Locator do
  with_scenario(:primary_db, :primary_record) do
    test "does not deprecate" do
      TenantedApplicationRecord.create_tenant("foo") do
        user = User.create!(email: "user1@example.org")

        assert_not_deprecated(GlobalID.deprecator) do
          ActiveRecord::Tenanted::GlobalId::Locator.new.locate(user.to_global_id)
        end
      end
    end
  end

  for_each_scenario do
    describe "#locate" do
      describe "given an untenanted GID" do
        test "raises MissingTenantError" do
          gid = GlobalID.parse("gid://dummy/User/1")

          TenantedApplicationRecord.create_tenant("foo") do
            assert_raises(ActiveRecord::Tenanted::MissingTenantError) do
              ActiveRecord::Tenanted::GlobalId::Locator.new.locate(gid)
            end
          end
        end
      end

      describe "in correct tenanted context" do
        test "loads correctly" do
          TenantedApplicationRecord.create_tenant("foo") do
            original_user = User.create!(email: "user1@example.org")
            user = ActiveRecord::Tenanted::GlobalId::Locator.new.locate(original_user.to_global_id)

            assert_equal(original_user, user)
          end
        end
      end

      describe "in wrong tenanted context" do
        test "raises WrongTenantError" do
          original_user = TenantedApplicationRecord.create_tenant("foo") do
            User.create!(email: "user1@example.org")
          end

          TenantedApplicationRecord.create_tenant("bar") do
            assert_raises(ActiveRecord::Tenanted::WrongTenantError) do
              ActiveRecord::Tenanted::GlobalId::Locator.new.locate(original_user.to_global_id)
            end
          end
        end
      end

      describe "in untenanted context" do
        test "raises NoTenantError" do
          original_user = TenantedApplicationRecord.create_tenant("foo") do
            User.create!(email: "user1@example.org")
          end

          TenantedApplicationRecord.without_tenant do
            assert_raises(ActiveRecord::Tenanted::NoTenantError) do
              ActiveRecord::Tenanted::GlobalId::Locator.new.locate(original_user.to_global_id)
            end
          end
        end
      end

      describe "given a model with a default scope" do
        test "ignores the default scope" do
          TenantedApplicationRecord.create_tenant("foo") do
            original_user = User.create!(email: "user1@example.org")
            User.class_eval { default_scope { where(email: nil) } }

            user = ActiveRecord::Tenanted::GlobalId::Locator.new.locate(original_user.to_global_id)

            assert_equal(original_user, user)
          end
        end
      end
    end

    describe "#locate_many" do
      describe "given an untenanted GID" do
        test "raises MissingTenantError" do
          gid = GlobalID.parse("gid://dummy/User/1")

          TenantedApplicationRecord.create_tenant("foo") do
            assert_raises(ActiveRecord::Tenanted::MissingTenantError) do
              ActiveRecord::Tenanted::GlobalId::Locator.new.locate_many([ gid ])
            end
          end
        end
      end

      describe "in correct tenanted context" do
        test "loads correctly" do
          TenantedApplicationRecord.create_tenant("foo") do
            original_users = [
              User.create!(email: "user1@example.org"),
              User.create!(email: "user2@example.org"),
            ]
            users = ActiveRecord::Tenanted::GlobalId::Locator.new.locate_many(original_users.map(&:to_global_id))

            assert_equal(original_users, users)
          end
        end
      end

      describe "in wrong tenanted context" do
        test "raises WrongTenantError" do
          original_user = TenantedApplicationRecord.create_tenant("foo") do
            User.create!(email: "user1@example.org")
          end

          TenantedApplicationRecord.create_tenant("bar") do
            assert_raises(ActiveRecord::Tenanted::WrongTenantError) do
              ActiveRecord::Tenanted::GlobalId::Locator.new.locate_many([ original_user.to_global_id ])
            end
          end
        end
      end

      describe "in untenanted context" do
        test "raises NoTenantError" do
          original_user = TenantedApplicationRecord.create_tenant("foo") do
            User.create!(email: "user1@example.org")
          end

          TenantedApplicationRecord.without_tenant do
            assert_raises(ActiveRecord::Tenanted::NoTenantError) do
              ActiveRecord::Tenanted::GlobalId::Locator.new.locate_many([ original_user.to_global_id ])
            end
          end
        end
      end

      describe "given a model with a default scope" do
        test "ignores the default scope" do
          TenantedApplicationRecord.create_tenant("foo") do
            original_user = User.create!(email: "user1@example.org")
            User.class_eval { default_scope { where(email: nil) } }

            users = ActiveRecord::Tenanted::GlobalId::Locator.new.locate_many([ original_user.to_global_id ])

            assert_equal([ original_user ], users)
          end
        end
      end
    end
  end
end

if GlobalID::Locator.respond_to?(:fetch)
  describe "GlobalID::Locator.fetch" do
    # GlobalID::Locator.fetch may re-raise our error wrapped in RecordUnavailable.
    def assert_tenant_error(error_class, error)
      chain = [ error ]
      chain << chain.last.cause while chain.last.cause

      assert(chain.any? { |e| e.is_a?(error_class) },
             "Expected #{error_class} in #{chain.map(&:class).inspect}")
    end

    for_each_scenario do
      describe "given an untenanted GID" do
        test "raises MissingTenantError" do
          gid = GlobalID.parse("gid://dummy/User/1")

          TenantedApplicationRecord.create_tenant("foo") do
            error = assert_raises(StandardError) { GlobalID::Locator.fetch(gid) }
            assert_tenant_error(ActiveRecord::Tenanted::MissingTenantError, error)
          end
        end
      end

      describe "in correct tenanted context" do
        test "loads correctly" do
          TenantedApplicationRecord.create_tenant("foo") do
            original_user = User.create!(email: "user1@example.org")

            assert_equal(original_user, GlobalID::Locator.fetch(original_user.to_global_id))
          end
        end

        test "raises RecordNotFound when the record is gone" do
          TenantedApplicationRecord.create_tenant("foo") do
            gid = User.create!(email: "user1@example.org").to_global_id
            User.delete_all

            assert_raises(GlobalID::Locator::RecordNotFound) do
              GlobalID::Locator.fetch(gid)
            end
          end
        end
      end

      describe "in wrong tenanted context" do
        test "raises WrongTenantError" do
          original_user = TenantedApplicationRecord.create_tenant("foo") do
            User.create!(email: "user1@example.org")
          end

          TenantedApplicationRecord.create_tenant("bar") do
            error = assert_raises(StandardError) { GlobalID::Locator.fetch(original_user.to_global_id) }
            assert_tenant_error(ActiveRecord::Tenanted::WrongTenantError, error)
          end
        end
      end

      describe "in untenanted context" do
        test "raises NoTenantError" do
          original_user = TenantedApplicationRecord.create_tenant("foo") do
            User.create!(email: "user1@example.org")
          end

          TenantedApplicationRecord.without_tenant do
            error = assert_raises(StandardError) { GlobalID::Locator.fetch(original_user.to_global_id) }
            assert_tenant_error(ActiveRecord::Tenanted::NoTenantError, error)
          end
        end
      end
    end
  end
end
