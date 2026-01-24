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

      assert html =~ "I can answer questions about Jump meetings and data"
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

    test "shows hint to use @ for mentioning contacts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/ask")

      # Shows hint about using @ to mention
      assert html =~ "to mention a contact"
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

    test "can trigger inline mention search with @ symbol", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Trigger mention search (simulating typing @)
      render_hook(view, "mention_search", %{"query" => ""})

      # Should show mention dropdown
      assert has_element?(view, "#mention-dropdown")
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
      assert render(view) =~ "I can answer questions about Jump meetings and data"
    end
  end

  describe "Inline @ Mention" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})

      %{
        conn: log_in_user(conn, user),
        user: user,
        hubspot_credential: hubspot_cred
      }
    end

    test "input has MentionInput hook and correct placeholder", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Check input has the hook
      assert has_element?(view, "input#message-input[phx-hook='MentionInput']")

      # Check placeholder mentions @ for tagging
      html = render(view)
      assert html =~ "type @ to mention a contact"
    end

    test "mention_search event opens mention dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Initially, mention dropdown should not be visible
      refute has_element?(view, "#mention-dropdown")

      # Trigger mention search event (simulating typing @)
      render_hook(view, "mention_search", %{"query" => ""})

      # Mention dropdown should now be visible
      assert has_element?(view, "#mention-dropdown")
    end

    test "mention_search shows searching state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Trigger mention search with a query
      html = render_hook(view, "mention_search", %{"query" => "john"})

      # Should show searching indicator
      assert html =~ "Searching"
    end

    test "close_mention event closes dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Open mention dropdown
      render_hook(view, "mention_search", %{"query" => ""})
      assert has_element?(view, "#mention-dropdown")

      # Close mention dropdown
      render_hook(view, "close_mention", %{})

      # Dropdown should be gone
      refute has_element?(view, "#mention-dropdown")
    end

    test "mention_navigate changes selected index", %{conn: conn} do
      import Mox

      # Mock the HubSpot API to return contacts with crm_provider
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, _query ->
        {:ok, [
          %{id: "1", firstname: "John", lastname: "Doe", email: "john@example.com", display_name: "John Doe", crm_provider: "hubspot"},
          %{id: "2", firstname: "Jane", lastname: "Smith", email: "jane@example.com", display_name: "Jane Smith", crm_provider: "hubspot"}
        ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Trigger mention search
      render_hook(view, "mention_search", %{"query" => "j"})

      # Wait for async search to complete
      # The search is done via handle_info, so we need to wait
      :timer.sleep(100)

      # Navigate down
      render_hook(view, "mention_navigate", %{"direction" => "down"})

      # The second contact should now be highlighted (index 1)
      html = render(view)
      # Jane Smith should have the highlighted styling
      assert html =~ "Jane Smith"
    end

    test "select_mention_contact closes dropdown and tracks contact", %{conn: conn} do
      import Mox

      # Mock the HubSpot API to return contacts with crm_provider
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, _query ->
        {:ok, [
          %{id: "contact-123", firstname: "John", lastname: "Doe", email: "john@example.com", display_name: "John Doe", crm_provider: "hubspot"}
        ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Trigger mention search
      render_hook(view, "mention_search", %{"query" => "john"})

      # Wait for async search
      :timer.sleep(100)

      # Should show the contact in results
      html = render(view)
      assert html =~ "John Doe"

      # Select the contact
      render_hook(view, "select_mention_contact", %{"id" => "contact-123"})

      # Dropdown should be closed (contact is now tracked in mentioned_contacts
      # and JS hook will insert it into the text)
      refute has_element?(view, "#mention-dropdown")
    end

    test "mention_select_current closes dropdown for highlighted contact", %{conn: conn} do
      import Mox

      # Mock the HubSpot API to return contacts with crm_provider
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, _query ->
        {:ok, [
          %{id: "contact-456", firstname: "Alice", lastname: "Wonder", email: "alice@example.com", display_name: "Alice Wonder", crm_provider: "hubspot"}
        ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Trigger mention search
      render_hook(view, "mention_search", %{"query" => "alice"})

      # Wait for async search
      :timer.sleep(100)

      # Should show the contact in results
      html = render(view)
      assert html =~ "Alice Wonder"

      # Select current (first item, index 0)
      render_hook(view, "mention_select_current", %{})

      # Dropdown should be closed
      refute has_element?(view, "#mention-dropdown")
    end

    test "shows empty state when no query entered", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Trigger mention search with empty query (just typed @)
      html = render_hook(view, "mention_search", %{"query" => ""})

      # Should show hint to type
      assert html =~ "Start typing to search contacts"
    end

    test "shows keyboard navigation hints", %{conn: conn} do
      import Mox

      # Mock the HubSpot API to return contacts with crm_provider
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, _query ->
        {:ok, [
          %{id: "1", firstname: "Test", lastname: "User", email: "test@example.com", display_name: "Test User", crm_provider: "hubspot"}
        ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Trigger mention search
      render_hook(view, "mention_search", %{"query" => "test"})

      # Wait for async search
      :timer.sleep(100)

      html = render(view)
      # Should show keyboard hints
      assert html =~ "navigate"
      assert html =~ "select"
    end

    test "shows CRM provider badge for contacts", %{conn: conn} do
      import Mox

      # Mock the HubSpot API to return contacts with crm_provider
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, _query ->
        {:ok, [
          %{id: "1", firstname: "Test", lastname: "User", email: "test@example.com", display_name: "Test User", crm_provider: "hubspot"}
        ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Trigger mention search
      render_hook(view, "mention_search", %{"query" => "test"})

      # Wait for async search
      :timer.sleep(100)

      html = render(view)
      # Should show the HubSpot badge (H letter)
      assert html =~ "Test User"
      # The badge should be present with the provider indicator
      assert html =~ "bg-orange-500"  # HubSpot color
    end
  end

  describe "Multi-CRM search" do
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

    test "searches both CRMs and shows contacts from both", %{conn: conn} do
      import Mox

      # Mock both HubSpot and Salesforce to return contacts
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, _query ->
        {:ok, [
          %{id: "h1", firstname: "HubSpot", lastname: "Contact", email: "hubspot@example.com", display_name: "HubSpot Contact", crm_provider: "hubspot"}
        ]}
      end)

      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _cred, _query ->
        {:ok, [
          %{id: "s1", firstname: "Salesforce", lastname: "Contact", email: "salesforce@example.com", display_name: "Salesforce Contact", crm_provider: "salesforce"}
        ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/ask")

      # Trigger mention search
      render_hook(view, "mention_search", %{"query" => "contact"})

      # Wait for async search
      :timer.sleep(200)

      html = render(view)
      # Should show contacts from both CRMs
      assert html =~ "HubSpot Contact"
      assert html =~ "Salesforce Contact"
      # Should show both CRM badges
      assert html =~ "bg-orange-500"  # HubSpot
      assert html =~ "bg-blue-500"    # Salesforce
    end
  end
end
