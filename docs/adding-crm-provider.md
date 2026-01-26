# Adding a New CRM Provider

This guide walks through integrating a new CRM provider (e.g., Pipedrive, Zoho, etc.) into the application.

## Overview

Adding a CRM provider requires implementing several components that follow established patterns. Use HubSpot and Salesforce as reference implementations.

### Files to Create

| Component | Path |
|-----------|------|
| OAuth Strategy | `lib/ueberauth/strategy/<provider>.ex` |
| OAuth Module | `lib/ueberauth/strategy/<provider>/oauth.ex` |
| API Behaviour | `lib/social_scribe/<provider>_api_behaviour.ex` |
| API Implementation | `lib/social_scribe/<provider>_api.ex` |
| Token Refresher | `lib/social_scribe/workers/<provider>_token_refresher.ex` |

### Files to Modify

| File | Changes |
|------|---------|
| `config/config.exs` | Add Ueberauth provider config, Oban cron job |
| `config/runtime.exs` | Add client ID/secret env vars |
| `lib/social_scribe/crm_field_config.ex` | Add field definitions |
| `lib/social_scribe/crm_suggestions.ex` | Add API mapping |
| `lib/social_scribe_web/controllers/auth_controller.ex` | Add OAuth callback |
| `lib/social_scribe/accounts.ex` | Add credential creation function |
| `lib/social_scribe_web/live/meeting_live/crm_modal_component.ex` | Add UI config |

---

## Step 1: Ueberauth OAuth Strategy

Create the OAuth strategy for authentication.

### 1a. Create the OAuth Module

Create `lib/ueberauth/strategy/<provider>/oauth.ex`:

```elixir
defmodule Ueberauth.Strategy.YourProvider.OAuth do
  use OAuth2.Strategy

  @defaults [
    strategy: __MODULE__,
    site: "https://api.yourprovider.com",
    authorize_url: "https://yourprovider.com/oauth/authorize",
    token_url: "https://api.yourprovider.com/oauth/token"
  ]

  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__, [])

    opts =
      @defaults
      |> Keyword.merge(config)
      |> Keyword.merge(opts)

    OAuth2.Client.new(opts)
  end

  def authorize_url!(params \\ []) do
    OAuth2.Client.authorize_url!(client(), params)
  end

  def get_access_token(params \\ [], opts \\ []) do
    case OAuth2.Client.get_token(client(opts), params) do
      {:ok, %OAuth2.Client{token: token}} -> {:ok, token}
      {:error, %OAuth2.Response{body: %{"error" => error, "error_description" => desc}}} ->
        {:error, {error, desc}}
      {:error, error} -> {:error, error}
    end
  end

  # OAuth2.Strategy callbacks
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_header("Accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
```

### 1b. Create the Strategy Module

Create `lib/ueberauth/strategy/<provider>.ex`:

```elixir
defmodule Ueberauth.Strategy.YourProvider do
  use Ueberauth.Strategy,
    uid_field: :id,
    default_scope: "contacts.read contacts.write",
    oauth2_module: Ueberauth.Strategy.YourProvider.OAuth

  alias Ueberauth.Auth.{Info, Credentials, Extra}

  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)
    opts = [scope: scopes, redirect_uri: callback_url(conn)]
    redirect!(conn, Ueberauth.Strategy.YourProvider.OAuth.authorize_url!(opts))
  end

  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    opts = [redirect_uri: callback_url(conn)]
    case Ueberauth.Strategy.YourProvider.OAuth.get_access_token([code: code], opts) do
      {:ok, token} -> fetch_user(conn, token)
      {:error, {error_code, error_description}} ->
        set_errors!(conn, [error(error_code, error_description)])
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  def handle_cleanup!(conn) do
    conn
    |> put_private(:yourprovider_token, nil)
    |> put_private(:yourprovider_user, nil)
  end

  def uid(conn), do: conn.private.yourprovider_user["id"]

  def credentials(conn) do
    token = conn.private.yourprovider_token
    %Credentials{
      expires: true,
      expires_at: token.expires_at,
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: token.token_type
    }
  end

  def info(conn) do
    user = conn.private.yourprovider_user
    %Info{email: user["email"], name: user["name"]}
  end

  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.yourprovider_token,
        user: conn.private.yourprovider_user
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :yourprovider_token, token)
    # Fetch user info from provider's API
    # put_private(conn, :yourprovider_user, user)
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end
end
```

---

## Step 2: API Behaviour & Implementation

### 2a. Create the Behaviour

Create `lib/social_scribe/<provider>_api_behaviour.ex`:

