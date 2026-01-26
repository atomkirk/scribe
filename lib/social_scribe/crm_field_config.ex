defmodule SocialScribe.CrmFieldConfig do
  @moduledoc """
  Centralized configuration for CRM field definitions.

  This module provides a single source of truth for CRM-specific field configurations,
  making it easy to add support for new CRM providers by adding new clauses to each function.

  ## Adding a new CRM provider

  1. Add a new clause to `extractable_fields/1` with the fields that can be extracted
  2. Add a new clause to `field_labels/1` with human-readable labels for each field
  3. Add a new clause to `display_name/1` with the CRM's display name
  4. Add a new clause to `supported_providers/0` to include the new provider
  """

  @doc """
  Returns the list of field names that can be extracted from meeting transcripts
  for the given CRM provider.
  """
  def extractable_fields("hubspot") do
    ~w(firstname lastname email phone mobilephone company jobtitle address city state zip country website linkedin_url twitter_handle)
  end

  def extractable_fields("salesforce") do
    ~w(firstname lastname email phone mobilephone jobtitle department address city state zip country)
  end

  def extractable_fields(_unknown), do: []

  @doc """
  Returns a map of field names to human-readable labels for the given CRM provider.
  """
  def field_labels("hubspot") do
    %{
      "firstname" => "First Name",
      "lastname" => "Last Name",
      "email" => "Email",
      "phone" => "Phone",
      "mobilephone" => "Mobile Phone",
      "company" => "Company",
      "jobtitle" => "Job Title",
      "address" => "Address",
      "city" => "City",
      "state" => "State",
      "zip" => "ZIP Code",
      "country" => "Country",
      "website" => "Website",
      "linkedin_url" => "LinkedIn",
      "twitter_handle" => "Twitter"
    }
  end

  def field_labels("salesforce") do
    %{
      "firstname" => "First Name",
      "lastname" => "Last Name",
      "email" => "Email",
      "phone" => "Phone",
      "mobilephone" => "Mobile Phone",
      "jobtitle" => "Job Title",
      "department" => "Department",
      "address" => "Mailing Street",
      "city" => "City",
      "state" => "State",
      "zip" => "ZIP Code",
      "country" => "Country"
    }
  end

  def field_labels(_unknown), do: %{}

  @doc """
  Returns the human-readable label for a specific field in the given CRM provider.
  Falls back to the field name itself if no label is defined.
  """
  def field_label(provider, field) do
    Map.get(field_labels(provider), field, field)
  end

  @doc """
  Returns the display name for the CRM provider.
  """
  def display_name("hubspot"), do: "HubSpot"
  def display_name("salesforce"), do: "Salesforce"
  def display_name(provider), do: String.capitalize(provider)

  @doc """
  Returns a list of all supported CRM provider identifiers.
  """
  def supported_providers do
    ["hubspot", "salesforce"]
  end

  @doc """
  Checks if a provider is supported.
  """
  def supported?(provider) do
    provider in supported_providers()
  end
end
