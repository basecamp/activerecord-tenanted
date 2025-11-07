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

    # Debug: Check Turbo Stream connection state
    debug_turbo_stream_connection("after visit, before update")

    note1.update!(body: "note 1 version 2")

    # Debug: Check state after update
    debug_turbo_stream_connection("after update")

    # Give it a moment to process
    sleep 0.1 if ENV["CI"]
    debug_turbo_stream_connection("after sleep")

    assert_text("note 1 version 2")

    ApplicationRecord.with_tenant(tenant2) do
      note2.update!(body: "note 2 version 2")
    end
    assert_no_text("note 2 version 2")
    assert_text("note 1 version 2")
  end

  private
    def debug_turbo_stream_connection(label)
      return unless ENV["CI"]

      puts "\n=== DEBUG: #{label} ==="

      # Check if turbo-cable-stream-source element exists
      has_stream = page.has_css?("turbo-cable-stream-source", visible: false)
      puts "Has turbo-cable-stream-source: #{has_stream}"

      if has_stream
        # Check connection state via JavaScript
        connected = page.evaluate_script(<<~JS)
        const streamSource = document.querySelector('turbo-cable-stream-source');
        if (streamSource) {
          const subscription = streamSource.subscription;
          console.log('Stream source found:', streamSource);
          console.log('Subscription:', subscription);
          console.log('Consumer state:', streamSource.consumer?.connection?.isActive());
          {
            hasElement: true,
            hasConnectedAttr: streamSource.hasAttribute('connected'),
            hasSubscription: !!subscription,
            consumerState: streamSource.consumer?.connection?.getState?.() || 'unknown'
          }
        } else {
          { hasElement: false }
        }
        JS
        puts "Connection details: #{connected.inspect}"

        # Check the actual HTML
        stream_html = page.find("turbo-cable-stream-source", visible: false)[:outerHTML] rescue "not found"
        puts "Stream element HTML: #{stream_html}"
      end

      # Check current body content
      body_text = page.find("div", text: /Body:/).text rescue "not found"
      puts "Current body on page: #{body_text}"

      puts "===================\n"
    end
end
