require "test_helper"

class TestCaching < ActionDispatch::IntegrationTest
  test "fragment cache is tenanted" do
    tenant1 = "#{__method__}_1"
    tenant2 = "#{__method__}_2"

    note1 = ApplicationRecord.create_tenant(tenant1) do
      Note.create!(title: "tenant 1 note", body: "Lorem ipsum.")
    end
    note2 = ApplicationRecord.create_tenant(tenant2) do
      Note.create!(title: "tenant 2 note", body: "Four score and twenty years ago.")
    end

    # get the tenant 1 note, generating a fragment cache
    integration_session.host = "#{tenant1}.example.com"
    get note_path(note1)
    assert_response :ok
    page1a = @response.body

    # assert on setup: make sure the random number is injected, because we're about to rely on it
    # for testing the cache.
    assert_includes(page1a, "Random:")

    # get the tenant 2 note, which should NOT clobber the tenant 1 note cache
    integration_session.host = "#{tenant2}.example.com"
    get note_path(note2)
    assert_response :ok
    page2a = @response.body

    # let's re-fetch tenant 1 note to see if the fragment was cached correctly
    integration_session.host = "#{tenant1}.example.com"
    get note_path(note1)
    assert_response :ok
    page1b = @response.body

    # same for tenant 2 note
    integration_session.host = "#{tenant2}.example.com"
    get note_path(note2)
    assert_response :ok
    page2b = @response.body

    # was it cached? (is the random number the same?)
    assert_equal(page1a, page1b)
    assert_equal(page2a, page2b)

    # make sure we see what we expect
    assert_includes(page1a, "Lorem ipsum")
    assert_includes(page2a, "Four score and twenty")
  end
end
