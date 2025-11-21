require "application_system_test_case"

class TestTurboBroadcast < ApplicationSystemTestCase
  test "broadcast does not cross the streams" do
    tenant2 = __method__

    note1 = Note.create!(title: "Tenant-1", body: "note 1 version 1")
    note2 = ApplicationRecord.create_tenant(tenant2) do
      Note.create!(title: "Tenant-2", body: "note 2 version 1", id: note1.id)
    end
    assert_equal(note1.id, note2.id)

    visit note_url(note1)
    assert_text("note 1 version 1")

    wait_for_turbo_stream_connected

    note1.update!(body: "note 1 version 2")
    assert_text("note 1 version 2")

    ApplicationRecord.with_tenant(tenant2) do
      note2.update!(body: "note 2 version 2")
    end
    assert_no_text("note 2 version 2")
    assert_text("note 1 version 2")
  end

  private
    # Wait for the Turbo Stream WebSocket connection to establish before broadcasting updates.
    # Without this, broadcasts can be sent before the browser is subscribed, causing them to be lost.
    def wait_for_turbo_stream_connected
      assert_selector("turbo-cable-stream-source[connected]", visible: false, wait: 5)
    rescue Capybara::ElementNotFound
      sleep 0.1
    end
end
