defmodule Ueberauth.Strategy.Salesforce.OAuth do
  @moduledoc """
  OAuth2 for Salesforce.

  Add `client_id`, `client_secret`, `redirect_uri`, and `instance_url` to your configuration:

      config :ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
        client_id: System.get_env("SALESFORCE_CLIENT_ID"),
        client_secret: System.get_env("SALESFORCE_CLIENT_SECRET"),
        redirect_uri: System.get_env("SALESFORCE_REDIRECT_URI"),
        instance_url: System.get_env("SALESFORCE_INSTANCE_URL")
  """

  use OAuth2.Strategy

  @defaults [
    strategy: __MODULE__,
    authorize_url: "/services/oauth2/authorize",
    token_url: "/services/oauth2/token"
  ]

  @doc """
  Construct a client for requests to Salesforce.

  This will be setup automatically for you in `Ueberauth.Strategy.Salesforce`.

  These options are only useful for usage outside the normal callback phase of Ueberauth.
  """
  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__, [])

    instance_url = config[:instance_url] || "https://orgfarm-d043c8acd2-dev-ed.develop.my.salesforce-setup.com"

    opts =
      @defaults
      |> Keyword.merge([site: instance_url])
      |> Keyword.merge(config)
      |> Keyword.merge(opts)

    json_library = Ueberauth.json_library()

    OAuth2.Client.new(opts)
    |> OAuth2.Client.put_serializer("application/json", json_library)
  end

  @doc """
  Provides the authorize url for the request phase of Ueberauth.
  """
  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client()
    |> OAuth2.Client.authorize_url!(params)
  end

  @doc """
  Fetches an access token from the Salesforce token endpoint.
  """
  def get_access_token(params \\ [], opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__, [])
    instance_url = config[:instance_url] || "https://login.salesforce.com"

    # Salesforce requires client_id and client_secret in the body
    params =
      params
      |> Keyword.put(:client_id, config[:client_id])
      |> Keyword.put(:client_secret, config[:client_secret])

    case opts |> client() |> OAuth2.Client.get_token(params) do
      {:ok, %OAuth2.Client{token: %OAuth2.AccessToken{} = token}} ->
        # Preserve instance_url in other_params for later use
        token = %{token | other_params: Map.put(token.other_params, "instance_url", instance_url)}
        {:ok, token}

      {:ok, %OAuth2.Client{token: nil}} ->
        {:error, {"no_token", "No token returned from Salesforce"}}

      {:error, %OAuth2.Response{body: %{"error" => error, "error_description" => description}}} ->
        {:error, {error, description}}

      {:error, %OAuth2.Response{body: %{"message" => message, "status" => status}}} ->
        {:error, {status, message}}

      {:error, %OAuth2.Error{reason: reason}} ->
        {:error, {"oauth2_error", to_string(reason)}}
    end
  end

  @doc """
  Fetches user info from Salesforce to get user_id and email.
  """
  def get_token_info(access_token, instance_url) do
    url = "#{instance_url}/services/oauth2/userinfo"

    case Tesla.get(http_client(access_token), url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Failed to get token info: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  defp http_client(access_token) do
    Tesla.client([
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{access_token}"}]},
      Tesla.Middleware.JSON
    ])
  end

  # OAuth2.Strategy callbacks

  @impl OAuth2.Strategy
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  @impl OAuth2.Strategy
  def get_token(client, params, headers) do
    client
    |> put_param(:grant_type, "authorization_code")
    |> put_header("Content-Type", "application/x-www-form-urlencoded")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
