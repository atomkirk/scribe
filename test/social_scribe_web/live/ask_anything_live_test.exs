defmodule SocialScribeWeb.AskAnythingLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures

  describe "Ask Anything Live" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "renders the chat interface", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/dashboard/ask")

      assert html =~ "Ask Anything"
      assert has_element?(view, "button", "Chat")
      assert has_element?(view, "button", "History")
    end

    test "shows welcome message when no messages", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/ask")

      assert html =~ "I can answer questions about your CRM contacts and data"
    end

    test "shows no CRM connected message when no credentials", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/ask")

      assert html =~ "No CRM connected"
    end

    test "can switch between chat and history tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Click on History tab
      view |> element("button", "History") |> render_click()

      assert has_element?(view, "p", "No conversations yet")

      # Click back to Chat tab
      view |> element("button", "Chat") |> render_click()

      assert has_element?(view, "input[placeholder*='Ask anything']")
    end

    test "has message input field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      assert has_element?(view, "input[name='message']")
      assert has_element?(view, "button[type='submit']")
    end

    test "has add context button for contact tagging", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/ask")

      assert html =~ "Add context"
    end
  end

  describe "Ask Anything with HubSpot" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})

      %{
        conn: log_in_user(conn, user),
        user: user,
        hubspot_credential: hubspot_cred
      }
    end

    test "shows HubSpot as connected source", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/ask")

      # Should show HubSpot indicator (orange dot)
      assert html =~ "HubSpot"
      refute html =~ "No CRM connected"
    end

    test "can open contact search dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Click Add context button
      view |> element("button", "Add context") |> render_click()

      # Should show search input
      assert has_element?(view, "input[placeholder*='Search contacts']")
    end
  end

  describe "Ask Anything with Salesforce" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      %{
        conn: log_in_user(conn, user),
        user: user,
        salesforce_credential: salesforce_cred
      }
    end

    test "shows Salesforce as connected source", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/ask")

      # Should show Salesforce indicator (blue dot)
      assert html =~ "Salesforce"
      refute html =~ "No CRM connected"
    end
  end

  describe "Ask Anything with both CRMs" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})
      salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      %{
        conn: log_in_user(conn, user),
        user: user,
        hubspot_credential: hubspot_cred,
        salesforce_credential: salesforce_cred
      }
    end

    test "shows both CRMs as connected sources", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/ask")

      assert html =~ "HubSpot"
      assert html =~ "Salesforce"
    end
  end

  describe "Chat History" do
    setup %{conn: conn} do
      user = user_fixture()

      # Create some conversations
      {:ok, conv1} =
        SocialScribe.CRMChat.create_conversation(user, %{title: "First conversation"})

      {:ok, _msg1} =
        SocialScribe.CRMChat.add_message(conv1, %{
          role: "user",
          content: "Hello there"
        })

      %{
        conn: log_in_user(conn, user),
        user: user,
        conversation: conv1
      }
    end

    test "shows conversation history in History tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Switch to History tab
      view |> element("button", "History") |> render_click()

      # Should show the conversation
      assert render(view) =~ "First conversation"
    end

    test "can select a conversation from history", %{conn: conn, conversation: conv} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Switch to History tab
      view |> element("button", "History") |> render_click()

      # Click on the conversation
      view |> element("button[phx-value-id='#{conv.id}']") |> render_click()

      # Should switch to chat tab and show message
      assert render(view) =~ "Hello there"
    end

    test "new chat button clears current conversation", %{conn: conn, conversation: conv} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Switch to History tab and select conversation
      view |> element("button", "History") |> render_click()
      view |> element("button[phx-value-id='#{conv.id}']") |> render_click()

      # Now click new chat
      view |> element("button[phx-click='new_chat']") |> render_click()

      # Should show welcome message again (no messages)
      assert render(view) =~ "I can answer questions about your CRM contacts and data"
    end
  end
end
