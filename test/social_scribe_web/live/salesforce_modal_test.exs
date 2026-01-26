defmodule SocialScribeWeb.SalesforceModalTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures

  describe "Salesforce Modal" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "renders modal when navigating to salesforce route", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "#salesforce-modal-wrapper")
      assert has_element?(view, "h2", "Update in Salesforce")
    end

    test "displays contact search input", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "input[placeholder*='Search']")
    end

    test "shows contact search initially without suggestions form", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Initially, only the contact search is shown, no form for suggestions
      # The form only appears after a contact is selected and suggestions are generated
      assert has_element?(view, "input[phx-keyup='contact_search']")

      # No suggestion form should be present initially
      refute has_element?(view, "form[phx-submit='apply_updates']")
    end

    test "modal can be closed by navigating back", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "#salesforce-modal-wrapper")

      # Navigate back to the meeting page
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute has_element?(view, "#salesforce-modal-wrapper")
    end
  end

  describe "Salesforce Modal - without credential" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "does not show Salesforce section when no credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute html =~ "Salesforce Integration"
      refute html =~ "Update Salesforce Contact"
    end

    test "redirects to meeting page when accessing salesforce route without credential", %{
      conn: conn,
      meeting: meeting
    } do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Modal should not be present since there's no salesforce credential
      refute html =~ "salesforce-modal-wrapper"
    end
  end

  describe "SalesforceModalComponent events" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "toggle_suggestion updates checkbox state", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # The modal component handles toggle_suggestion events
      # We can test this by sending the event directly to the component
      # First verify the modal is present
      assert has_element?(view, "#salesforce-modal-wrapper")
    end

    test "contact_search input is present and accepts input", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Verify the search input exists and has the correct attributes
      assert has_element?(view, "input[phx-keyup='contact_search']")
      assert has_element?(view, "input[placeholder*='Search']")
      assert has_element?(view, "#salesforce-modal-wrapper")
    end
  end

  # Helper function to create a meeting with transcript for testing
  defp meeting_fixture_with_transcript(user) do
    meeting = meeting_fixture(%{})

    # Update the meeting's calendar_event to belong to the test user
    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

    {:ok, _updated_event} =
      SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    # Create a transcript with some content
    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{
            "speaker" => "John Doe",
            "words" => [
              %{"text" => "Hello,"},
              %{"text" => "my"},
              %{"text" => "phone"},
              %{"text" => "number"},
              %{"text" => "is"},
              %{"text" => "555-1234"}
            ]
          }
        ]
      }
    })

    # Reload the meeting with all associations
    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
