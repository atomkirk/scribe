defmodule SocialScribe.Chat.ChatConversation do
  @moduledoc """
  Schema for chat conversations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Accounts.User
  alias SocialScribe.Chat.ChatMessage

  schema "chat_conversations" do
    field :title, :string

    belongs_to :user, User
    has_many :messages, ChatMessage, foreign_key: :conversation_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :user_id])
    |> validate_required([:user_id])
  end
end
