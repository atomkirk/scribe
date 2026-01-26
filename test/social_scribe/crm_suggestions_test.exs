defmodule SocialScribe.CrmSuggestionsTest do
  use SocialScribe.DataCase

  alias SocialScribe.CrmSuggestions

  describe "merge_with_contact/3" do
    test "merges suggestions with contact data for hubspot" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "company",
          label: "Company",
          current_value: nil,
          new_value: "Acme Corp",
          context: "Works at Acme",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        phone: nil,
        company: "Acme Corp",
        email: "test@example.com"
      }

      result = CrmSuggestions.merge_with_contact(suggestions, contact, "hubspot")

      # Only phone should remain since company already matches
      assert length(result) == 1
      assert hd(result).field == "phone"
      assert hd(result).new_value == "555-1234"
      assert hd(result).apply == true
    end

    test "merges suggestions with contact data for salesforce" do
      contact = %{
        id: "003000000000001",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: "555-1234"
      }

      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-9999",
          context: "mentioned new phone",
          timestamp: "01:23",
          apply: true,
          has_change: true
        },
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "john@example.com",
          context: "mentioned email",
          timestamp: "02:00",
          apply: true,
          has_change: true
        }
      ]

      merged = CrmSuggestions.merge_with_contact(suggestions, contact, "salesforce")

      # Phone suggestion should remain (different value)
      phone_suggestion = Enum.find(merged, &(&1.field == "phone"))
      assert phone_suggestion != nil
      assert phone_suggestion.current_value == "555-1234"
      assert phone_suggestion.new_value == "555-9999"
      assert phone_suggestion.has_change == true

      # Email suggestion should be filtered out (same value)
      email_suggestion = Enum.find(merged, &(&1.field == "email"))
      assert email_suggestion == nil
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        email: "test@example.com"
      }

      result = CrmSuggestions.merge_with_contact(suggestions, contact, "hubspot")

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{id: "123", email: "test@example.com"}

      result = CrmSuggestions.merge_with_contact([], contact, "salesforce")

      assert result == []
    end

    test "handles nil contact fields" do
      contact = %{
        phone: nil,
        email: nil
      }

      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "new phone",
          timestamp: "01:00",
          apply: true,
          has_change: true
        }
      ]

      merged = CrmSuggestions.merge_with_contact(suggestions, contact, "hubspot")

      assert length(merged) == 1
      phone_suggestion = hd(merged)
      assert phone_suggestion.current_value == nil
      assert phone_suggestion.new_value == "555-1234"
      assert phone_suggestion.has_change == true
    end
  end
end
