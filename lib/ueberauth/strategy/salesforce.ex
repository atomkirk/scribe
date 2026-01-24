defmodule Ueberauth.Strategy.Salesforce do
  @moduledoc """
  Salesforce Strategy for Ueberauth.
  """

  use Ueberauth.Strategy,
    uid_field: :user_id,
    default_scope: "api refresh_token",
    oauth2_module: Ueberauth.Strategy.Salesforce.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @doc """
  Handles initial request for Salesforce authentication.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    opts =
      [scope: scopes, redirect_uri: callback_url(conn)]
      |> with_optional(:prompt, conn)
      |> with_param(:prompt, conn)
      |> with_state_param(conn)

    redirect!(conn, Ueberauth.Strategy.Salesforce.OAuth.authorize_url!(opts))
  end

  @doc """
  Handles the callback from Salesforce.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    opts = [redirect_uri: callback_url(conn)]

    case Ueberauth.Strategy.Salesforce.OAuth.get_access_token([code: code], opts) do
      {:ok, token} ->
        fetch_user(conn, token)

      {:error, {error_code, error_description}} ->
        set_errors!(conn, [error(error_code, error_description)])
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc """
  Cleans up the private area of the connection used for passing the raw Salesforce response around during the callback.
  """
  def handle_cleanup!(conn) do
    conn
    |> put_private(:salesforce_token, nil)
    |> put_private(:salesforce_user, nil)
  end

  @doc """
  Fetches the uid field from the response.
  """
  def uid(conn) do
    conn.private.salesforce_user["user_id"]
  end

  @doc """
  Includes the credentials from the Salesforce response.
  """
  def credentials(conn) do
    token = conn.private.salesforce_token

    %Credentials{
      expires: token.expires_at != nil,
      expires_at: token.expires_at,
      scopes: String.split(token.other_params["scope"] || "", " "),
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: token.token_type,
      other: %{
        instance_url: token.other_params["instance_url"],
        id: token.other_params["id"]
      }
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.salesforce_user

    %Info{
      email: user["email"],
      name: user["display_name"],
      first_name: user["first_name"],
      last_name: user["last_name"],
      nickname: user["nick_name"],
      image: user["photos"]["picture"]
    }
  end

  @doc """
  Stores the raw information obtained from the Salesforce callback.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.salesforce_token,
        user: conn.private.salesforce_user
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :salesforce_token, token)

    # The identity URL is returned in the token response as "id"
    identity_url = token.other_params["id"]

    case Ueberauth.Strategy.Salesforce.OAuth.get_user_info(token.access_token, identity_url) do
      {:ok, user} ->
        put_private(conn, :salesforce_user, user)

      {:error, reason} ->
        set_errors!(conn, [error("user_info_error", reason)])
    end
  end

  defp with_param(opts, key, conn) do
    if value = conn.params[to_string(key)], do: Keyword.put(opts, key, value), else: opts
  end

  defp with_optional(opts, key, conn) do
    if option(conn, key), do: Keyword.put(opts, key, option(conn, key)), else: opts
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end
end
