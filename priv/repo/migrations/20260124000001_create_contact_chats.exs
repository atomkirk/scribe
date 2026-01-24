defmodule SocialScribe.Repo.Migrations.CreateContactChats do
  use Ecto.Migration

  def change do
    create table(:contact_chats) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false  # "hubspot" or "salesforce"
      add :contact_id, :string, null: false  # ID from CRM
      add :contact_name, :string, null: false  # Display name

      timestamps()
    end

    create index(:contact_chats, [:user_id])
    create index(:contact_chats, [:provider])
  end
end
