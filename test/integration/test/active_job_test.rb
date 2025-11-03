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
    tenant = "global_id_locator_catches_wrong_tenant"
    note = ApplicationRecord.create_tenant(tenant) do
      Note.create!(title: "asdf", body: "Lorem ipsum.")
    end

    NoteCheerioJob.perform_later(note) # kicked off from test-tenant context

    e = assert_raises(ActiveJob::DeserializationError) { perform_enqueued_jobs }

    # this will be a RecordNotFound if the GlobalID locator is not installed correctly
    assert_kind_of(ActiveRecord::Tenanted::WrongTenantError, e.cause)
  end

  test "global id locator catches untenanted context" do
    tenant = "global_id_locator_catches_untenanted_context"
    note = ApplicationRecord.create_tenant(tenant) do
      Note.create!(title: "asdf", body: "Lorem ipsum.")
    end

    ApplicationRecord.without_tenant do
      NoteCheerioJob.perform_later(note) # kicked off from test-tenant context
    end

    e = assert_raises(ActiveJob::DeserializationError) { perform_enqueued_jobs }

    # this will be a RecordNotFound if the GlobalID locator is not installed correctly
    # this will be a WrongTenantError if the active job test helper isn't installed correctly
    assert_kind_of(ActiveRecord::Tenanted::NoTenantError, e.cause)
  end
end
