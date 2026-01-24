defmodule SocialScribe.Repo.Migrations.CreateContactChatMessages do
  use Ecto.Migration

  def change do
    create table(:contact_chat_messages) do
      add :contact_chat_id, references(:contact_chats, on_delete: :delete_all), null: false
      add :sender, :string, null: false  # "user" or "assistant"
      add :content, :text, null: false

      timestamps(updated_at: false)
    end

    create index(:contact_chat_messages, [:contact_chat_id])
  end
end
