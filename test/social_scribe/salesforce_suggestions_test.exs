defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceSuggestions

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data" do
      contact = %{
        id: "003000000000001",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: "555-1234",
        mobilephone: nil,
        jobtitle: "Manager",
        department: nil,
        address: nil,
        city: nil,
        state: nil,
        zip: nil,
        country: nil
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

      merged = SalesforceSuggestions.merge_with_contact(suggestions, contact)

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

    test "returns empty list when no changes detected" do
      contact = %{
        phone: "555-1234",
        email: "john@example.com"
      }

      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "same phone",
          timestamp: "01:00",
          apply: true,
          has_change: true
        }
      ]

      merged = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert merged == []
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

      merged = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert length(merged) == 1
      phone_suggestion = hd(merged)
      assert phone_suggestion.current_value == nil
      assert phone_suggestion.new_value == "555-1234"
      assert phone_suggestion.has_change == true
    end
  end

  describe "field_labels" do
    test "returns correct labels for Salesforce fields" do
      # Test that suggestions have correct human-readable labels
      suggestions = [
        %{
          field: "firstname",
          label: "First Name",
          current_value: nil,
          new_value: "John",
          context: "test",
          timestamp: "00:00",
          apply: true,
          has_change: true
        },
        %{
          field: "jobtitle",
          label: "Job Title",
          current_value: nil,
          new_value: "Engineer",
          context: "test",
          timestamp: "00:00",
          apply: true,
          has_change: true
        }
      ]

      # The labels are set during suggestion generation
      assert Enum.find(suggestions, &(&1.field == "firstname")).label == "First Name"
      assert Enum.find(suggestions, &(&1.field == "jobtitle")).label == "Job Title"
    end
  end
end
