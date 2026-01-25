defmodule SocialScribeWeb.ChatLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Accounts
  alias SocialScribe.Meetings
  alias SocialScribe.ContactChats
  alias SocialScribe.ContactChats.ContactQuestionAnswerer
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user do
      socket =
        socket
        |> assign(:page_title, "Ask Anything")
        |> assign(:active_tab, "chat")
        |> assign(:active_chat_id, nil)
        |> assign(:messages, [])
        |> assign(:chat_history, [])
        |> assign(:input_value, "")
        |> assign(:loading, false)
        |> assign(:error, nil)
        |> assign(:provider, "hubspot")
        |> assign(:has_hubspot, false)
        |> assign(:has_salesforce, false)
        |> assign(:selected_contacts, [])
        |> assign(:search_results, [])
        |> assign(:show_search_modal, false)
        |> assign(:search_query, "")
        |> assign(:searching, false)
        |> assign(:recent_meetings, [])
        |> load_credentials()
        |> load_chat_history()
        |> load_recent_meetings()

      {:ok, socket, layout: {SocialScribeWeb.Layouts, :dashboard}}
    else
      {:error, socket}
    end
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  @impl true
  def handle_event("select_chat", %{"chat_id" => chat_id}, socket) do
    chat = ContactChats.get_contact_chat!(chat_id)
    messages = ContactChats.get_chat_messages(chat_id)

    socket =
      socket
      |> assign(:active_chat_id, chat_id)
      |> assign(:messages, messages)
      |> assign(:active_tab, "chat")

    {:noreply, socket}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    socket =
      socket
      |> assign(:active_chat_id, nil)
      |> assign(:messages, [])
      |> assign(:input_value, "")
      |> assign(:error, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_provider", params, socket) do
    IO.inspect(params, label: "provider changing")
    {:noreply, assign(socket, provider: params["provider"], error: nil)}
  end

  @impl true
  def handle_event("update_input", %{"input" => input}, socket) do
    {:noreply, assign(socket, input_value: input)}
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, error: nil)}
  end

  @impl true
  def handle_event("open_contact_search", _params, socket) do
    {:noreply, assign(socket, show_search_modal: true, search_results: [], search_query: "")}
  end

  @impl true
  def handle_event("close_contact_search", _params, socket) do
    {:noreply, assign(socket, show_search_modal: false, search_results: [], search_query: "")}
  end

  @impl true
  def handle_event("search_contacts", %{"value" => query}, socket) do
    query = String.trim(query)

    if String.length(query) < 2 do
      {:noreply, assign(socket, search_results: [], search_query: query)}
    else
      socket = assign(socket, searching: true, search_query: query)
      send(self(), {:perform_contact_search, query, socket.assigns.provider})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"contact_id" => contact_id}, socket) do
    # Fetch full contact details from API
    send(self(), {:fetch_contact_details, contact_id, socket.assigns.provider})
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_contact", %{"contact_id" => contact_id}, socket) do
    selected_contacts = Enum.reject(socket.assigns.selected_contacts, &(&1.id == contact_id))
    {:noreply, assign(socket, selected_contacts: selected_contacts)}
  end

  @impl true
  def handle_event("send_message", %{"input" => content}, socket) do
    content = String.trim(content)

    cond do
      content == "" ->
        {:noreply, assign(socket, error: "Please enter a question")}

      socket.assigns.provider == "hubspot" && !socket.assigns.has_hubspot ->
        {:noreply, assign(socket, error: "Please connect your HubSpot account first")}

      socket.assigns.provider == "salesforce" && !socket.assigns.has_salesforce ->
        {:noreply, assign(socket, error: "Please connect your Salesforce account first")}

      true ->
        socket = assign(socket, loading: true, error: nil)
        send(self(), {:process_question, content, socket.assigns.provider})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:process_question, content, provider}, socket) do
    credential =
      if provider == "hubspot" do
        socket.assigns.hubspot_credential
      else
        socket.assigns.salesforce_credential
      end

    # Get or create chat session
    chat =
      if socket.assigns.active_chat_id do
        ContactChats.get_contact_chat!(socket.assigns.active_chat_id)
      else
        # Create new chat for this session
        {:ok, chat} =
          ContactChats.create_contact_chat(%{
            user_id: socket.assigns.current_user.id,
            provider: provider,
            contact_id: "general",
            contact_name: "General Question"
          })

        chat
      end

    # Save user message
    {:ok, user_message} =
      ContactChats.add_message(chat, "user", content)

    # Update UI with user message
    socket =
      socket
      |> assign(:messages, socket.assigns.messages ++ [user_message])
      |> assign(:input_value, "")
      |> assign(:active_chat_id, chat.id)

    # Generate AI response with selected contacts context
    case generate_answer(content, provider, credential, socket.assigns.selected_contacts, socket.assigns.recent_meetings) do
      {:ok, answer} ->
        {:ok, ai_message} = ContactChats.add_message(chat, "assistant", answer)

        socket =
          socket
          |> assign(:messages, socket.assigns.messages ++ [ai_message])
          |> assign(:loading, false)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error, "Failed to generate response: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:perform_contact_search, query, provider}, socket) do
    credential =
      if provider == "hubspot" do
        socket.assigns.hubspot_credential
      else
        socket.assigns.salesforce_credential
      end

    case search_contacts_in_crm(provider, credential, query) do
      {:ok, results} ->
        {:noreply,
         assign(socket,
           search_results: results,
           searching: false
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           search_results: [],
           searching: false
         )}
    end
  end

  @impl true
  def handle_info({:fetch_contact_details, contact_id, provider}, socket) do
    credential =
      if provider == "hubspot" do
        socket.assigns.hubspot_credential
      else
        socket.assigns.salesforce_credential
      end

    case fetch_full_contact(provider, credential, contact_id) do
      {:ok, contact} ->
        # Add to selected contacts if not already there
        selected_contacts =
          if Enum.any?(socket.assigns.selected_contacts, &(&1.id == contact_id)) do
            socket.assigns.selected_contacts
          else
            socket.assigns.selected_contacts ++ [contact]
          end

        {:noreply,
         assign(socket,
           selected_contacts: selected_contacts,
           show_search_modal: false,
           search_results: [],
           search_query: ""
         )}

      {:error, _reason} ->
        {:noreply, assign(socket, error: "Failed to fetch contact details")}
    end
  end

  defp load_credentials(socket) do
    hubspot_credential = Accounts.get_user_hubspot_credential(socket.assigns.current_user.id)
    salesforce_credential = Accounts.get_user_salesforce_credential(socket.assigns.current_user.id)

    socket
    |> assign(:hubspot_credential, hubspot_credential)
    |> assign(:salesforce_credential, salesforce_credential)
    |> assign(:has_hubspot, hubspot_credential != nil)
    |> assign(:has_salesforce, salesforce_credential != nil)
  end

  defp load_chat_history(socket) do
    chats = ContactChats.list_chats_for_user(socket.assigns.current_user.id)
    assign(socket, :chat_history, chats)
  end

  defp load_recent_meetings(socket) do
    meetings = Meetings.get_user_recent_meetings_with_transcripts(socket.assigns.current_user.id, 3)
    assign(socket, :recent_meetings, meetings)
  end

  defp generate_answer(question, provider, credential, selected_contacts, recent_meetings) do
    case ContactQuestionAnswerer.answer_question(question, provider, credential, selected_contacts, recent_meetings) do
      {:ok, answer} -> {:ok, answer}
      {:error, reason} -> {:error, reason}
    end
  end

  defp search_contacts_in_crm(provider, credential, query) do
    case provider do
      "hubspot" ->
        IO.inspect({:hubspot_search, credential, query}, label: "Searching HubSpot contacts")
        HubspotApi.search_contacts(credential, query)

      "salesforce" ->
        IO.inspect({:salesforce_search, credential, query}, label: "searching sales force")
        SalesforceApi.search_contacts(credential, query)

      _ ->
        {:error, :invalid_provider}
    end
  end

  defp fetch_full_contact(provider, credential, contact_id) do
    case provider do
      "hubspot" ->
        HubspotApi.get_contact(credential, contact_id)

      "salesforce" ->
        SalesforceApi.get_contact(credential, contact_id)

      _ ->
        {:error, :invalid_provider}
    end
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    seconds_ago = DateTime.diff(now, datetime, :second)

    cond do
      seconds_ago < 60 ->
        "just now"

      seconds_ago < 3600 ->
        minutes = div(seconds_ago, 60)
        "#{minutes}m ago"

      seconds_ago < 86400 ->
        hours = div(seconds_ago, 3600)
        "#{hours}h ago"

      seconds_ago < 604800 ->
        days = div(seconds_ago, 86400)
        "#{days}d ago"

      true ->
        datetime
        |> Calendar.strftime("%b %d")
    end
  end

defp format_chat_date(dt) when is_struct(dt, DateTime) or is_struct(dt, NaiveDateTime) do
  # %I:%M%P  -> 11:50am
  # %B %d, %Y -> November 13, 2025
  Calendar.strftime(dt, "%I:%M%P - %B %d, %Y")
end

defp format_chat_date(_), do: "Date Unknown"
end
