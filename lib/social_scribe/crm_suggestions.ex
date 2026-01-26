defmodule SocialScribe.CrmSuggestions do
  @moduledoc """
  Unified CRM suggestions module that generates and formats contact update suggestions
  by combining AI-extracted data with existing CRM contact information.

  This module works with any supported CRM provider by using the CrmFieldConfig
  for provider-specific field definitions.

  ## Usage

      # Generate suggestions for a specific contact
      CrmSuggestions.generate_suggestions(credential, contact_id, meeting, "hubspot")

      # Generate suggestions without a selected contact
      CrmSuggestions.generate_suggestions_from_meeting(meeting, "salesforce")

      # Merge suggestions with contact data
      CrmSuggestions.merge_with_contact(suggestions, contact, "hubspot")
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.CrmFieldConfig
  alias SocialScribe.Accounts.UserCredential

  @doc """
  Generates suggested updates for a CRM contact based on a meeting transcript.

  ## Parameters
    - credential: The user's CRM credential
    - contact_id: The CRM contact ID
    - meeting: The meeting map containing transcript data
    - crm_provider: The CRM provider identifier ("hubspot", "salesforce", etc.)

  ## Returns
    - {:ok, %{contact: map(), suggestions: list()}} - Contact and formatted suggestions
    - {:error, reason} - If generation fails
  """
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting, crm_provider) do
    case get_crm_api(crm_provider) do
      nil ->
        {:error, :unsupported_provider}

      crm_api ->
        with {:ok, contact} <- crm_api.get_contact(credential, contact_id),
             {:ok, ai_suggestions} <- AIContentGeneratorApi.generate_crm_suggestions(meeting, crm_provider) do
          suggestions = format_suggestions(ai_suggestions, contact, crm_provider)
          {:ok, %{contact: contact, suggestions: suggestions}}
        end
    end
  end

  @doc """
  Generates suggestions without fetching contact data.
  Useful when a contact hasn't been selected yet.

  ## Parameters
    - meeting: The meeting map containing transcript data
    - crm_provider: The CRM provider identifier

  ## Returns
    - {:ok, list()} - List of formatted suggestion maps
    - {:error, reason} - If generation fails
  """
  def generate_suggestions_from_meeting(meeting, crm_provider) do
    case AIContentGeneratorApi.generate_crm_suggestions(meeting, crm_provider) do
      {:ok, ai_suggestions} ->
        suggestions =
          ai_suggestions
          |> Enum.map(fn suggestion ->
            %{
              field: suggestion.field,
              label: CrmFieldConfig.field_label(crm_provider, suggestion.field),
              current_value: nil,
              new_value: suggestion.value,
              context: Map.get(suggestion, :context),
              timestamp: Map.get(suggestion, :timestamp),
              apply: true,
              has_change: true
            }
          end)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Merges AI suggestions with contact data to show current vs suggested values.

  ## Parameters
    - suggestions: List of suggestion maps from generate_suggestions_from_meeting
    - contact: The contact map from the CRM
    - crm_provider: The CRM provider identifier (used for field labels)

  ## Returns
    - List of suggestions with current_value populated and filtered to only show changes
  """
  def merge_with_contact(suggestions, contact, _crm_provider) when is_list(suggestions) do
    suggestions
    |> Enum.map(fn suggestion ->
      current_value = get_contact_field(contact, suggestion.field)

      %{
        suggestion
        | current_value: current_value,
          has_change: current_value != suggestion.new_value,
          apply: true
      }
    end)
    |> Enum.filter(fn s -> s.has_change end)
  end

  # Private functions

  defp format_suggestions(ai_suggestions, contact, crm_provider) do
    ai_suggestions
    |> Enum.map(fn suggestion ->
      field = suggestion.field
      current_value = get_contact_field(contact, field)

      %{
        field: field,
        label: CrmFieldConfig.field_label(crm_provider, field),
        current_value: current_value,
        new_value: suggestion.value,
        context: suggestion.context,
        apply: true,
        has_change: current_value != suggestion.value
      }
    end)
    |> Enum.filter(fn s -> s.has_change end)
  end

  defp get_contact_field(contact, field) when is_map(contact) do
    field_atom = String.to_existing_atom(field)
    Map.get(contact, field_atom)
  rescue
    ArgumentError -> nil
  end

  defp get_contact_field(_, _), do: nil

  defp get_crm_api("hubspot"), do: SocialScribe.HubspotApiBehaviour
  defp get_crm_api("salesforce"), do: SocialScribe.SalesforceApiBehaviour
  defp get_crm_api(_), do: nil
end
