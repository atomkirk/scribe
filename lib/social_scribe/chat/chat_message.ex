defmodule SocialScribe.Chat.ChatMessage do
  @moduledoc """
  Schema for chat messages.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Chat.ChatConversation

  @roles ~w(user assistant system)

  schema "chat_messages" do
    field :role, :string
    field :content, :string
    field :contact_id, :string
    field :contact_name, :string
    field :crm_provider, :string
    field :sources, {:array, :map}, default: []

    belongs_to :conversation, ChatConversation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :contact_id, :contact_name, :crm_provider, :sources, :conversation_id])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, @roles)
  end
end
