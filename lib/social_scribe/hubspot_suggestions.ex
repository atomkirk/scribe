defmodule SocialScribe.HubspotSuggestions do
  @moduledoc """
  HubSpot-specific wrapper for CRM suggestions.

  This module delegates to `SocialScribe.CrmSuggestions` for the actual implementation,
  providing backward compatibility for existing code that uses HubSpot-specific functions.

  For new code, consider using `SocialScribe.CrmSuggestions` directly with "hubspot" as
  the provider argument.
  """

  alias SocialScribe.CrmSuggestions
  alias SocialScribe.Accounts.UserCredential

  @provider "hubspot"

  @doc """
  Generates suggested updates for a HubSpot contact based on a meeting transcript.

  Delegates to `CrmSuggestions.generate_suggestions/4`.
  """
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
    CrmSuggestions.generate_suggestions(credential, contact_id, meeting, @provider)
  end

  @doc """
  Generates suggestions without fetching contact data.

  Delegates to `CrmSuggestions.generate_suggestions_from_meeting/2`.
  """
  def generate_suggestions_from_meeting(meeting) do
    CrmSuggestions.generate_suggestions_from_meeting(meeting, @provider)
  end

  @doc """
  Merges AI suggestions with contact data to show current vs suggested values.

  Delegates to `CrmSuggestions.merge_with_contact/3`.
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    CrmSuggestions.merge_with_contact(suggestions, contact, @provider)
  end
end
