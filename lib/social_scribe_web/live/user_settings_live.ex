defmodule SocialScribeWeb.UserSettingsLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Accounts
  alias SocialScribe.Bots

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    google_accounts = Accounts.list_user_credentials(current_user, provider: "google")

    linkedin_accounts = Accounts.list_user_credentials(current_user, provider: "linkedin")

    facebook_accounts = Accounts.list_user_credentials(current_user, provider: "facebook")

    hubspot_accounts = Accounts.list_user_credentials(current_user, provider: "hubspot")

    salesforce_accounts = Accounts.list_user_credentials(current_user, provider: "salesforce")

    user_bot_preference =
      Bots.get_user_bot_preference(current_user.id) || %Bots.UserBotPreference{}

    changeset = Bots.change_user_bot_preference(user_bot_preference)

    socket =
      socket
      |> assign(:page_title, "User Settings")
      |> assign(:google_accounts, google_accounts)
      |> assign(:linkedin_accounts, linkedin_accounts)
      |> assign(:facebook_accounts, facebook_accounts)
      |> assign(:hubspot_accounts, hubspot_accounts)
      |> assign(:salesforce_accounts, salesforce_accounts)
      |> assign(:user_bot_preference, user_bot_preference)
      |> assign(:user_bot_preference_form, to_form(changeset))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    case socket.assigns.live_action do
      :facebook_pages ->
        facebook_page_options =
          socket.assigns.current_user
          |> Accounts.list_linked_facebook_pages()
          |> Enum.map(&{&1.page_name, &1.id})

        socket =
          socket
          |> assign(:facebook_page_options, facebook_page_options)
          |> assign(:facebook_page_form, to_form(%{"facebook_page" => ""}))

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_user_bot_preference", %{"user_bot_preference" => params}, socket) do
    changeset =
      socket.assigns.user_bot_preference
      |> Bots.change_user_bot_preference(params)

    {:noreply, assign(socket, :user_bot_preference_form, to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("update_user_bot_preference", %{"user_bot_preference" => params}, socket) do
    params = Map.put(params, "user_id", socket.assigns.current_user.id)

    case create_or_update_user_bot_preference(socket.assigns.user_bot_preference, params) do
      {:ok, bot_preference} ->
        {:noreply,
         socket
         |> assign(:user_bot_preference, bot_preference)
         |> put_flash(:info, "Bot preference updated successfully")}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :user_bot_preference_form, to_form(changeset, action: :validate))}
    end
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  @impl true
  def handle_event("select_facebook_page", %{"facebook_page" => facebook_page}, socket) do
    facebook_page_credential = Accounts.get_facebook_page_credential!(facebook_page)

    case Accounts.update_facebook_page_credential(facebook_page_credential, %{selected: true}) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Facebook page selected successfully")
          |> push_navigate(to: ~p"/dashboard/settings")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
    end
  end

  defp create_or_update_user_bot_preference(bot_preference, params) do
    case bot_preference do
      %Bots.UserBotPreference{id: nil} ->
        Bots.create_user_bot_preference(params)

      bot_preference ->
        Bots.update_user_bot_preference(bot_preference, params)
    end
  end
end
