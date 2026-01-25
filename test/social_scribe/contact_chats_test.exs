defmodule SocialScribe.ContactChatsTest do
  use SocialScribe.DataCase

  import SocialScribe.AccountsFixtures

  alias SocialScribe.ContactChats

  describe "create_contact_chat/1" do
    test "creates a chat with valid attrs" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        provider: "hubspot",
        contact_id: "123",
        contact_name: "John Doe"
      }

      assert {:ok, chat} = ContactChats.create_contact_chat(attrs)
      assert chat.user_id == user.id
      assert chat.provider == "hubspot"
      assert chat.contact_id == "123"
      assert chat.contact_name == "John Doe"
    end

    test "returns error changeset for invalid provider" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        provider: "invalid",
        contact_id: "123",
        contact_name: "John Doe"
      }

      assert {:error, changeset} = ContactChats.create_contact_chat(attrs)
      assert %{provider: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "messages" do
    test "add_message/3 inserts and get_chat_messages/1 returns ordered" do
      user = user_fixture()

      {:ok, chat} =
        ContactChats.create_contact_chat(%{
          user_id: user.id,
          provider: "hubspot",
          contact_id: "123",
          contact_name: "John Doe"
        })

      {:ok, m1} = ContactChats.add_message(chat, "user", "hello")
      {:ok, m2} = ContactChats.add_message(chat, "assistant", "hi")

      messages = ContactChats.get_chat_messages(chat.id)
      assert Enum.map(messages, & &1.id) == [m1.id, m2.id]
      assert Enum.map(messages, & &1.sender) == ["user", "assistant"]
    end

    test "list_chats_for_user/1 returns chats ordered by inserted_at desc" do
      user = user_fixture()

      {:ok, chat1} =
        ContactChats.create_contact_chat(%{
          user_id: user.id,
          provider: "hubspot",
          contact_id: "1",
          contact_name: "First"
        })

      {:ok, chat2} =
        ContactChats.create_contact_chat(%{
          user_id: user.id,
          provider: "hubspot",
          contact_id: "2",
          contact_name: "Second"
        })

      chats = ContactChats.list_chats_for_user(user.id)
      assert Enum.map(chats, & &1.id) == [chat2.id, chat1.id]
    end
  end
end
