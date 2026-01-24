defmodule SocialScribe.ContactChats.ContactChatMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contact_chat_messages" do
    field :sender, :string           # "user" or "assistant"
    field :content, :string          # The message text

    belongs_to :contact_chat, SocialScribe.ContactChats.ContactChat

    timestamps(updated_at: false)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:sender, :content, :contact_chat_id])
    |> validate_required([:sender, :content, :contact_chat_id])
    |> validate_inclusion(:sender, ["user", "assistant"])
  end
end
