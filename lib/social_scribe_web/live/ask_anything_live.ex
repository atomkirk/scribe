defmodule SocialScribeWeb.AskAnythingLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.CRMChat
  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Get connected CRM info
    hubspot_credential = Accounts.get_user_hubspot_credential(user.id)
    salesforce_credential = Accounts.get_user_salesforce_credential(user.id)

    {crm_provider, _credential} = CRMChat.get_connected_crm(user)

    # Load existing conversations for history
    conversations = CRMChat.list_user_conversations(user)

    socket =
      socket
      |> assign(:page_title, "Ask Anything")
      |> assign(:active_tab, :chat)
      |> assign(:conversations, conversations)
      |> assign(:current_conversation, nil)
      |> assign(:messages, [])
      |> assign(:input_value, "")
      |> assign(:loading, false)
      |> assign(:hubspot_credential, hubspot_credential)
      |> assign(:salesforce_credential, salesforce_credential)
      |> assign(:crm_provider, crm_provider)
      |> assign(:selected_contact, nil)
      |> assign(:contact_search_query, "")
      |> assign(:contact_search_results, [])
      |> assign(:contact_dropdown_open, false)
      |> assign(:searching_contacts, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    socket =
      socket
      |> assign(:current_conversation, nil)
      |> assign(:messages, [])
      |> assign(:selected_contact, nil)
      |> assign(:active_tab, :chat)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    conversation = CRMChat.get_user_conversation(socket.assigns.current_user, id)

    if conversation do
      socket =
        socket
        |> assign(:current_conversation, conversation)
        |> assign(:messages, conversation.messages)
        |> assign(:active_tab, :chat)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input_value, value)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    # Prevent duplicate sends if already loading
    if socket.assigns.loading do
      {:noreply, socket}
    else
      user = socket.assigns.current_user
      message = String.trim(message)

      if message == "" do
        {:noreply, socket}
      else
        # Create conversation if needed
        conversation =
          case socket.assigns.current_conversation do
            nil ->
              {:ok, conv} = CRMChat.create_conversation(user)
              conv

            conv ->
              conv
          end

        contact_id = if socket.assigns.selected_contact, do: socket.assigns.selected_contact.id, else: nil

        # Add user message to UI immediately
        user_message = %{
          role: "user",
          content: message,
          contact_name: if(socket.assigns.selected_contact, do: socket.assigns.selected_contact.display_name, else: nil),
          inserted_at: DateTime.utc_now()
        }

        socket =
          socket
          |> assign(:current_conversation, conversation)
          |> assign(:messages, socket.assigns.messages ++ [user_message])
          |> assign(:input_value, "")
          |> assign(:loading, true)

        # Send the question asynchronously
        send(self(), {:ask_question, conversation, message, contact_id})

        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", %{"key" => "Enter"}, socket) do
    # Don't handle Enter here - let the form's phx-submit handle it
    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_contact_search", _params, socket) do
    {:noreply, assign(socket, :contact_dropdown_open, true)}
  end

  @impl true
  def handle_event("close_contact_search", _params, socket) do
    {:noreply, assign(socket, contact_dropdown_open: false, contact_search_query: "", contact_search_results: [])}
  end

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)

    if String.length(query) >= 2 do
      socket = assign(socket, searching_contacts: true, contact_search_query: query)
      send(self(), {:search_contacts, query})
      {:noreply, socket}
    else
      {:noreply, assign(socket, contact_search_query: query, contact_search_results: [])}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.contact_search_results, &(&1.id == contact_id))

    if contact do
      socket =
        socket
        |> assign(:selected_contact, contact)
        |> assign(:contact_dropdown_open, false)
        |> assign(:contact_search_query, "")
        |> assign(:contact_search_results, [])

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    {:noreply, assign(socket, :selected_contact, nil)}
  end

  @impl true
  def handle_info({:ask_question, conversation, question, contact_id}, socket) do
    user = socket.assigns.current_user

    case CRMChat.ask_question(user, conversation, question, contact_id) do
      {:ok, %{assistant_message: assistant_message}} ->
        # Reload conversations for history
        conversations = CRMChat.list_user_conversations(user)

        socket =
          socket
          |> assign(:messages, socket.assigns.messages ++ [assistant_message])
          |> assign(:loading, false)
          |> assign(:conversations, conversations)
          |> assign(:selected_contact, nil)

        {:noreply, socket}

      {:error, reason} ->
        error_message = %{
          role: "assistant",
          content: "I'm sorry, I encountered an error: #{inspect(reason)}. Please try again.",
          inserted_at: DateTime.utc_now()
        }

        socket =
          socket
          |> assign(:messages, socket.assigns.messages ++ [error_message])
          |> assign(:loading, false)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:search_contacts, query}, socket) do
    result =
      case socket.assigns.crm_provider do
        "hubspot" ->
          HubspotApi.search_contacts(socket.assigns.hubspot_credential, query)

        "salesforce" ->
          SalesforceApi.search_contacts(socket.assigns.salesforce_credential, query)

        _ ->
          {:ok, []}
      end

    case result do
      {:ok, contacts} ->
        {:noreply, assign(socket, contact_search_results: contacts, searching_contacts: false)}

      {:error, _} ->
        {:noreply, assign(socket, contact_search_results: [], searching_contacts: false)}
    end
  end

  # Helper functions

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%I:%M%P - %B %d, %Y")
    |> String.replace("am", "am")
    |> String.replace("pm", "pm")
  end

  defp get_welcome_message do
    "I can answer questions about your CRM contacts and data - just ask!"
  end
end
