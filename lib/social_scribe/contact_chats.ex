defmodule SocialScribe.ContactChats do
  @moduledoc """
  The ContactChats context for managing chat conversations about CRM contacts.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo
  alias SocialScribe.ContactChats.ContactChat
  alias SocialScribe.ContactChats.ContactChatMessage

  @doc """
  Creates a new contact chat session.
  """
  def create_contact_chat(attrs \\ %{}) do
    %ContactChat{}
    |> ContactChat.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a contact chat by ID with messages preloaded.
  """
  def get_contact_chat(id) do
    ContactChat
    |> where([c], c.id == ^id)
    |> preload(:messages)
    |> Repo.one()
  end

  def get_contact_chat!(id) do
    ContactChat
    |> where([c], c.id == ^id)
    |> preload(:messages)
    |> Repo.one!()
  end

  @doc """
  Adds a message to a contact chat.
  """
  def add_message(chat, sender, content) do
    %ContactChatMessage{}
    |> ContactChatMessage.changeset(%{
      sender: sender,
      content: content,
      contact_chat_id: chat.id
    })
    |> Repo.insert()
  end

  @doc """
  Gets all messages for a contact chat.
  """
  def get_chat_messages(contact_chat_id) do
    ContactChatMessage
    |> where([m], m.contact_chat_id == ^contact_chat_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all chats for a specific user, ordered by most recent first.
  """
  def list_chats_for_user(user_id) do
    ContactChat
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.inserted_at)
    |> preload(:messages)
    |> Repo.all()
  end

  @doc """
  Deletes a contact chat and all its messages.
  """
  def delete_contact_chat(id) do
    Repo.get(ContactChat, id)
    |> Repo.delete()
  end

  @doc """
  Updates a contact chat.
  """
  def update_contact_chat(%ContactChat{} = chat, attrs) do
    chat
    |> ContactChat.changeset(attrs)
    |> Repo.update()
  end
end
