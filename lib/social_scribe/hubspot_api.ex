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

  @doc """
  Gets notes associated with a contact.
  Uses HubSpot's associations API to find linked notes, then fetches their details.
  Returns up to 10 most recent notes.
  """
  def get_contact_notes(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      assoc_body = %{inputs: [%{id: contact_id}]}

      case Tesla.post(client(cred.token), "/crm/v3/associations/contact/note/batch/read", assoc_body) do
        {:ok, %Tesla.Env{status: 200, body: %{"results" => results}}} ->
          note_ids =
            results
            |> List.first(%{})
            |> Map.get("to", [])
            |> Enum.map(& &1["id"])
            |> Enum.take(10)

          if Enum.empty?(note_ids) do
            {:ok, []}
          else
            fetch_notes_by_ids(cred, note_ids)
          end

        {:ok, %Tesla.Env{status: 200, body: _}} ->
          {:ok, []}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Gets recent tasks associated with a contact.
  Uses HubSpot's associations API to find linked tasks, then fetches their details.
  Returns up to 5 most recent tasks.
  """
  def get_contact_tasks(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      assoc_body = %{inputs: [%{id: contact_id}]}

      case Tesla.post(client(cred.token), "/crm/v3/associations/contact/task/batch/read", assoc_body) do
        {:ok, %Tesla.Env{status: 200, body: %{"results" => results}}} ->
          task_ids =
            results
            |> List.first(%{})
            |> Map.get("to", [])
            |> Enum.map(& &1["id"])
            |> Enum.take(5)

          if Enum.empty?(task_ids) do
            {:ok, []}
          else
            fetch_tasks_by_ids(cred, task_ids)
          end

        {:ok, %Tesla.Env{status: 200, body: _}} ->
          {:ok, []}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Gets a contact with additional context including notes and tasks.
  If notes or tasks fail to fetch, returns the contact with empty arrays.
  """
  def get_contact_with_context(%UserCredential{} = credential, contact_id) do
    with {:ok, contact} <- get_contact(credential, contact_id) do
      notes =
        case get_contact_notes(credential, contact_id) do
          {:ok, n} -> n
          {:error, _} -> []
        end

      tasks =
        case get_contact_tasks(credential, contact_id) do
          {:ok, t} -> t
          {:error, _} -> []
        end

      {:ok, Map.merge(contact, %{notes: notes, tasks: tasks})}
    end
  end

  # Fetch note details by IDs
  defp fetch_notes_by_ids(cred, note_ids) do
    notes_body = %{
      inputs: Enum.map(note_ids, &%{id: &1}),
      properties: ["hs_note_body", "hs_timestamp", "hubspot_owner_id", "hs_createdate"]
    }

    case Tesla.post(client(cred.token), "/crm/v3/objects/notes/batch/read", notes_body) do
      {:ok, %Tesla.Env{status: 200, body: %{"results" => notes}}} ->
        formatted_notes =
          notes
          |> Enum.map(&format_note/1)
          |> Enum.reject(&is_nil/1)

        {:ok, formatted_notes}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  # Fetch task details by IDs
  defp fetch_tasks_by_ids(cred, task_ids) do
    tasks_body = %{
      inputs: Enum.map(task_ids, &%{id: &1}),
      properties: ["hs_task_subject", "hs_task_body", "hs_task_status", "hs_task_priority", "hs_timestamp", "hs_createdate"]
    }

    case Tesla.post(client(cred.token), "/crm/v3/objects/tasks/batch/read", tasks_body) do
      {:ok, %Tesla.Env{status: 200, body: %{"results" => tasks}}} ->
        formatted_tasks =
          tasks
          |> Enum.map(&format_task/1)
          |> Enum.reject(&is_nil/1)

        {:ok, formatted_tasks}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
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

  # Format a HubSpot note response
  defp format_note(%{"id" => id, "properties" => properties}) do
    %{
      id: id,
      body: properties["hs_note_body"],
      created_at: parse_hubspot_timestamp(properties["hs_createdate"] || properties["hs_timestamp"]),
      owner_id: properties["hubspot_owner_id"]
    }
  end

  defp format_note(_), do: nil

  # Format a HubSpot task response
  defp format_task(%{"id" => id, "properties" => properties}) do
    %{
      id: id,
      subject: properties["hs_task_subject"],
      description: properties["hs_task_body"],
      status: properties["hs_task_status"],
      priority: properties["hs_task_priority"],
      due_date: parse_hubspot_timestamp(properties["hs_timestamp"]),
      created_at: parse_hubspot_timestamp(properties["hs_createdate"])
    }
  end

  defp format_task(_), do: nil

  # Parse HubSpot timestamp (milliseconds since epoch or ISO string)
  defp parse_hubspot_timestamp(nil), do: nil

  defp parse_hubspot_timestamp(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(div(timestamp, 1000)) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

  defp parse_hubspot_timestamp(timestamp) when is_binary(timestamp) do
    case Integer.parse(timestamp) do
      {ms, ""} -> parse_hubspot_timestamp(ms)
      _ ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, datetime, _offset} -> datetime
          _ -> timestamp
        end
    end
  end

  defp parse_hubspot_timestamp(_), do: nil

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

  # Handles token refresh on auth errors
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
