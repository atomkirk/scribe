defmodule SocialScribe.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  def change do
    create table(:chat_conversations) do
      add :title, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chat_conversations, [:user_id])

    create table(:chat_messages) do
      add :role, :string, null: false
      add :content, :text, null: false
      add :contact_id, :string
      add :contact_name, :string
      add :crm_provider, :string
      add :sources, {:array, :map}, default: []
      add :conversation_id, references(:chat_conversations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chat_messages, [:conversation_id])
    create index(:chat_messages, [:role])
  end
end
