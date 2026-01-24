defmodule SocialScribe.HubspotApi do
  @moduledoc """
  HubSpot CRM API client for contacts operations.
  Implements automatic token refresh on 401/expired token errors.
  """

  @behaviour SocialScribe.HubspotApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.HubspotTokenRefresher

  require Logger

  @base_url "https://api.hubapi.com"

  @contact_properties [
    "firstname",
    "lastname",
    "email",
    "phone",
    "mobilephone",
    "company",
    "jobtitle",
    "address",
    "city",
    "state",
    "zip",
    "country",
    "website",
    "hs_linkedin_url",
    "twitterhandle"
  ]

  defp client(access_token) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @base_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string.
  Returns up to 10 matching contacts with basic properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      body = %{
        query: query,
        limit: 10,
        properties: @contact_properties
      }

      case Tesla.post(client(cred.token), "/crm/v3/objects/contacts/search", body) do
        {:ok, %Tesla.Env{status: 200, body: %{"results" => results}}} ->
          contacts = Enum.map(results, &format_contact/1)
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
    with_token_refresh(credential, fn cred ->
      properties_param = Enum.join(@contact_properties, ",")
      url = "/crm/v3/objects/contacts/#{contact_id}?properties=#{properties_param}"

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
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      body = %{properties: updates}

      case Tesla.patch(client(cred.token), "/crm/v3/objects/contacts/#{contact_id}", body) do
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

  # Format a HubSpot contact response into a cleaner structure
  defp format_contact(%{"id" => id, "properties" => properties}) do
    %{
      id: id,
      firstname: properties["firstname"],
      lastname: properties["lastname"],
      email: properties["email"],
      phone: properties["phone"],
      mobilephone: properties["mobilephone"],
      company: properties["company"],
      jobtitle: properties["jobtitle"],
      address: properties["address"],
      city: properties["city"],
      state: properties["state"],
      zip: properties["zip"],
      country: properties["country"],
      website: properties["website"],
      linkedin_url: properties["hs_linkedin_url"],
      twitter_handle: properties["twitterhandle"],
      display_name: format_display_name(properties),
      crm_provider: "hubspot"
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(properties) do
    firstname = properties["firstname"] || ""
    lastname = properties["lastname"] || ""
    email = properties["email"] || ""

    name = String.trim("#{firstname} #{lastname}")

    if name == "" do
      email
    else
      name
    end
  end

  # Wrapper that handles token refresh on auth errors
  # Tries the API call, and if it fails with 401 or BAD_CLIENT_ID, refreshes token and retries once
  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- HubspotTokenRefresher.ensure_valid_token(credential) do
      case api_call.(credential) do
        {:error, {:api_error, status, body}} when status in [401, 400] ->
          if is_token_error?(body) do
            Logger.info("HubSpot token expired, refreshing and retrying...")
            retry_with_fresh_token(credential, api_call)
          else
            Logger.error("HubSpot API error: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          end

        other ->
          other
      end
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case HubspotTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed_credential} ->
        case api_call.(refreshed_credential) do
          {:error, {:api_error, status, body}} ->
            Logger.error("HubSpot API error after refresh: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}

          {:error, {:http_error, reason}} ->
            Logger.error("HubSpot HTTP error after refresh: #{inspect(reason)}")
            {:error, {:http_error, reason}}

          success ->
            success
        end

      {:error, refresh_error} ->
        Logger.error("Failed to refresh HubSpot token: #{inspect(refresh_error)}")
        {:error, {:token_refresh_failed, refresh_error}}
    end
  end

  defp is_token_error?(%{"status" => "BAD_CLIENT_ID"}), do: true
  defp is_token_error?(%{"status" => "UNAUTHORIZED"}), do: true
  defp is_token_error?(%{"message" => msg}) when is_binary(msg) do
    String.contains?(String.downcase(msg), ["token", "expired", "unauthorized", "client id"])
  end
  defp is_token_error?(_), do: false
end
