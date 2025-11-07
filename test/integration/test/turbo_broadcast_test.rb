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

    debug_turbo_stream_connection("after visit, before update")

    note1.update!(body: "note 1 version 2")

    debug_turbo_stream_connection("after update")

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

      has_stream = page.has_css?("turbo-cable-stream-source", visible: false)
      puts "Has turbo-cable-stream-source: #{has_stream}"

      if has_stream
        # ES5-compatible JavaScript
        connected = page.evaluate_script(<<~JS)
        (function() {
          var streamSource = document.querySelector('turbo-cable-stream-source');
          if (streamSource) {
            var subscription = streamSource.subscription;
            var consumer = streamSource.consumer;
            var connection = consumer ? consumer.connection : null;
            var connectionState = connection ? (connection.getState ? connection.getState() : 'unknown') : 'no-connection';
            var isActive = connection ? (connection.isActive ? connection.isActive() : false) : false;

            return {
              hasElement: true,
              hasConnectedAttr: streamSource.hasAttribute('connected'),
              hasSubscription: !!subscription,
              consumerState: connectionState,
              consumerIsActive: isActive,
              signedStreamName: streamSource.getAttribute('signed-stream-name') || 'none'
            };
          } else {
            return { hasElement: false };
          }
        })();
        JS
        puts "Connection details: #{connected.inspect}"

        # Check the actual HTML
        stream_html = page.find("turbo-cable-stream-source", visible: false)[:outerHTML] rescue "not found"
        puts "Stream element HTML: #{stream_html}"
      end

      # Check current body content
      body_elem = page.all("div", text: /Body:/).first
      body_text = body_elem ? body_elem.text : "not found"
      puts "Current body on page: #{body_text}"

      # Check the note body specifically
      note_body = page.all("div").find { |div| div.text.match?(/note \d+ version \d+/) }
      puts "Note body element: #{note_body ? note_body.text : 'not found'}"

      puts "===================\n"
    end
end
