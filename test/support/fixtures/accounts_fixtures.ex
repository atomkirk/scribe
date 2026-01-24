defmodule SocialScribe.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `SocialScribe.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> SocialScribe.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  @doc """
  Generate a user_credential.
  """
  def user_credential_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || user_fixture().id

    {:ok, user_credential} =
      attrs
      |> Enum.into(%{
        user_id: user_id,
        expires_at: ~U[2025-05-23 15:01:00Z],
        provider: "some provider",
        refresh_token: "some refresh_token",
        token: "some token",
        uid: "some uid #{System.unique_integer([:positive])}",
        email: "some email"
      })
      |> SocialScribe.Accounts.create_user_credential()

    user_credential
  end

  @doc """
  Generate a unique facebook_page_credential facebook_page_id.
  """
  def unique_facebook_page_credential_facebook_page_id,
    do: "some facebook_page_id#{System.unique_integer([:positive])}"

  @doc """
  Generate a hubspot_credential.
  """
  def hubspot_credential_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || user_fixture().id

    {:ok, credential} =
      attrs
      |> Enum.into(%{
        user_id: user_id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        provider: "hubspot",
        refresh_token: "hubspot_refresh_token_#{System.unique_integer([:positive])}",
        token: "hubspot_token_#{System.unique_integer([:positive])}",
        uid: "hub_#{System.unique_integer([:positive])}",
        email: "hubspot_user@example.com"
      })
      |> SocialScribe.Accounts.create_user_credential()

    credential
  end

  @doc """
  Generate a salesforce_credential.
  """
  def salesforce_credential_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || user_fixture().id

    {:ok, credential} =
      attrs
      |> Enum.into(%{
        user_id: user_id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        provider: "salesforce",
        refresh_token: "salesforce_refresh_token_#{System.unique_integer([:positive])}",
        token: "salesforce_token_#{System.unique_integer([:positive])}",
        uid: "https://test.salesforce.com",
        email: "salesforce_user@example.com"
      })
      |> SocialScribe.Accounts.create_user_credential()

    credential
  end

  @doc """
  Generate a facebook_page_credential.
  """
  def facebook_page_credential_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || user_fixture().id

    user_credential_id =
      attrs[:user_credential_id] || user_credential_fixture(%{user_id: user_id}).id

    {:ok, facebook_page_credential} =
      attrs
      |> Enum.into(%{
        category: "some category",
        facebook_page_id: unique_facebook_page_credential_facebook_page_id(),
        page_access_token: "some page_access_token",
        page_name: "some page_name",
        selected: false,
        user_id: user_id,
        user_credential_id: user_credential_id
      })
      |> SocialScribe.Accounts.create_facebook_page_credential()

    facebook_page_credential
  end
end