```elixir
defmodule SocialScribe.YourProviderApiBehaviour do
  @moduledoc """
  Behaviour for YourProvider API client.
  Allows using a real client in production and a mock in tests.
  """

  alias SocialScribe.Accounts.UserCredential

  @callback search_contacts(credential :: UserCredential.t(), query :: String.t()) ::
              {:ok, list(map())} | {:error, any()}

  @callback get_contact(credential :: UserCredential.t(), contact_id :: String.t()) ::
              {:ok, map()} | {:error, any()}

  @callback update_contact(
              credential :: UserCredential.t(),
              contact_id :: String.t(),
              updates :: map()
            ) :: {:ok, map()} | {:error, any()}

  @callback apply_updates(
              credential :: UserCredential.t(),
              contact_id :: String.t(),
              updates_list :: list(map())
            ) :: {:ok, map() | :no_updates} | {:error, any()}

  @callback get_contact_notes(credential :: UserCredential.t(), contact_id :: String.t()) ::
              {:ok, list(map())} | {:error, any()}

  @callback get_contact_tasks(credential :: UserCredential.t(), contact_id :: String.t()) ::
              {:ok, list(map())} | {:error, any()}

  @callback get_contact_with_context(credential :: UserCredential.t(), contact_id :: String.t()) ::
              {:ok, map()} | {:error, any()}

  # Delegating functions
  def search_contacts(credential, query), do: impl().search_contacts(credential, query)
  def get_contact(credential, contact_id), do: impl().get_contact(credential, contact_id)
  def update_contact(credential, contact_id, updates), do: impl().update_contact(credential, contact_id, updates)
  def apply_updates(credential, contact_id, updates_list), do: impl().apply_updates(credential, contact_id, updates_list)
  def get_contact_notes(credential, contact_id), do: impl().get_contact_notes(credential, contact_id)
  def get_contact_tasks(credential, contact_id), do: impl().get_contact_tasks(credential, contact_id)
  def get_contact_with_context(credential, contact_id), do: impl().get_contact_with_context(credential, contact_id)

  defp impl do
    Application.get_env(:social_scribe, :yourprovider_api, SocialScribe.YourProviderApi)
  end
end
```

### 2b. Implement the API

Create `lib/social_scribe/<provider>_api.ex` implementing the behaviour with actual HTTP calls.

Key requirements:
- Use Tesla for HTTP client
- Normalize contact data to a consistent structure with atom keys
- Handle token in `credential.token`
- Return `{:ok, result}` or `{:error, reason}` tuples

---

## Step 3: Token Refresher Worker

Create `lib/social_scribe/workers/<provider>_token_refresher.ex`:

```elixir
defmodule SocialScribe.Workers.YourProviderTokenRefresher do
  @moduledoc """
  Oban worker that refreshes YourProvider tokens before expiry.
  """

  use Oban.Worker, queue: :default

  alias SocialScribe.Accounts
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    # Get credentials expiring within 10 minutes
    credentials = Accounts.list_expiring_credentials("yourprovider", 10)

    Enum.each(credentials, fn credential ->
      case refresh_token(credential) do
        {:ok, new_token_data} ->
          Accounts.update_credential_tokens(credential, new_token_data)
        {:error, reason} ->
          Logger.error("Failed to refresh YourProvider token: #{inspect(reason)}")
      end
    end)

    :ok
  end

  defp refresh_token(credential) do
    # Implement token refresh logic
    # POST to provider's token endpoint with refresh_token grant
  end
end
```

---

## Step 4: Update CRM Field Config

Edit `lib/social_scribe/crm_field_config.ex`:

```elixir
# Add extractable_fields clause
def extractable_fields("yourprovider") do
  ~w(firstname lastname email phone company jobtitle)
end

# Add field_labels clause
def field_labels("yourprovider") do
  %{
    "firstname" => "First Name",
    "lastname" => "Last Name",
    "email" => "Email",
    "phone" => "Phone",
    "company" => "Company",
    "jobtitle" => "Job Title"
  }
end

# Add display_name clause
def display_name("yourprovider"), do: "YourProvider"

# Update supported_providers
def supported_providers do
  ["hubspot", "salesforce", "yourprovider"]
end
```

---

## Step 5: Update CRM Suggestions

Edit `lib/social_scribe/crm_suggestions.ex`, add to `get_crm_api/1`:

```elixir
defp get_crm_api("yourprovider"), do: SocialScribe.YourProviderApiBehaviour
```

---

## Step 6: Auth Controller Callback

