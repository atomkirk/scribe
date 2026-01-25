defmodule SocialScribe.CrmSuggestionsPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SocialScribe.CrmSuggestions

  # Using HubSpot fields for testing - the merge logic is provider-agnostic
  @test_fields [
    "firstname",
    "lastname",
    "email",
    "phone",
    "mobilephone",
    "company",
    "jobtitle",
    "address",
    "city",
    "state",
    "zip",
    "country",
    "website",
    "linkedin_url",
    "twitter_handle"
  ]

  describe "merge_with_contact/3 properties" do
    property "never returns suggestions where new_value equals contact's current value" do
      check all suggestions <- list_of(suggestion_generator(), min_length: 1, max_length: 5),
                contact <- contact_generator() do
        result = CrmSuggestions.merge_with_contact(suggestions, contact, "hubspot")

        for suggestion <- result do
          current_in_contact = get_contact_value(contact, suggestion.field)
          refute suggestion.new_value == current_in_contact,
                 "Suggestion for #{suggestion.field} should have been filtered out: " <>
                   "new_value=#{inspect(suggestion.new_value)}, contact_value=#{inspect(current_in_contact)}"
        end
      end
    end

    property "all returned suggestions have has_change set to true" do
      check all suggestions <- list_of(suggestion_generator(), min_length: 1, max_length: 5),
                contact <- contact_generator() do
        result = CrmSuggestions.merge_with_contact(suggestions, contact, "hubspot")

        for suggestion <- result do
          assert suggestion.has_change == true,
                 "Suggestion for #{suggestion.field} should have has_change: true"
        end
      end
    end

    property "all returned suggestions have apply set to true" do
      check all suggestions <- list_of(suggestion_generator(), min_length: 1, max_length: 5),
                contact <- contact_generator() do
        result = CrmSuggestions.merge_with_contact(suggestions, contact, "hubspot")

        for suggestion <- result do
          assert suggestion.apply == true,
                 "Suggestion for #{suggestion.field} should have apply: true"
        end
      end
    end

    property "output length is always less than or equal to input length" do
      check all suggestions <- list_of(suggestion_generator(), min_length: 0, max_length: 10),
                contact <- contact_generator() do
        result = CrmSuggestions.merge_with_contact(suggestions, contact, "hubspot")

        assert length(result) <= length(suggestions),
               "Output length #{length(result)} should be <= input length #{length(suggestions)}"
      end
    end

    property "current_value in result matches the contact's actual value for that field" do
      check all suggestions <- list_of(suggestion_generator(), min_length: 1, max_length: 5),
                contact <- contact_generator() do
        result = CrmSuggestions.merge_with_contact(suggestions, contact, "hubspot")

        for suggestion <- result do
          expected_current = get_contact_value(contact, suggestion.field)

          assert suggestion.current_value == expected_current,
                 "current_value for #{suggestion.field} should be #{inspect(expected_current)}, " <>
                   "got #{inspect(suggestion.current_value)}"
        end
      end
    end

    property "empty suggestions list returns empty list" do
      check all contact <- contact_generator() do
        result = CrmSuggestions.merge_with_contact([], contact, "hubspot")
        assert result == []
      end
    end
  end

  # Generators

  defp suggestion_generator do
    gen all field <- member_of(@test_fields),
            new_value <- one_of([string(:alphanumeric, min_length: 1, max_length: 50), constant(nil)]),
            context <- string(:alphanumeric, min_length: 5, max_length: 100) do
      %{
        field: field,
        label: field,
        current_value: nil,
        new_value: new_value,
        context: context,
        apply: false,
        has_change: true
      }
    end
  end

  defp contact_generator do
    gen all firstname <- one_of([string(:alphanumeric, min_length: 1, max_length: 20), constant(nil)]),
            lastname <- one_of([string(:alphanumeric, min_length: 1, max_length: 20), constant(nil)]),
            email <- one_of([email_generator(), constant(nil)]),
            phone <- one_of([phone_generator(), constant(nil)]),
            company <- one_of([string(:alphanumeric, min_length: 1, max_length: 30), constant(nil)]) do
      %{
        id: "test_#{:rand.uniform(10000)}",
        firstname: firstname,
        lastname: lastname,
        email: email,
        phone: phone,
        mobilephone: nil,
        company: company,
        jobtitle: nil,
        address: nil,
        city: nil,
        state: nil,
        zip: nil,
        country: nil,
        website: nil,
        linkedin_url: nil,
        twitter_handle: nil,
        display_name: "#{firstname || ""} #{lastname || ""}" |> String.trim()
      }
    end
  end

  defp email_generator do
    gen all local <- string(:alphanumeric, min_length: 3, max_length: 10),
            domain <- string(:alphanumeric, min_length: 3, max_length: 8) do
      "#{local}@#{domain}.com"
    end
  end

  defp phone_generator do
    gen all digits <- string(?0..?9, length: 10) do
      "#{String.slice(digits, 0, 3)}-#{String.slice(digits, 3, 3)}-#{String.slice(digits, 6, 4)}"
    end
  end

  defp get_contact_value(contact, field) do
    field_atom = String.to_existing_atom(field)
    Map.get(contact, field_atom)
  rescue
    ArgumentError -> nil
  end
end
