defmodule SocialScribe.CrmFieldConfigTest do
  use ExUnit.Case, async: true

  alias SocialScribe.CrmFieldConfig

  describe "extractable_fields/1" do
    test "returns HubSpot fields" do
      fields = CrmFieldConfig.extractable_fields("hubspot")

      assert is_list(fields)
      assert "email" in fields
      assert "phone" in fields
      assert "company" in fields
      assert "jobtitle" in fields
      assert "linkedin_url" in fields
      assert "twitter_handle" in fields
    end

    test "returns Salesforce fields" do
      fields = CrmFieldConfig.extractable_fields("salesforce")

      assert is_list(fields)
      assert "email" in fields
      assert "phone" in fields
      assert "jobtitle" in fields
      assert "department" in fields
      # Salesforce doesn't have company, linkedin_url, twitter_handle by default
      refute "company" in fields
      refute "linkedin_url" in fields
    end

    test "returns empty list for unknown provider" do
      assert CrmFieldConfig.extractable_fields("unknown") == []
    end
  end

  describe "field_labels/1" do
    test "returns HubSpot field labels" do
      labels = CrmFieldConfig.field_labels("hubspot")

      assert is_map(labels)
      assert labels["firstname"] == "First Name"
      assert labels["email"] == "Email"
      assert labels["jobtitle"] == "Job Title"
      assert labels["linkedin_url"] == "LinkedIn"
    end

    test "returns Salesforce field labels" do
      labels = CrmFieldConfig.field_labels("salesforce")

      assert is_map(labels)
      assert labels["firstname"] == "First Name"
      assert labels["email"] == "Email"
      assert labels["jobtitle"] == "Job Title"
      assert labels["department"] == "Department"
      # Salesforce uses "Mailing Street" for address
      assert labels["address"] == "Mailing Street"
    end

    test "returns empty map for unknown provider" do
      assert CrmFieldConfig.field_labels("unknown") == %{}
    end
  end

  describe "field_label/2" do
    test "returns label for known field" do
      assert CrmFieldConfig.field_label("hubspot", "firstname") == "First Name"
      assert CrmFieldConfig.field_label("salesforce", "department") == "Department"
    end

    test "returns field name for unknown field" do
      assert CrmFieldConfig.field_label("hubspot", "custom_field") == "custom_field"
    end
  end

  describe "display_name/1" do
    test "returns proper display names" do
      assert CrmFieldConfig.display_name("hubspot") == "HubSpot"
      assert CrmFieldConfig.display_name("salesforce") == "Salesforce"
    end

    test "capitalizes unknown providers" do
      assert CrmFieldConfig.display_name("zoho") == "Zoho"
    end
  end

  describe "supported_providers/0" do
    test "returns list of supported providers" do
      providers = CrmFieldConfig.supported_providers()

      assert is_list(providers)
      assert "hubspot" in providers
      assert "salesforce" in providers
    end
  end

  describe "supported?/1" do
    test "returns true for supported providers" do
      assert CrmFieldConfig.supported?("hubspot") == true
      assert CrmFieldConfig.supported?("salesforce") == true
    end

    test "returns false for unsupported providers" do
      assert CrmFieldConfig.supported?("zoho") == false
      assert CrmFieldConfig.supported?("unknown") == false
    end
  end
end
