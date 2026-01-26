defmodule SocialScribe.Workers.SalesforceTokenRefresher do
  @moduledoc """
  Oban worker that proactively refreshes Salesforce OAuth tokens before they expire.
  Runs every 5 minutes and refreshes tokens expiring within 10 minutes.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias SocialScribe.Repo
  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  import Ecto.Query

  require Logger

  @refresh_threshold_minutes 10

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Running proactive Salesforce token refresh check...")

    expiring_credentials = get_expiring_salesforce_credentials()

    case expiring_credentials do
      [] ->
        Logger.debug("No Salesforce tokens expiring soon")
        :ok

      credentials ->
        Logger.info("Found #{length(credentials)} Salesforce token(s) expiring soon, refreshing...")
        refresh_all(credentials)
    end
  end

  defp get_expiring_salesforce_credentials do
    threshold = DateTime.add(DateTime.utc_now(), @refresh_threshold_minutes, :minute)

    from(c in UserCredential,
      where: c.provider == "salesforce",
      where: c.expires_at < ^threshold,
      where: not is_nil(c.refresh_token)
    )
    |> Repo.all()
  end

  defp refresh_all(credentials) do
    results =
      Enum.map(credentials, fn credential ->
        case SalesforceTokenRefresher.refresh_credential(credential) do
          {:ok, _updated} ->
            Logger.info("Proactively refreshed Salesforce token for credential #{credential.id}")
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to proactively refresh Salesforce token for credential #{credential.id}: #{inspect(reason)}"
            )

            {:error, credential.id, reason}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if Enum.empty?(errors) do
      :ok
    else
      # Return ok anyway - we don't want to retry the whole batch
      # Individual failures are logged
      :ok
    end
  end
end
