require "test_helper"

class NoteCheerioJobTest < ActiveJob::TestCase
  test "update the note" do
    note = notes(:one)
    assert_not_includes(note.body, "Cheerio!")

    NoteCheerioJob.perform_later(note)

    perform_enqueued_jobs
    note.reload

    assert_includes(note.body, "Cheerio!")
  end

  test "perform_now called from tenanted code behaves as expected" do
    note = notes(:one)
    assert_not_includes(note.body, "Cheerio!")

    ApplicationRecord.with_tenant(note.tenant) do
      NoteCheerioJob.perform_now(note)
    end
    note.reload

    assert_includes(note.body, "Cheerio!")
  end

  test "global id locator catches wrong tenant context" do
    tenant = __method__
    note = ApplicationRecord.create_tenant(tenant) do
      Note.create!(title: "asdf", body: "Lorem ipsum.")
    end

    NoteCheerioJob.perform_later(note) # kicked off from test-tenant context

    e = assert_raises(ActiveJob::DeserializationError) { perform_enqueued_jobs }

    assert_tenant_error(ActiveRecord::Tenanted::WrongTenantError, e)
  end

  test "global id locator catches untenanted context" do
    tenant = __method__
    note = ApplicationRecord.create_tenant(tenant) do
      Note.create!(title: "asdf", body: "Lorem ipsum.")
    end

    ApplicationRecord.without_tenant do
      NoteCheerioJob.perform_later(note) # kicked off from test-tenant context
    end

    e = assert_raises(ActiveJob::DeserializationError) { perform_enqueued_jobs }

    assert_tenant_error(ActiveRecord::Tenanted::NoTenantError, e)
  end

  private
    # GlobalID::Locator.fetch may re-raise our error wrapped in RecordUnavailable.
    def assert_tenant_error(error_class, error)
      chain = [ error ]
      chain << chain.last.cause while chain.last.cause

      assert(chain.any? { |e| e.is_a?(error_class) },
             "Expected #{error_class} in #{chain.map(&:class).inspect}")
    end
end
