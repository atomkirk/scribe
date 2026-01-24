defmodule SocialScribe.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias Ueberauth.Auth

  alias SocialScribe.Accounts.{User, UserToken, UserCredential}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## User Credentials

  @doc """
  Returns the list of user_credentials.

  ## Examples

      iex> list_user_credentials()
      [%UserCredential{}, ...]

  """
  def list_user_credentials do
    Repo.all(UserCredential)
  end

  def list_user_credentials(user, where \\ []) do
    query =
      from c in UserCredential,
        where: c.user_id == ^user.id,
        where: ^where

    Repo.all(query)
  end

  @doc """
  Gets a single user_credential.

  Raises `Ecto.NoResultsError` if the User credential does not exist.

  ## Examples

      iex> get_user_credential!(123)
      %UserCredential{}

      iex> get_user_credential!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user_credential!(id), do: Repo.get!(UserCredential, id)

  def get_user_linkedin_credential(user) do
    Repo.get_by(UserCredential, user_id: user.id, provider: "linkedin")
  end

  @doc """
  Gets a user credential by user, provider, and uid.

  ## Examples

      iex> get_user_credential(user, "google", "google-uid-12345")
      %UserCredential{}

      iex> get_user_credential(user, "google", "google-uid-12345")
      nil
  """
  def get_user_credential(user, provider, uid) do
    Repo.get_by(UserCredential, user_id: user.id, provider: provider, uid: uid)
  end

  def get_user_credential(user, provider) do
    Repo.get_by(UserCredential, user_id: user.id, provider: provider)
  end

  @doc """
  Creates a user_credential.

  ## Examples

      iex> create_user_credential(%{field: value})
      {:ok, %UserCredential{}}

      iex> create_user_credential(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_credential(attrs \\ %{}) do
    %UserCredential{}
    |> UserCredential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user_credential.

  ## Examples

      iex> update_user_credential(user_credential, %{field: new_value})
      {:ok, %UserCredential{}}

      iex> update_user_credential(user_credential, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_credential(%UserCredential{} = user_credential, attrs) do
    user_credential
    |> UserCredential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user_credential.

  ## Examples

      iex> delete_user_credential(user_credential)
      {:ok, %UserCredential{}}

      iex> delete_user_credential(user_credential)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user_credential(%UserCredential{} = user_credential) do
    Repo.delete(user_credential)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user_credential changes.

  ## Examples

      iex> change_user_credential(user_credential)
      %Ecto.Changeset{data: %UserCredential{}}

  """
  def change_user_credential(%UserCredential{} = user_credential, attrs \\ %{}) do
    UserCredential.changeset(user_credential, attrs)
  end

  ## OAuth

  def find_or_create_user_from_oauth(%Auth{} = auth) do
    Repo.transaction(fn ->
      user = find_or_create_user(auth.provider, auth.uid, auth.info.email)

      case find_or_create_user_credential(user, auth) do
        {:ok, _} ->
          user

        {:error, _} ->
          Repo.rollback(:cannot_create_user_credential)
      end
    end)
  end

  defp find_or_create_user(provider, uid, email) do
    case get_user_by_oauth_uid(Atom.to_string(provider), uid) do
      %User{} = user ->
        user

      nil ->
        case get_user_by_email(email) do
          %User{} = user ->
            user

          nil ->
            %User{}
            |> User.oauth_registration_changeset(%{
              email: email
            })
            |> Repo.insert!()
        end
    end
  end

  @doc """
  Finds or creates a user credential for a user.
  """
  def find_or_create_user_credential(user, %Auth{provider: provider} = auth)
      when provider in [:linkedin, :facebook] do
    case get_user_credential(
           user,
           Atom.to_string(auth.provider)
         ) do
      nil ->
        create_user_credential(format_credential_attrs(user, auth))

      %UserCredential{} = credential ->
        update_user_credential(credential, format_credential_attrs(user, auth))
    end
  end

  def find_or_create_user_credential(user, %Auth{} = auth) do
    case get_user_credential(user, Atom.to_string(auth.provider), auth.uid) do
      nil ->
        create_user_credential(format_credential_attrs(user, auth))

      %UserCredential{} = credential ->
        update_user_credential(credential, format_credential_attrs(user, auth))
    end
  end

  @doc """
  Finds or creates a HubSpot credential for a user.
  HubSpot uses a single credential per hub_id (account).
  """
  def find_or_create_hubspot_credential(user, attrs) do
    case get_user_credential(user, "hubspot", attrs.uid) do
      nil ->
        create_user_credential(attrs)

      %UserCredential{} = credential ->
        update_user_credential(credential, attrs)
    end
  end

  @doc """
  Gets the user's HubSpot credential if one exists.
  """
  def get_user_hubspot_credential(user_id) do
    Repo.get_by(UserCredential, user_id: user_id, provider: "hubspot")
  end

  @doc """
  Finds or creates a Salesforce credential for the user.
  """
  def find_or_create_salesforce_credential(user, attrs) do
    case get_user_credential(user, "salesforce", attrs.uid) do
      nil ->
        create_user_credential(attrs)

      %UserCredential{} = credential ->
        update_user_credential(credential, attrs)
    end
  end

  @doc """
  Gets the user's Salesforce credential if one exists.
  """
  def get_user_salesforce_credential(user_id) do
    Repo.get_by(UserCredential, user_id: user_id, provider: "salesforce")
  end

  defp get_user_by_oauth_uid(provider, uid) do
    from(c in UserCredential,
      where: c.provider == ^provider and c.uid == ^uid,
      join: u in assoc(c, :user),
      select: u
    )
    |> Repo.one()
  end

  defp format_credential_attrs(user, %Auth{provider: :linkedin} = auth) do
    %{
      user_id: user.id,
      provider: to_string(auth.provider),
      uid: "urn:li:person:#{auth.extra.raw_info.user["sub"]}",
      token: auth.credentials.token,
      refresh_token: auth.credentials.token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }
  end

  defp format_credential_attrs(user, %Auth{provider: :facebook} = auth) do
    %{
      user_id: user.id,
      provider: to_string(auth.provider),
      uid: auth.uid,
      token: auth.credentials.token,
      refresh_token: auth.credentials.token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }
  end

  defp format_credential_attrs(user, %Auth{credentials: %{refresh_token: nil}} = auth) do
    %{
      user_id: user.id,
      provider: to_string(auth.provider),
      uid: auth.uid,
      token: auth.credentials.token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }
  end

  defp format_credential_attrs(user, %Auth{} = auth) do
    %{
      user_id: user.id,
      provider: to_string(auth.provider),
      uid: auth.uid,
      token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }
  end

  @doc """
  Updates a user credential's tokens.

  ## Examples

      iex> update_credential_tokens(user_credential, %{"access_token" => "new_token", "expires_in" => 3600})
      {:ok, %UserCredential{}}
  """
  def update_credential_tokens(%UserCredential{} = credential, %{
        "access_token" => token,
        "expires_in" => expires_in
      }) do
    credential
    |> UserCredential.changeset(%{
      token: token,
      expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second)
    })
    |> Repo.update()
  end

  alias SocialScribe.Accounts.FacebookPageCredential

  @doc """
  Returns the list of facebook_page_credentials.

  ## Examples

      iex> list_facebook_page_credentials()
      [%FacebookPageCredential{}, ...]

  """
  def list_facebook_page_credentials do
    Repo.all(FacebookPageCredential)
  end

  @doc """
  Gets a single facebook_page_credential.

  Raises `Ecto.NoResultsError` if the Facebook page credential does not exist.

  ## Examples

      iex> get_facebook_page_credential!(123)
      %FacebookPageCredential{}

      iex> get_facebook_page_credential!(456)
      ** (Ecto.NoResultsError)

  """
  def get_facebook_page_credential!(id), do: Repo.get!(FacebookPageCredential, id)

  def get_user_selected_facebook_page_credential(user) do
    Repo.get_by(FacebookPageCredential, user_id: user.id, selected: true)
  end

  @doc """
  Creates a facebook_page_credential.

  ## Examples

      iex> create_facebook_page_credential(%{field: value})
      {:ok, %FacebookPageCredential{}}

      iex> create_facebook_page_credential(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_facebook_page_credential(attrs \\ %{}) do
    %FacebookPageCredential{}
    |> FacebookPageCredential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a facebook_page_credential.

  ## Examples

      iex> update_facebook_page_credential(facebook_page_credential, %{field: new_value})
      {:ok, %FacebookPageCredential{}}

      iex> update_facebook_page_credential(facebook_page_credential, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_facebook_page_credential(%FacebookPageCredential{} = facebook_page_credential, attrs) do
    facebook_page_credential
    |> FacebookPageCredential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a facebook_page_credential.

  ## Examples

      iex> delete_facebook_page_credential(facebook_page_credential)
      {:ok, %FacebookPageCredential{}}

      iex> delete_facebook_page_credential(facebook_page_credential)
      {:error, %Ecto.Changeset{}}

  """
  def delete_facebook_page_credential(%FacebookPageCredential{} = facebook_page_credential) do
    Repo.delete(facebook_page_credential)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking facebook_page_credential changes.

  ## Examples

      iex> change_facebook_page_credential(facebook_page_credential)
      %Ecto.Changeset{data: %FacebookPageCredential{}}

  """
  def change_facebook_page_credential(
        %FacebookPageCredential{} = facebook_page_credential,
        attrs \\ %{}
      ) do
    FacebookPageCredential.changeset(facebook_page_credential, attrs)
  end

  @doc """
  Creates or updates a FacebookPageCredential record.
  `user_credential` is the main Facebook UserCredential record.
  `page_data` is a map like %{id: "page_id", name: "Page Name", page_access_token: "token"}.
  """
  def link_facebook_page(user, user_credential, page_data) do
    attrs = %{
      user_id: user.id,
      user_credential_id: user_credential.id,
      facebook_page_id: page_data.id,
      page_name: page_data.name,
      page_access_token: page_data.page_access_token,
      category: page_data.category
    }

    case get_linked_facebook_page(user, page_data.id) do
      nil ->
        create_facebook_page_credential(attrs)

      existing_credential ->
        update_facebook_page_credential(existing_credential, attrs)
    end
  end

  @doc "Gets all linked Facebook Pages for a user."
  def list_linked_facebook_pages(user) do
    Repo.all(from fpc in FacebookPageCredential, where: fpc.user_id == ^user.id)
  end

  @doc "Gets a specific linked Facebook Page for a user."
  def get_linked_facebook_page(user, facebook_page_id) do
    Repo.get_by(FacebookPageCredential, user_id: user.id, facebook_page_id: facebook_page_id)
  end
end
