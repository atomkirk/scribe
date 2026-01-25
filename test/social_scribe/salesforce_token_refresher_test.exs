defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceTokenRefresher
  alias SocialScribe.Accounts.UserCredential

  describe "token_url/0" do
    test "builds URL from configured instance_url" do
      Application.put_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, instance_url: "https://example.my.salesforce.com")

      assert SalesforceTokenRefresher.token_url() ==
               "https://example.my.salesforce.com/services/oauth2/token"
    end
  end

  describe "ensure_valid_token/1" do
    test "returns {:ok, credential} when token is not near expiry" do
      credential = %UserCredential{expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)}
      assert {:ok, ^credential} = SalesforceTokenRefresher.ensure_valid_token(credential)
    end
  end
end
