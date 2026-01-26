# Local Development Setup

## Prerequisites

- Elixir 1.14+
- Erlang/OTP 25+
- Node.js 18+ (for asset compilation)
- PostgreSQL 14+ (or use Docker)

## Quick Start

```bash
docker-compose up -d

# 2. Copy env template and fill in your credentials
cp .env.example .env
# Edit .env with your API keys (see docs/ for each service)

# 3. Install deps and setup database
mix setup

# 4. Run the server
source .env && mix phx.server
```

App runs at [http://localhost:4000](http://localhost:4000)

## Database Options

### Option A: Docker (recommended)

The included `docker-compose.yml` runs Postgres on port 5432:

```bash
docker-compose up -d      # start
docker-compose down       # stop
docker-compose down -v    # stop and wipe data
```

### Option B: Local Postgres

If you have Postgres installed locally, update `config/dev.exs`:

```elixir
config :social_scribe, SocialScribe.Repo,
  username: "your_user",
  password: "your_pass",
  hostname: "localhost",
  port: 5432,
  database: "social_scribe_dev"
```

## Environment Variables

Elixir doesn't auto-load `.env` files. Two options:

### Option A: Source before running

```bash
source .env && mix phx.server
```

### Option B: Use direnv (recommended for frequent dev)

```bash
# Install direnv, then:
cp .env .envrc
direnv allow
```

## Common Commands

```bash
mix deps.get          # install dependencies
mix ecto.migrate      # run migrations
mix test              # run tests
mix phx.routes        # list all routes
iex -S mix phx.server # run with interactive shell
```

## Troubleshooting

**Database connection refused**
- Check Postgres is running: `docker-compose ps`
- Verify port 5432 isn't blocked

**OAuth callback errors**
- Ensure redirect URIs in your OAuth apps match exactly what's in `.env`
- For Google: make sure you've enabled the Calendar API (see docs/google.md)

**Missing API errors at runtime**
- Check all required env vars are set: `echo $GOOGLE_CLIENT_ID`
- Make sure you sourced the env file: `source .env`
