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
        # Simple checks without complex JavaScript
        has_connected_attr = page.has_css?("turbo-cable-stream-source[connected]", visible: false)
        puts "Has 'connected' attribute: #{has_connected_attr}"

        # Get the HTML of the element
        stream_html = page.find("turbo-cable-stream-source", visible: false)[:outerHTML] rescue "not found"
        puts "Stream element: #{stream_html}"

        # Check if subscription exists - simpler approach
        has_subscription = page.evaluate_script("!!document.querySelector('turbo-cable-stream-source').subscription") rescue false
        puts "Has subscription object: #{has_subscription}"
      end

      # Check current page content
      current_body = page.text
      if current_body =~ /note 1 version (\d+)/
        puts "Current note version shown: version #{$1}"
      else
        puts "Could not find note version in page"
      end

      puts "===================\n"
    end
end
