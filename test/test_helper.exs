ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(SocialScribe.Repo, :manual)

# test/test_helper.exs

Mox.defmock(SocialScribe.GoogleCalendarApiMock, for: SocialScribe.GoogleCalendarApi)
Mox.defmock(SocialScribe.TokenRefresherMock, for: SocialScribe.TokenRefresherApi)
Mox.defmock(SocialScribe.RecallApiMock, for: SocialScribe.RecallApi)
Mox.defmock(SocialScribe.AIContentGeneratorMock, for: SocialScribe.AIContentGeneratorApi)
Mox.defmock(SocialScribe.HubspotApiMock, for: SocialScribe.HubspotApiBehaviour)
Mox.defmock(SocialScribe.SalesforceApiMock, for: SocialScribe.SalesforceApiBehaviour)

Application.put_env(:social_scribe, :google_calendar_api, SocialScribe.GoogleCalendarApiMock)
Application.put_env(:social_scribe, :token_refresher_api, SocialScribe.TokenRefresherMock)
Application.put_env(:social_scribe, :recall_api, SocialScribe.RecallApiMock)

Application.put_env(
  :social_scribe,
  :ai_content_generator_api,
  SocialScribe.AIContentGeneratorMock
)

Application.put_env(:social_scribe, :hubspot_api, SocialScribe.HubspotApiMock)
Application.put_env(:social_scribe, :salesforce_api, SocialScribe.SalesforceApiMock)
