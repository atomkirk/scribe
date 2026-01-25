defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contacts operations.
  Implements automatic token refresh on 401/expired token errors.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @contact_fields [
    "Id",
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "MobilePhone",
    "Fax",
    "Title",
    "Department",
    "Account.Name",
    "Account.Website",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry",
    "OtherStreet",
    "OtherCity",
    "OtherState",
    "OtherPostalCode",
    "OtherCountry"
  ]

  defp client(instance_url, access_token) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "#{instance_url}/services/data/v60.0"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string using SOQL.
  Returns up to 10 matching contacts with standard properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    instance_url = config[:instance_url]

    with_token_refresh(credential, fn cred ->
      # Build SOQL query - search by name or email
      fields = Enum.join(@contact_fields, ", ")

      soql = """
      SELECT #{fields} FROM Contact
      WHERE FirstName LIKE '%#{sanitize_soql(query)}%'
         OR LastName LIKE '%#{sanitize_soql(query)}%'
         OR Email LIKE '%#{sanitize_soql(query)}%'
      LIMIT 10
      """

      url = "/query?q=#{URI.encode(soql)}"

      case Tesla.get(client(instance_url, cred.token), url) do
        {:ok, %Tesla.Env{status: 200, body: %{"records" => records}}} ->
          contacts = Enum.map(records, &format_contact/1)
          {:ok, contacts}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Gets a single contact by ID with all properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def get_contact(%UserCredential{} = credential, contact_id) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    instance_url = config[:instance_url]

    with_token_refresh(credential, fn cred ->
      fields = Enum.join(@contact_fields, ", ")

      soql = "SELECT #{fields} FROM Contact WHERE Id = '#{sanitize_soql(contact_id)}' LIMIT 1"
      url = "/query?q=#{URI.encode(soql)}"

      case Tesla.get(client(instance_url, cred.token), url) do
        {:ok, %Tesla.Env{status: 200, body: %{"records" => [record]}}} ->
          {:ok, format_contact(record)}

        {:ok, %Tesla.Env{status: 200, body: %{"records" => []}}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Updates a contact's properties.
  `updates` should be a map of field names to new values.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    instance_url = config[:instance_url]

    with_token_refresh(credential, fn cred ->
      url = "/sobjects/Contact/#{contact_id}"

      case Tesla.patch(client(instance_url, cred.token), url, updates) do
        {:ok, %Tesla.Env{status: 204}} ->
          # Salesforce returns 204 No Content on successful update, fetch the updated record
          get_contact(credential, contact_id)

        {:ok, %Tesla.Env{status: 404, body: _body}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Batch updates multiple properties on a contact.
  This is a convenience wrapper around update_contact/3.
  """
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.reduce(%{}, fn update, acc ->
        Map.put(acc, update.field, update.new_value)
      end)

    if map_size(updates_map) > 0 do
      update_contact(credential, contact_id, updates_map)
    else
      {:ok, :no_updates}
    end
  end

  # Format a Salesforce contact response into a cleaner structure
  defp format_contact(%{"Id" => id} = contact) do
    account = contact["Account"] || %{}

    %{
      id: id,
      firstname: contact["FirstName"],
      lastname: contact["LastName"],
      email: contact["Email"],
      phone: contact["Phone"],
      mobilephone: contact["MobilePhone"],
      fax: contact["Fax"],
      company: account["Name"],
      company_website: account["Website"],
      title: contact["Title"],
      department: contact["Department"],
      mailing_street: contact["MailingStreet"],
      mailing_city: contact["MailingCity"],
      mailing_state: contact["MailingState"],
      mailing_postal_code: contact["MailingPostalCode"],
      mailing_country: contact["MailingCountry"],
      other_street: contact["OtherStreet"],
      other_city: contact["OtherCity"],
      other_state: contact["OtherState"],
      other_postal_code: contact["OtherPostalCode"],
      other_country: contact["OtherCountry"],
      display_name: format_display_name(contact)
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(contact) do
    firstname = contact["FirstName"] || ""
    lastname = contact["LastName"] || ""
    email = contact["Email"] || ""

    name = String.trim("#{firstname} #{lastname}")

    if name == "" do
      email
    else
      name
    end
  end

  # Sanitize SOQL query strings to prevent injection
  # This is a basic implementation - in production, use parameterized queries if available
  defp sanitize_soql(input) do
    input
    |> String.replace("'", "\\'")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  # Wrapper that handles token refresh on auth errors
  # Tries the API call, and if it fails with 401, refreshes token and retries once
  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- SalesforceTokenRefresher.ensure_valid_token(credential) do
      case api_call.(credential) do
        {:error, {:api_error, status, body}} when status in [401, 400] ->
          if is_token_error?(body) do
            Logger.info("Salesforce token expired, refreshing and retrying...")
            retry_with_fresh_token(credential, api_call)
          else
            Logger.error("Salesforce API error: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          end

        other ->
          other
      end
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case SalesforceTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed_credential} ->
        case api_call.(refreshed_credential) do
          {:error, {:api_error, status, body}} ->
            Logger.error("Salesforce API error after refresh: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}

          {:error, {:http_error, reason}} ->
            Logger.error("Salesforce HTTP error after refresh: #{inspect(reason)}")
            {:error, {:http_error, reason}}

          success ->
            success
        end

      {:error, refresh_error} ->
        Logger.error("Failed to refresh Salesforce token: #{inspect(refresh_error)}")
        {:error, {:token_refresh_failed, refresh_error}}
    end
  end

  defp is_token_error?(%{"error" => "invalid_grant"}), do: true
  defp is_token_error?(%{"error" => "invalid_request"}), do: true

  defp is_token_error?(%{"message" => msg}) when is_binary(msg) do
    String.contains?(String.downcase(msg), ["token", "expired", "unauthorized", "invalid"])
  end

  defp is_token_error?(_), do: false
end
