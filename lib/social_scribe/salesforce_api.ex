defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contacts operations.
  Implements automatic token refresh on 401/expired token errors.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @api_version "v59.0"

  @contact_fields [
    "Id",
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "MobilePhone",
    "Title",
    "Department",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry"
  ]

  defp client(access_token) do
    Tesla.client([
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string using SOSL.
  Returns up to 10 matching contacts with basic properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  @impl true
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      instance_url = get_instance_url(cred)
      # Escape special SOSL characters
      escaped_query = escape_sosl_query(query)

      fields = Enum.join(@contact_fields, ", ")
      sosl_query = "FIND {#{escaped_query}} IN ALL FIELDS RETURNING Contact(#{fields}) LIMIT 10"
      encoded_query = URI.encode(sosl_query)
      url = "#{instance_url}/services/data/#{@api_version}/search?q=#{encoded_query}"

      case Tesla.get(client(cred.token), url) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          contacts = parse_search_results(body)
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
  @impl true
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      instance_url = get_instance_url(cred)
      fields = Enum.join(@contact_fields, ",")
      url = "#{instance_url}/services/data/#{@api_version}/sobjects/Contact/#{contact_id}?fields=#{fields}"

      case Tesla.get(client(cred.token), url) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          {:ok, format_contact(body)}

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
  Updates a contact's properties.
  `updates` should be a map of property names to new values.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  @impl true
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      instance_url = get_instance_url(cred)
      url = "#{instance_url}/services/data/#{@api_version}/sobjects/Contact/#{contact_id}"

      # Map our field names to Salesforce field names
      salesforce_updates = map_to_salesforce_fields(updates)

      case Tesla.patch(client(cred.token), url, salesforce_updates) do
        {:ok, %Tesla.Env{status: 204}} ->
          # Salesforce returns 204 No Content on successful update
          # Fetch the updated contact to return it
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
  @impl true
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

  # Get the instance URL from the credential
  # The instance URL is stored in the uid field during OAuth
  defp get_instance_url(%UserCredential{} = credential) do
    case credential do
      %{uid: uid} when is_binary(uid) and uid != "" ->
        # The uid field contains the instance URL from OAuth
        if String.starts_with?(uid, "https://") do
          uid
        else
          # Fallback if uid doesn't contain a full URL
          "https://login.salesforce.com"
        end

      _ ->
        # Fallback to login.salesforce.com for API calls
        "https://login.salesforce.com"
    end
  end

  # Parse SOSL search results
  defp parse_search_results(%{"searchRecords" => records}) when is_list(records) do
    Enum.map(records, &format_contact/1)
  end

  defp parse_search_results(_), do: []

  # Format a Salesforce contact response into a cleaner structure
  defp format_contact(%{"Id" => id} = contact) do
    %{
      id: id,
      firstname: contact["FirstName"],
      lastname: contact["LastName"],
      email: contact["Email"],
      phone: contact["Phone"],
      mobilephone: contact["MobilePhone"],
      jobtitle: contact["Title"],
      department: contact["Department"],
      address: contact["MailingStreet"],
      city: contact["MailingCity"],
      state: contact["MailingState"],
      zip: contact["MailingPostalCode"],
      country: contact["MailingCountry"],
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

  # Map our internal field names to Salesforce field names
  defp map_to_salesforce_fields(updates) do
    field_mapping = %{
      "firstname" => "FirstName",
      "lastname" => "LastName",
      "email" => "Email",
      "phone" => "Phone",
      "mobilephone" => "MobilePhone",
      "jobtitle" => "Title",
      "department" => "Department",
      "address" => "MailingStreet",
      "city" => "MailingCity",
      "state" => "MailingState",
      "zip" => "MailingPostalCode",
      "country" => "MailingCountry"
    }

    Enum.reduce(updates, %{}, fn {key, value}, acc ->
      sf_field = Map.get(field_mapping, to_string(key), to_string(key))
      Map.put(acc, sf_field, value)
    end)
  end

  # Escape special characters in SOSL queries
  defp escape_sosl_query(query) do
    query
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\"", "\\\"")
    |> String.replace("?", "\\?")
    |> String.replace("&", "\\&")
    |> String.replace("|", "\\|")
    |> String.replace("!", "\\!")
    |> String.replace("{", "\\{")
    |> String.replace("}", "\\}")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
    |> String.replace("^", "\\^")
    |> String.replace("~", "\\~")
    |> String.replace("*", "\\*")
    |> String.replace(":", "\\:")
    |> String.replace("+", "\\+")
    |> String.replace("-", "\\-")
  end

  # Wrapper that handles token refresh on auth errors
  # Tries the API call, and if it fails with 401, refreshes token and retries once
  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- SalesforceTokenRefresher.ensure_valid_token(credential) do
      case api_call.(credential) do
        {:error, {:api_error, 401, _body}} ->
          Logger.info("Salesforce token expired, refreshing and retrying...")
          retry_with_fresh_token(credential, api_call)

        {:error, {:api_error, status, body}} when is_list(body) ->
          # Salesforce returns errors as a list
          if is_token_error?(body) do
            Logger.info("Salesforce token error, refreshing and retrying...")
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

  defp is_token_error?(errors) when is_list(errors) do
    Enum.any?(errors, fn error ->
      error_code = error["errorCode"] || ""

      error_code in [
        "INVALID_SESSION_ID",
        "INVALID_AUTH_HEADER",
        "SESSION_EXPIRED"
      ]
    end)
  end

  defp is_token_error?(_), do: false
end
