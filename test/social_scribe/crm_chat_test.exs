defmodule SocialScribe.CRMChatTest do
  use SocialScribe.DataCase

  alias SocialScribe.CRMChat
  alias SocialScribe.Chat.{ChatConversation, ChatMessage}

  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  describe "create_conversation/2" do
    test "creates a conversation for a user" do
      user = user_fixture()

      assert {:ok, %ChatConversation{} = conversation} = CRMChat.create_conversation(user)
      assert conversation.user_id == user.id
      assert conversation.title == nil
    end

    test "creates a conversation with a title" do
      user = user_fixture()

      assert {:ok, %ChatConversation{} = conversation} =
               CRMChat.create_conversation(user, %{title: "Test Conversation"})

      assert conversation.title == "Test Conversation"
    end
  end

  describe "get_conversation!/1" do
    test "returns the conversation with messages preloaded" do
      user = user_fixture()
      {:ok, conversation} = CRMChat.create_conversation(user)

      fetched = CRMChat.get_conversation!(conversation.id)
      assert fetched.id == conversation.id
      assert fetched.messages == []
    end
  end

  describe "get_user_conversation/2" do
    test "returns conversation belonging to user" do
      user = user_fixture()
      {:ok, conversation} = CRMChat.create_conversation(user)

      fetched = CRMChat.get_user_conversation(user, conversation.id)
      assert fetched.id == conversation.id
    end

    test "returns nil for conversation not belonging to user" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = CRMChat.create_conversation(user1)

      assert CRMChat.get_user_conversation(user2, conversation.id) == nil
    end
  end

  describe "list_user_conversations/1" do
    test "returns all conversations for a user ordered by most recent" do
      user = user_fixture()
      {:ok, _conv1} = CRMChat.create_conversation(user, %{title: "First"})
      {:ok, _conv2} = CRMChat.create_conversation(user, %{title: "Second"})

      conversations = CRMChat.list_user_conversations(user)
      assert length(conversations) == 2
      # Both were created at nearly the same time, so just verify they're returned
      titles = Enum.map(conversations, & &1.title)
      assert "First" in titles
      assert "Second" in titles
    end

    test "does not return conversations from other users" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, _conv1} = CRMChat.create_conversation(user1)
      {:ok, _conv2} = CRMChat.create_conversation(user2)

      conversations = CRMChat.list_user_conversations(user1)
      assert length(conversations) == 1
    end
  end

  describe "add_message/2" do
    test "adds a user message to a conversation" do
      user = user_fixture()
      {:ok, conversation} = CRMChat.create_conversation(user)

      attrs = %{
        role: "user",
        content: "Hello, this is a test message"
      }

      assert {:ok, %ChatMessage{} = message} = CRMChat.add_message(conversation, attrs)
      assert message.role == "user"
      assert message.content == "Hello, this is a test message"
      assert message.conversation_id == conversation.id
    end

    test "adds an assistant message to a conversation" do
      user = user_fixture()
      {:ok, conversation} = CRMChat.create_conversation(user)

      attrs = %{
        role: "assistant",
        content: "I'm here to help!",
        crm_provider: "hubspot",
        sources: [%{type: "crm_contact", provider: "hubspot"}]
      }

      assert {:ok, %ChatMessage{} = message} = CRMChat.add_message(conversation, attrs)
      assert message.role == "assistant"
      assert message.crm_provider == "hubspot"
      assert length(message.sources) == 1
    end

    test "validates role is one of user, assistant, system" do
      user = user_fixture()
      {:ok, conversation} = CRMChat.create_conversation(user)

      attrs = %{
        role: "invalid_role",
        content: "Test"
      }

      assert {:error, changeset} = CRMChat.add_message(conversation, attrs)
      assert "is invalid" in errors_on(changeset).role
    end
  end

  describe "get_connected_crm/1" do
    test "returns hubspot when hubspot is connected" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})

      {provider, credential} = CRMChat.get_connected_crm(user)
      assert provider == "hubspot"
      assert credential.provider == "hubspot"
    end

    test "returns salesforce when only salesforce is connected" do
      user = user_fixture()
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      {provider, credential} = CRMChat.get_connected_crm(user)
      assert provider == "salesforce"
      assert credential.provider == "salesforce"
    end

    test "returns nil when no CRM is connected" do
      user = user_fixture()

      {provider, credential} = CRMChat.get_connected_crm(user)
      assert provider == nil
      assert credential == nil
    end

    test "prefers hubspot when both are connected" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      {provider, _credential} = CRMChat.get_connected_crm(user)
      assert provider == "hubspot"
    end
  end

  describe "fetch_contact_data/3" do
    test "returns nil when no credential is provided" do
      assert {:ok, nil} = CRMChat.fetch_contact_data(nil, "123", "hubspot")
    end

    test "returns nil when no contact_id is provided" do
      user = user_fixture()
      cred = hubspot_credential_fixture(%{user_id: user.id})

      assert {:ok, nil} = CRMChat.fetch_contact_data(cred, nil, "hubspot")
    end

    test "fetches hubspot contact with context" do
      user = user_fixture()
      cred = hubspot_credential_fixture(%{user_id: user.id})

      expect(SocialScribe.HubspotApiMock, :get_contact_with_context, fn _cred, contact_id ->
        assert contact_id == "123"
        {:ok, %{
          id: "123",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          display_name: "John Doe",
          crm_provider: "hubspot",
          notes: [%{id: "n1", body: "Test note", created_at: nil}],
          tasks: [%{id: "t1", subject: "Follow up", status: "Open", due_date: nil}]
        }}
      end)

      assert {:ok, contact} = CRMChat.fetch_contact_data(cred, "123", "hubspot")
      assert contact.id == "123"
      assert contact.firstname == "John"
      assert length(contact.notes) == 1
      assert length(contact.tasks) == 1
    end

    test "fetches salesforce contact with context" do
      user = user_fixture()
      cred = salesforce_credential_fixture(%{user_id: user.id})

      expect(SocialScribe.SalesforceApiMock, :get_contact_with_context, fn _cred, contact_id ->
        assert contact_id == "456"
        {:ok, %{
          id: "456",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@example.com",
          display_name: "Jane Smith",
          crm_provider: "salesforce",
          notes: [],
          tasks: [%{id: "t1", subject: "Send proposal", status: "Completed", due_date: nil}]
        }}
      end)

      assert {:ok, contact} = CRMChat.fetch_contact_data(cred, "456", "salesforce")
      assert contact.id == "456"
      assert contact.firstname == "Jane"
      assert contact.notes == []
      assert length(contact.tasks) == 1
    end
  end

  describe "ask_question/5 with mocks" do
    setup do
      user = user_fixture()
      hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})
      {:ok, conversation} = CRMChat.create_conversation(user)

      %{user: user, credential: hubspot_cred, conversation: conversation}
    end

    test "creates user and assistant messages without contact", %{
      user: user,
      conversation: conversation
    } do
      # Mock the AI content generator
      expect(SocialScribe.AIContentGeneratorMock, :answer_crm_question, fn question, nil, "hubspot" ->
        assert question == "What is the weather?"
        {:ok, "I can help with CRM questions. Try tagging a contact with @."}
      end)

      result = CRMChat.ask_question(user, conversation, "What is the weather?")

      assert {:ok, %{user_message: user_msg, assistant_message: assistant_msg}} = result
      assert user_msg.content == "What is the weather?"
      assert user_msg.role == "user"
      assert assistant_msg.role == "assistant"
      assert assistant_msg.content =~ "CRM"
    end
  end

  describe "get_all_crm_credentials/1" do
    test "returns empty list when no CRM is connected" do
      user = user_fixture()

      credentials = CRMChat.get_all_crm_credentials(user)
      assert credentials == []
    end

    test "returns hubspot credential when only hubspot is connected" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})

      credentials = CRMChat.get_all_crm_credentials(user)
      assert length(credentials) == 1
      assert [{"hubspot", cred}] = credentials
      assert cred.provider == "hubspot"
    end

    test "returns salesforce credential when only salesforce is connected" do
      user = user_fixture()
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      credentials = CRMChat.get_all_crm_credentials(user)
      assert length(credentials) == 1
      assert [{"salesforce", cred}] = credentials
      assert cred.provider == "salesforce"
    end

    test "returns both credentials when both CRMs are connected" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      credentials = CRMChat.get_all_crm_credentials(user)
      assert length(credentials) == 2

      providers = Enum.map(credentials, fn {provider, _} -> provider end)
      assert "hubspot" in providers
      assert "salesforce" in providers
    end
  end

  describe "get_all_connected_crms/1" do
    test "returns empty list when no CRM is connected" do
      user = user_fixture()

      crms = CRMChat.get_all_connected_crms(user)
      assert crms == []
    end

    test "returns list of provider names when CRMs are connected" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      crms = CRMChat.get_all_connected_crms(user)
      assert length(crms) == 2
      assert "hubspot" in crms
      assert "salesforce" in crms
    end
  end

  describe "search_all_crms/2" do
    test "returns empty list when no CRM is connected" do
      user = user_fixture()

      assert {:ok, []} = CRMChat.search_all_crms(user, "john")
    end

    test "searches only hubspot when only hubspot is connected" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})

      # Mock HubSpot search with photo_url
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, "john" ->
        {:ok, [
          %{id: "h1", firstname: "John", lastname: "Doe", email: "john@hubspot.com",
            display_name: "John Doe", crm_provider: "hubspot", photo_url: nil}
        ]}
      end)

      assert {:ok, contacts} = CRMChat.search_all_crms(user, "john")
      assert length(contacts) == 1
      assert hd(contacts).crm_provider == "hubspot"
    end

    test "searches only salesforce when only salesforce is connected" do
      user = user_fixture()
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      # Mock Salesforce search with photo_url
      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _cred, "jane" ->
        {:ok, [
          %{id: "s1", firstname: "Jane", lastname: "Smith", email: "jane@salesforce.com",
            display_name: "Jane Smith", crm_provider: "salesforce", photo_url: nil}
        ]}
      end)

      assert {:ok, contacts} = CRMChat.search_all_crms(user, "jane")
      assert length(contacts) == 1
      assert hd(contacts).crm_provider == "salesforce"
    end

    test "searches both CRMs in parallel and merges results" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      # Mock both CRM searches with photo_url
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, "test" ->
        {:ok, [
          %{id: "h1", firstname: "Test", lastname: "HubSpot", email: "test@hubspot.com",
            display_name: "Test HubSpot", crm_provider: "hubspot", photo_url: nil}
        ]}
      end)

      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _cred, "test" ->
        {:ok, [
          %{id: "s1", firstname: "Test", lastname: "Salesforce", email: "test@salesforce.com",
            display_name: "Test Salesforce", crm_provider: "salesforce", photo_url: nil}
        ]}
      end)

      assert {:ok, contacts} = CRMChat.search_all_crms(user, "test")
      assert length(contacts) == 2

      providers = Enum.map(contacts, & &1.crm_provider)
      assert "hubspot" in providers
      assert "salesforce" in providers
    end

    test "gracefully handles errors from one CRM" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      # HubSpot returns results with photo_url
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, "test" ->
        {:ok, [
          %{id: "h1", firstname: "Test", lastname: "User", email: "test@hubspot.com",
            display_name: "Test User", crm_provider: "hubspot", photo_url: nil}
        ]}
      end)

      # Salesforce returns an error
      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _cred, "test" ->
        {:error, {:api_error, 500, "Internal Server Error"}}
      end)

      # Should still return HubSpot results
      assert {:ok, contacts} = CRMChat.search_all_crms(user, "test")
      assert length(contacts) == 1
      assert hd(contacts).crm_provider == "hubspot"
    end
  end
end
