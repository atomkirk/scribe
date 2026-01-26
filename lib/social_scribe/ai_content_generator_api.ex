defmodule SocialScribe.AIContentGeneratorApi do
  @moduledoc """
  Behaviour for generating AI content for meetings.
  """

  @callback generate_follow_up_email(map()) :: {:ok, String.t()} | {:error, any()}
  @callback generate_automation(map(), map()) :: {:ok, String.t()} | {:error, any()}
  @callback generate_crm_suggestions(map(), String.t()) :: {:ok, list(map())} | {:error, any()}
  @callback answer_crm_question(String.t(), map() | nil, String.t() | nil) ::
              {:ok, String.t()} | {:error, any()}

  def generate_follow_up_email(meeting) do
    impl().generate_follow_up_email(meeting)
  end

  def generate_automation(automation, meeting) do
    impl().generate_automation(automation, meeting)
  end

  @doc """
  Generates CRM contact update suggestions from a meeting transcript.

  ## Parameters
    - meeting: The meeting map containing transcript data
    - crm_provider: The CRM provider identifier ("hubspot", "salesforce", etc.)

  ## Returns
    - {:ok, list(map())} - List of suggestion maps with field, value, context, timestamp
    - {:error, reason} - If generation fails
  """
  def generate_crm_suggestions(meeting, crm_provider) do
    impl().generate_crm_suggestions(meeting, crm_provider)
  end

  # Backward compatibility wrappers - delegate to unified function
  def generate_hubspot_suggestions(meeting) do
    generate_crm_suggestions(meeting, "hubspot")
  end

  def generate_salesforce_suggestions(meeting) do
    generate_crm_suggestions(meeting, "salesforce")
  end

  def answer_crm_question(question, contact_data, crm_provider) do
    impl().answer_crm_question(question, contact_data, crm_provider)
  end

  defp impl do
    Application.get_env(
      :social_scribe,
      :ai_content_generator_api,
      SocialScribe.AIContentGenerator
    )
  end
end