Edit `lib/social_scribe_web/controllers/auth_controller.ex`, add a callback handler:

```elixir
def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
      "provider" => "yourprovider"
    })
    when not is_nil(user) do
  Logger.info("YourProvider OAuth")

  credential_attrs = %{
    user_id: user.id,
    provider: "yourprovider",
    uid: to_string(auth.uid),
    token: auth.credentials.token,
    refresh_token: auth.credentials.refresh_token,
    expires_at:
      (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
        DateTime.add(DateTime.utc_now(), 3600, :second),
    email: auth.info.email
  }

  case Accounts.find_or_create_yourprovider_credential(user, credential_attrs) do
    {:ok, _credential} ->
      conn
      |> put_flash(:info, "YourProvider account connected successfully!")
      |> redirect(to: ~p"/dashboard/settings")

    {:error, reason} ->
      Logger.error("Failed to save YourProvider credential: #{inspect(reason)}")
      conn
      |> put_flash(:error, "Could not connect YourProvider account.")
      |> redirect(to: ~p"/dashboard/settings")
  end
end
```

---

## Step 7: Accounts Module

Edit `lib/social_scribe/accounts.ex`, add credential creation function:

```elixir
def find_or_create_yourprovider_credential(user, attrs) do
  case Repo.get_by(UserCredential, user_id: user.id, provider: "yourprovider") do
    nil ->
      %UserCredential{}
      |> UserCredential.changeset(attrs)
      |> Repo.insert()

    existing ->
      existing
      |> UserCredential.changeset(attrs)
      |> Repo.update()
  end
end
```

---

## Step 8: Configuration

### 8a. Edit `config/config.exs`

Add Ueberauth provider:

```elixir
config :ueberauth, Ueberauth,
  providers: [
    # ... existing providers ...
    yourprovider:
      {Ueberauth.Strategy.YourProvider,
       [
         default_scope: "contacts.read contacts.write"
       ]}
  ]
```

Add Oban cron job:

```elixir
{Oban.Plugins.Cron,
 crontab: [
   # ... existing jobs ...
   {"*/5 * * * *", SocialScribe.Workers.YourProviderTokenRefresher}
 ]}
```

### 8b. Edit `config/runtime.exs`

Add OAuth credentials:

```elixir
config :ueberauth, Ueberauth.Strategy.YourProvider.OAuth,
  client_id: System.get_env("YOURPROVIDER_CLIENT_ID"),
  client_secret: System.get_env("YOURPROVIDER_CLIENT_SECRET")
```

---

## Step 9: UI Components

### 9a. CRM Modal Component

Edit `lib/social_scribe_web/live/meeting_live/crm_modal_component.ex`, add to `@crm_config`:

```elixir
@crm_config %{
  # ... existing entries ...
  yourprovider: %{
    title: "Update in YourProvider",
    description: "Here are suggested updates to sync with YourProvider based on this",
    button_class: "bg-purple-600 hover:bg-purple-700",  # Choose appropriate color
    info_template: "1 contact, %{count} fields selected to update"
  }
}
```

### 9b. Settings Page

Add a connect button in the user settings LiveView for the new provider.

---

## Step 10: Environment Variables

Add to your `.env` file:

```bash
export YOURPROVIDER_CLIENT_ID=your-client-id
export YOURPROVIDER_CLIENT_SECRET=your-client-secret
```

Document these in a provider-specific setup guide at `docs/yourprovider.md`.

---

## Testing

### Mock the API Behaviour

In `config/test.exs`:

```elixir
config :social_scribe, :yourprovider_api, SocialScribe.YourProviderApiMock
```

Create a mock module using Mox or manual implementation for tests.

### Reference Tests

- `test/social_scribe/hubspot_api_test.exs` - API testing patterns
- `test/social_scribe_web/live/hubspot_modal_test.exs` - LiveView modal tests
- `test/social_scribe_web/live/salesforce_modal_test.exs` - Additional modal patterns

---

## Checklist

- [ ] OAuth strategy and module created
- [ ] API behaviour defined
- [ ] API implementation complete
- [ ] Token refresher worker created
- [ ] `crm_field_config.ex` updated
- [ ] `crm_suggestions.ex` updated
- [ ] Auth controller callback added
- [ ] Accounts credential function added
- [ ] `config.exs` Ueberauth provider added
- [ ] `config.exs` Oban cron job added
- [ ] `runtime.exs` OAuth credentials added
- [ ] CRM modal config added
- [ ] Settings UI connect button added
- [ ] Tests written
- [ ] Provider setup documentation created (`docs/<provider>.md`)
