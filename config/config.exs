# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :social_scribe, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  repo: SocialScribe.Repo,
  queues: [
    default: 10,
    ai_content: 10,
    polling: 5
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"*/2 * * * *", SocialScribe.Workers.BotStatusPoller},
       {"*/5 * * * *", SocialScribe.Workers.HubspotTokenRefresher},
       {"*/5 * * * *", SocialScribe.Workers.SalesforceTokenRefresher}
     ]}
  ]

config :social_scribe,
  ecto_repos: [SocialScribe.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :social_scribe, SocialScribeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SocialScribeWeb.ErrorHTML, json: SocialScribeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SocialScribe.PubSub,
  live_view: [signing_salt: "BoCs15uf"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :social_scribe, SocialScribe.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  social_scribe: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  social_scribe: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth
config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [
         default_scope: "email profile https://www.googleapis.com/auth/calendar.readonly",
         extra_params: [access_type: "offline", prompt: "consent"]
       ]},
    linkedin:
      {Ueberauth.Strategy.LinkedIn, [default_scope: "openid profile email w_member_social"]},
    facebook:
      {Ueberauth.Strategy.Facebook,
       [
         default_scope: "email,public_profile,pages_show_list,pages_manage_posts"
       ]},
    hubspot:
      {Ueberauth.Strategy.Hubspot,
       [
         default_scope: "crm.objects.contacts.read crm.objects.contacts.write oauth"
       ]},
    salesforce:
      {Ueberauth.Strategy.Salesforce,
       [
         default_scope: "api refresh_token"
       ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
