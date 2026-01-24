defmodule SocialScribe.ContactChats.ContactChat do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contact_chats" do
    field :provider, :string         # "hubspot" or "salesforce"
    field :contact_id, :string       # ID from CRM
    field :contact_name, :string     # Name to display

    belongs_to :user, SocialScribe.Accounts.User
    has_many :messages, SocialScribe.ContactChats.ContactChatMessage, on_delete: :delete_all

    timestamps()
  end

  def changeset(contact_chat, attrs) do
    contact_chat
    |> cast(attrs, [:provider, :contact_id, :contact_name, :user_id])
    |> validate_required([:provider, :contact_id, :contact_name, :user_id])
    |> validate_inclusion(:provider, ["hubspot", "salesforce"])
  end
end
