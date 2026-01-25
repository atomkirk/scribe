import Config
config :social_scribe, Oban, testing: :manual

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
db_host = System.get_env("DB_HOST") || "localhost"

config :social_scribe, SocialScribe.Repo,
  username: "postgres",
  password: "postgres",
  hostname: db_host,
  database: "social_scribe_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :social_scribe, SocialScribeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9WxuBiSiy5Rn3y6exTd0tdFUdW0WJuANQKsWlNqvHlYSVRs4EZ/EDBUlIW4pa8LH",
  server: false

# In test we don't send emails
config :social_scribe, SocialScribe.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
