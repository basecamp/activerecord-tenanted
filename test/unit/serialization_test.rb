# frozen_string_literal: true

require "test_helper"
require "active_support/message_pack"

SERIALIZERS = {
  "Marshal" => {
    dump: ->(record) { Marshal.dump(record) },
    load: ->(payload) { Marshal.load(payload) },
  },
  "JSON" => {
    dump: ->(record) { record.to_json },
    load: ->(payload) { User.new.from_json(payload) },
  },
  "YAML" => {
    dump: ->(record) { YAML.dump(record) },
    load: ->(payload) { YAML.unsafe_load(payload) },
  },
  "MessagePack" => {
    dump: ->(record) { ActiveSupport::MessagePack::CacheSerializer.dump(record) },
    load: ->(payload) { ActiveSupport::MessagePack::CacheSerializer.load(payload) },
  },
}

describe "Serializing tenanted records" do
  with_scenario(:primary_db, :primary_record) do
    setup do
      TenantedApplicationRecord.create_tenant("foo") do
        User.create!(email: "user1@foo.example.org")
      end

      TenantedApplicationRecord.create_tenant("bar")
    end

    SERIALIZERS.each do |format, serializer|
      describe format do
        let(:dump_in_tenant_context) do
          TenantedApplicationRecord.with_tenant("foo") { serializer[:dump].call(User.first) }
        end

        let(:dump_outside_tenant_context) do
          user = TenantedApplicationRecord.with_tenant("foo") { User.first }
          TenantedApplicationRecord.without_tenant { serializer[:dump].call(user) }
        end

        describe "dumping in a tenanted context" do
          test "loading in the same tenant context round-trips" do
            payload = dump_in_tenant_context

            loaded = TenantedApplicationRecord.with_tenant("foo") { serializer[:load].call(payload) }

            assert_equal("foo", loaded.tenant)
            assert_equal("user1@foo.example.org", loaded.email)
          end

          test "loading outside of a tenanted context round-trips" do
            payload = dump_in_tenant_context

            loaded = TenantedApplicationRecord.without_tenant { serializer[:load].call(payload) }

            assert_equal("foo", loaded.tenant)
            assert_equal("user1@foo.example.org", loaded.email)
          end

          test "loading in another tenant context round-trips" do
            payload = dump_in_tenant_context

            loaded = TenantedApplicationRecord.with_tenant("bar") { serializer[:load].call(payload) }

            assert_equal("foo", loaded.tenant)
            assert_equal("user1@foo.example.org", loaded.email)
          end
        end

        describe "dumping outside of a tenanted context" do
          test "loading in the same tenant context round-trips" do
            payload = dump_outside_tenant_context

            loaded = TenantedApplicationRecord.with_tenant("foo") { serializer[:load].call(payload) }

            assert_equal("foo", loaded.tenant)
            assert_equal("user1@foo.example.org", loaded.email)
          end

          test "loading outside of a tenanted context round-trips" do
            payload = dump_outside_tenant_context

            loaded = TenantedApplicationRecord.without_tenant { serializer[:load].call(payload) }

            assert_equal("foo", loaded.tenant)
            assert_equal("user1@foo.example.org", loaded.email)
          end

          test "loading in another tenant context round-trips" do
            payload = dump_outside_tenant_context

            loaded = TenantedApplicationRecord.with_tenant("bar") { serializer[:load].call(payload) }

            assert_equal("foo", loaded.tenant)
            assert_equal("user1@foo.example.org", loaded.email)
          end
        end
      end
    end
  end
end

