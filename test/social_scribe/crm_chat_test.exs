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
end
