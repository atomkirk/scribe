defmodule SocialScribeWeb.ChatLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import Mox

  setup :verify_on_exit!

  test "renders chat page for authenticated user", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, _view, html} = live(conn, ~p"/dashboard/chat")
    assert html =~ "Ask Anything"
  end

  test "send_message shows error when empty", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

    html = render_submit(view, "send_message", %{"input" => ""})
    assert html =~ "Please enter a question"
  end

  test "send_message requires provider credential", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

    html = render_submit(view, "send_message", %{"input" => "What is John's email?"})
    assert html =~ "Please connect your HubSpot account first"
  end

  test "can search and select contact and send message", %{conn: conn} do
    user = user_fixture()
    _cred = hubspot_credential_fixture(%{user_id: user.id})

    meeting = meeting_fixture_with_transcript(user)

    SocialScribe.HubspotApiMock
    |> expect(:search_contacts, fn _credential, query ->
      assert query == "John"

      {:ok,
       [
         %{id: "123", firstname: "John", lastname: "Doe", email: "john@example.com", phone: nil, mobilephone: nil, company: "Acme"}
       ]}
    end)

    SocialScribe.HubspotApiMock
    |> expect(:get_contact, fn _credential, contact_id ->
      assert contact_id == "123"

      {:ok,
       %{id: "123", firstname: "John", lastname: "Doe", email: "john@example.com", phone: nil, mobilephone: nil, company: "Acme"}}
    end)

    SocialScribe.AIContentGeneratorMock
    |> expect(:generate_contact_chat_response, fn prompt ->
      assert prompt =~ "Contact:"
      assert prompt =~ "Meeting:"
      {:ok, "It is john@example.com"}
    end)

    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

    view |> element("button[phx-click='open_contact_search']") |> render_click()
    assert has_element?(view, "input[phx-keyup='search_contacts']")

    view
    |> element("input[phx-keyup='search_contacts']")
    |> render_keyup(%{"value" => "John"})

    :timer.sleep(250)

    assert render(view) =~ "John Doe"

    view
    |> element("button[phx-click='select_contact'][phx-value-contact_id='123']")
    |> render_click()

    :timer.sleep(250)

    html = render(view)
    assert html =~ "John"
    assert html =~ "Doe"

    render_submit(view, "send_message", %{"input" => "What is John's email?"})

    :timer.sleep(250)

    html = render(view)
    assert html =~ "What is John"
    assert html =~ "email?"
    assert html =~ "It is john@example.com"

    _meeting = meeting
  end

  defp meeting_fixture_with_transcript(user) do
    meeting = meeting_fixture(%{})

    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

    {:ok, _updated_event} =
      SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{
            "speaker" => "John Doe",
            "words" => [
              %{"text" => "Hello,"},
              %{"text" => "my"},
              %{"text" => "email"},
              %{"text" => "is"},
              %{"text" => "john@example.com"}
            ]
          }
        ]
      }
    })

    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
