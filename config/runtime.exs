import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
#
# For dev: run `source .env && mix phx.server`

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/social_scribe start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
  redirect_uri: System.get_env("GOOGLE_REDIRECT_URI")

config :ueberauth, Ueberauth.Strategy.LinkedIn.OAuth,
  client_id: System.get_env("LINKEDIN_CLIENT_ID"),
  client_secret: System.get_env("LINKEDIN_CLIENT_SECRET"),
  redirect_uri: System.get_env("LINKEDIN_REDIRECT_URI")

config :ueberauth, Ueberauth.Strategy.Facebook.OAuth,
  client_id: System.get_env("FACEBOOK_CLIENT_ID"),
  client_secret: System.get_env("FACEBOOK_CLIENT_SECRET"),
  redirect_uri: System.get_env("FACEBOOK_REDIRECT_URI")

config :social_scribe, :recall_api_key, System.get_env("RECALL_API_KEY")
config :social_scribe, :recall_region, System.get_env("RECALL_REGION")
config :social_scribe, :gemini_api_key, System.get_env("GEMINI_API_KEY")

config :ueberauth, Ueberauth.Strategy.Hubspot.OAuth,
  client_id: System.get_env("HUBSPOT_CLIENT_ID"),
  client_secret: System.get_env("HUBSPOT_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
  client_id: System.get_env("SALESFORCE_CLIENT_ID"),
  client_secret: System.get_env("SALESFORCE_CLIENT_SECRET")

if System.get_env("PHX_SERVER") do
  config :social_scribe, SocialScribeWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Parse DATABASE_URL for Cloud SQL Unix socket connections
  # Format: ecto://user:pass@localhost/db?socket=/cloudsql/project:region:instance
  uri = URI.parse(database_url)
  socket_dir = if uri.query do
    uri.query
    |> URI.decode_query()
    |> Map.get("socket")
  end

  repo_config = if socket_dir do
    # For Cloud SQL socket connections, configure manually (don't use URL with host)
    [userinfo_user, userinfo_pass] = String.split(uri.userinfo || ":", ":")
    database = String.trim_leading(uri.path || "", "/")

    [
      username: userinfo_user,
      password: userinfo_pass,
      database: database,
      socket_dir: socket_dir,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
    ]
  else
    # Standard TCP connection
    [
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      socket_options: maybe_ipv6
    ]
  end

  config :social_scribe, SocialScribe.Repo, repo_config

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :social_scribe, SocialScribeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :ueberauth, Ueberauth.Strategy.Google.OAuth,
    redirect_uri: "https://" <> host <> "/auth/google/callback"

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :social_scribe, SocialScribeWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :social_scribe, SocialScribeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :social_scribe, SocialScribe.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