describe "Serializing tenanted records with a loaded association" do
  with_scenario(:primary_db, :primary_record) do
    setup do
      with_migration "20250830152220_create_posts.rb"
      User.has_many :posts
      Post.belongs_to :user

      TenantedApplicationRecord.create_tenant("foo") do
        user = User.create!(email: "user1@foo.example.org")
        Post.create!(title: "Post 1 foo", user: user)
        Post.create!(title: "Post 2 foo", user: user)
      end

      TenantedApplicationRecord.create_tenant("bar")
    end

    # Only these two formats put loaded association targets in their payloads, and so only these
    # two restore a record by assigning to an association.
    %w[ Marshal MessagePack ].each do |format|
      describe format do
        let(:serializer) { SERIALIZERS[format] }

        let(:dump_in_tenant_context) do
          TenantedApplicationRecord.with_tenant("foo") do
            user = User.first
            user.posts.load
            serializer[:dump].call(user)
          end
        end

        let(:dump_outside_tenant_context) do
          user = TenantedApplicationRecord.with_tenant("foo") { User.first.tap { |u| u.posts.load } }
          TenantedApplicationRecord.without_tenant { serializer[:dump].call(user) }
        end

        describe "dumping in a tenanted context" do
          test "loading in the same tenant context round-trips" do
            payload = dump_in_tenant_context

            TenantedApplicationRecord.with_tenant("foo") do
              loaded = serializer[:load].call(payload)

              assert_equal("foo", loaded.tenant)
              assert_same_elements([ "Post 1 foo", "Post 2 foo" ], loaded.posts.map(&:title))
              assert_equal([ "foo" ], loaded.posts.map(&:tenant).uniq)
            end
          end

          test "loading outside of a tenanted context round-trips" do
            payload = dump_in_tenant_context

            loaded = TenantedApplicationRecord.without_tenant { serializer[:load].call(payload) }

            assert_equal("foo", loaded.tenant)
            assert_predicate(loaded.association(:posts), :loaded?)
            assert_same_elements([ "Post 1 foo", "Post 2 foo" ],
                                 loaded.association(:posts).target.map(&:title))
          end

          test "loading in another tenant context round-trips" do
            payload = dump_in_tenant_context

            loaded = TenantedApplicationRecord.with_tenant("bar") { serializer[:load].call(payload) }

            assert_equal("foo", loaded.tenant)
            assert_predicate(loaded.association(:posts), :loaded?)
            assert_same_elements([ "Post 1 foo", "Post 2 foo" ],
                                 loaded.association(:posts).target.map(&:title))
          end
        end

        describe "dumping outside of a tenanted context" do
          test "loading in the same tenant context round-trips" do
            payload = dump_outside_tenant_context

            TenantedApplicationRecord.with_tenant("foo") do
              loaded = serializer[:load].call(payload)

              assert_equal("foo", loaded.tenant)
              assert_same_elements([ "Post 1 foo", "Post 2 foo" ], loaded.posts.map(&:title))
              assert_equal([ "foo" ], loaded.posts.map(&:tenant).uniq)
            end
          end

          test "loading outside of a tenanted context round-trips" do
            payload = dump_outside_tenant_context

            loaded = TenantedApplicationRecord.without_tenant { serializer[:load].call(payload) }

            assert_equal("foo", loaded.tenant)
            assert_predicate(loaded.association(:posts), :loaded?)
            assert_same_elements([ "Post 1 foo", "Post 2 foo" ],
                                 loaded.association(:posts).target.map(&:title))
          end

          test "loading in another tenant context round-trips" do
            payload = dump_outside_tenant_context

            loaded = TenantedApplicationRecord.with_tenant("bar") { serializer[:load].call(payload) }

            assert_equal("foo", loaded.tenant)
            assert_predicate(loaded.association(:posts), :loaded?)
            assert_same_elements([ "Post 1 foo", "Post 2 foo" ],
                                 loaded.association(:posts).target.map(&:title))
          end
        end
      end
    end
  end
end

describe "Serialization options on a tenanted record" do
  with_scenario(:primary_db, :primary_record) do
    setup do
      TenantedApplicationRecord.create_tenant("foo") do
        User.create!(email: "user1@foo.example.org")
      end
    end

    let(:user) { TenantedApplicationRecord.with_tenant("foo") { User.first } }

    test "the tenant is serialized by default" do
      assert_equal("foo", user.serializable_hash["tenant"])
    end

    test "only: excludes the tenant when it is not named" do
      assert_not_includes(user.serializable_hash(only: [ :email ]).keys, "tenant")
    end

    test "only: includes the tenant when it is named" do
      assert_equal("foo", user.serializable_hash(only: [ :email, :tenant ])["tenant"])
    end

    test "except: excludes the tenant when it is named" do
      assert_not_includes(user.serializable_hash(except: [ :tenant ]).keys, "tenant")
    end

    test "except: includes the tenant when another attribute is named" do
      assert_equal("foo", user.serializable_hash(except: [ :email ])["tenant"])
    end
  end
end

# The Marshal, YAML, and JSON hooks are all defined on TenantCommon and so never run for an
# untenanted model. The MessagePack decoder patch is the only one installed globally, on every
# record in a payload, whatever its class.
describe "Serializing an untenanted record that has a tenant attribute" do
  with_scenario(:primary_db, :primary_record) do
    setup do
      Announcement.attribute :tenant, :string
    end

    test "MessagePack leaves the attribute alone" do
      announcement = Announcement.create!(message: "Announcement 1", tenant: "shared-column-value")

      payload = ActiveSupport::MessagePack::CacheSerializer.dump(announcement)
      loaded = ActiveSupport::MessagePack::CacheSerializer.load(payload)

      assert_equal("shared-column-value", loaded.tenant)
    end
  end
end

describe "Loading a tenanted record when a callback materializes the attribute set" do
  with_scenario(:primary_db, :primary_record) do
    setup do
      TenantedApplicationRecord.create_tenant("foo") do
        User.create!(email: "user1@foo.example.org")
      end
    end

    # Only these two formats carry the tenant inside the payload's attributes hash, which is the
    # hash the attribute set is built from.
    %w[ Marshal MessagePack ].each do |format|
      describe format do
        let(:serializer) { SERIALIZERS[format] }

        test "the tenant does not become a record attribute" do
          User.after_initialize { attribute_names }

          payload = TenantedApplicationRecord.with_tenant("foo") { serializer[:dump].call(User.first) }

          loaded = TenantedApplicationRecord.without_tenant { serializer[:load].call(payload) }

          assert_equal("foo", loaded.tenant)
          assert_not_includes(loaded.attribute_names, "tenant")
        end
      end
    end
  end
end
