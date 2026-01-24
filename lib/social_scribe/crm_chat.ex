defmodule SocialScribe.CRMChat do
  @moduledoc """
  Context for CRM chat functionality.
  Handles asking questions about CRM contacts and managing chat history.
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias SocialScribe.Chat.{ChatConversation, ChatMessage}
  alias SocialScribe.Accounts
  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi
  alias SocialScribe.AIContentGeneratorApi

  @doc """
  Creates a new chat conversation for a user.
  """
  def create_conversation(user, attrs \\ %{}) do
    %ChatConversation{}
    |> ChatConversation.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Gets a conversation by ID.
  """
  def get_conversation!(id) do
    Repo.get!(ChatConversation, id)
    |> Repo.preload(:messages)
  end

  @doc """
  Gets a conversation by ID, ensuring it belongs to the user.
  """
  def get_user_conversation(user, id) do
    Repo.get_by(ChatConversation, id: id, user_id: user.id)
    |> Repo.preload(:messages)
  end

  @doc """
  Lists all conversations for a user, ordered by most recent.
  """
  def list_user_conversations(user) do
    from(c in ChatConversation,
      where: c.user_id == ^user.id,
      order_by: [desc: c.updated_at],
      preload: [messages: ^from(m in ChatMessage, order_by: [asc: m.inserted_at])]
    )
    |> Repo.all()
  end

  @doc """
  Adds a message to a conversation.
  """
  def add_message(conversation, attrs) do
    %ChatMessage{}
    |> ChatMessage.changeset(Map.put(attrs, :conversation_id, conversation.id))
    |> Repo.insert()
  end

  @doc """
  Asks a question about a CRM contact and returns the AI response.

  ## Parameters
    - user: The current user
    - conversation: The chat conversation
    - question: The user's question text
    - contact_id: The CRM contact ID (optional)
    - crm_provider: "hubspot" or "salesforce" (optional, auto-detected if not provided)

  ## Returns
    - {:ok, %{user_message: message, assistant_message: message, sources: list}}
    - {:error, reason}
  """
  def ask_question(user, conversation, question, contact_id \\ nil, crm_provider \\ nil) do
    # Determine which CRM to use
    {provider, credential} = determine_crm_provider(user, crm_provider)

    # Save the user's message
    user_message_attrs = %{
      role: "user",
      content: question,
      contact_id: contact_id,
      crm_provider: provider
    }

    with {:ok, user_message} <- add_message(conversation, user_message_attrs),
         {:ok, contact_data} <- fetch_contact_data(credential, contact_id, provider),
         {:ok, ai_response} <- generate_ai_response(question, contact_data, provider),
         {:ok, assistant_message} <- save_assistant_message(conversation, ai_response, contact_data, provider) do
      # Update conversation title if it's the first message
      maybe_update_conversation_title(conversation, question)

      {:ok, %{
        user_message: user_message,
        assistant_message: assistant_message,
        sources: build_sources(contact_data, provider)
      }}
    end
  end

  @doc """
  Fetches contact data from the appropriate CRM.
  """
  def fetch_contact_data(nil, _contact_id, _provider), do: {:ok, nil}
  def fetch_contact_data(_credential, nil, _provider), do: {:ok, nil}

  def fetch_contact_data(%UserCredential{} = credential, contact_id, "hubspot") do
    HubspotApi.get_contact(credential, contact_id)
  end

  def fetch_contact_data(%UserCredential{} = credential, contact_id, "salesforce") do
    SalesforceApi.get_contact(credential, contact_id)
  end

  def fetch_contact_data(_credential, _contact_id, _provider), do: {:ok, nil}

  @doc """
  Searches for contacts in the connected CRM.
  """
  def search_contacts(user, query, crm_provider \\ nil) do
    {provider, credential} = determine_crm_provider(user, crm_provider)

    case {provider, credential} do
      {nil, _} -> {:error, :no_crm_connected}
      {"hubspot", cred} -> HubspotApi.search_contacts(cred, query)
      {"salesforce", cred} -> SalesforceApi.search_contacts(cred, query)
      _ -> {:error, :unsupported_provider}
    end
  end

  @doc """
  Searches for contacts across all connected CRMs in parallel.
  Returns a merged list of contacts from all CRMs, each tagged with their crm_provider.
  Limits to max 4 CRMs for performance.
  """
  def search_all_crms(user, query) do
    credentials = get_all_crm_credentials(user)

    if Enum.empty?(credentials) do
      {:ok, []}
    else
      # Limit to max 4 CRMs and search in parallel
      contacts =
        credentials
        |> Enum.take(4)
        |> Task.async_stream(
          fn {provider, cred} -> search_single_crm(provider, cred, query) end,
          timeout: 10_000,
          on_timeout: :kill_task
        )
        |> Enum.flat_map(fn
          {:ok, {:ok, contacts}} -> contacts
          {:ok, {:error, _}} -> []
          {:exit, _} -> []
        end)

      {:ok, contacts}
    end
  end

  @doc """
  Gets all connected CRM credentials for a user.
  Returns a list of {provider, credential} tuples.
  """
  def get_all_crm_credentials(user) do
    hubspot = Accounts.get_user_hubspot_credential(user.id)
    salesforce = Accounts.get_user_salesforce_credential(user.id)

    [{"hubspot", hubspot}, {"salesforce", salesforce}]
    |> Enum.reject(fn {_, cred} -> is_nil(cred) end)
  end

  @doc """
  Gets all connected CRM providers for a user.
  Returns a list of provider names (e.g., ["hubspot", "salesforce"]).
  """
  def get_all_connected_crms(user) do
    get_all_crm_credentials(user)
    |> Enum.map(fn {provider, _cred} -> provider end)
  end

  # Search a single CRM for contacts
  defp search_single_crm("hubspot", credential, query) do
    HubspotApi.search_contacts(credential, query)
  end

  defp search_single_crm("salesforce", credential, query) do
    SalesforceApi.search_contacts(credential, query)
  end

  defp search_single_crm(_provider, _credential, _query) do
    {:ok, []}
  end

  @doc """
  Gets the connected CRM provider for a user.
  Returns {provider_name, credential} or {nil, nil} if no CRM is connected.
  """
  def get_connected_crm(user) do
    determine_crm_provider(user, nil)
  end

  # Private functions

  defp determine_crm_provider(user, nil) do
    # Try HubSpot first, then Salesforce
    case Accounts.get_user_hubspot_credential(user.id) do
      %UserCredential{} = cred -> {"hubspot", cred}
      nil ->
        case Accounts.get_user_salesforce_credential(user.id) do
          %UserCredential{} = cred -> {"salesforce", cred}
          nil -> {nil, nil}
        end
    end
  end

  defp determine_crm_provider(user, "hubspot") do
    case Accounts.get_user_hubspot_credential(user.id) do
      %UserCredential{} = cred -> {"hubspot", cred}
      nil -> {nil, nil}
    end
  end

  defp determine_crm_provider(user, "salesforce") do
    case Accounts.get_user_salesforce_credential(user.id) do
      %UserCredential{} = cred -> {"salesforce", cred}
      nil -> {nil, nil}
    end
  end

  defp generate_ai_response(question, contact_data, provider) do
    AIContentGeneratorApi.answer_crm_question(question, contact_data, provider)
  end

  defp save_assistant_message(conversation, ai_response, contact_data, provider) do
    contact_name = if contact_data, do: contact_data[:display_name], else: nil

    attrs = %{
      role: "assistant",
      content: ai_response,
      contact_name: contact_name,
      crm_provider: provider,
      sources: build_sources(contact_data, provider)
    }

    add_message(conversation, attrs)
  end

  defp build_sources(nil, _provider), do: []
  defp build_sources(_contact_data, nil), do: []

  defp build_sources(contact_data, provider) do
    [%{
      type: "crm_contact",
      provider: provider,
      contact_id: contact_data[:id],
      contact_name: contact_data[:display_name]
    }]
  end

  defp maybe_update_conversation_title(conversation, question) do
    if is_nil(conversation.title) or conversation.title == "" do
      # Take first 50 chars of question as title
      title = String.slice(question, 0, 50)
      title = if String.length(question) > 50, do: title <> "...", else: title

      conversation
      |> ChatConversation.changeset(%{title: title})
      |> Repo.update()
    else
      {:ok, conversation}
    end
  end
end
