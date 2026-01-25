defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  import SocialScribe.AccountsFixtures
  import Mox

  alias SocialScribe.SalesforceSuggestions

  setup :verify_on_exit!

  describe "generate_suggestions_from_meeting/1" do
    test "maps AI suggestions to suggestion structs" do
      meeting = %{id: 1}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn ^meeting ->
        {:ok,
         [
           %{field: "phone", value: "555-1234", context: "said number", timestamp: "01:23"}
         ]}
      end)

      assert {:ok, [s]} = SalesforceSuggestions.generate_suggestions_from_meeting(meeting)
      assert s.field == "phone"
      assert s.new_value == "555-1234"
      assert s.apply == true
      assert s.has_change == true
      assert s.current_value == nil
      assert s.timestamp == "01:23"
    end
  end

  describe "merge_with_contact/2" do
    test "sets current_value from contact and filters no-op changes" do
      suggestions = [
        %{field: "phone", label: "phone", current_value: nil, new_value: "555", context: nil, apply: true, has_change: true}
      ]

      contact = %{phone: "555"}

      assert [] = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      contact2 = %{phone: nil}

      assert [merged] = SalesforceSuggestions.merge_with_contact(suggestions, contact2)
      assert merged.current_value == nil
      assert merged.new_value == "555"
      assert merged.apply == true
      assert merged.has_change == true
    end
  end

  describe "generate_suggestions/3" do
    test "fetches contact and filters suggestions without changes" do
      user = user_fixture()
      credential = user_credential_fixture(%{user_id: user.id, provider: "salesforce"})

      contact = %{id: "sf1", phone: "555"}

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "sf1"
        {:ok, contact}
      end)

      meeting = %{id: 1}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn ^meeting ->
        {:ok,
         [
           %{field: "phone", value: "555", context: "same"},
           %{field: "email", value: "new@example.com", context: "updated"}
         ]}
      end)

      assert {:ok, %{contact: ^contact, suggestions: suggestions}} =
               SalesforceSuggestions.generate_suggestions(credential, "sf1", meeting)

      assert Enum.any?(suggestions, fn s -> s.field == "email" end)
      refute Enum.any?(suggestions, fn s -> s.field == "phone" end)
    end
  end
end
