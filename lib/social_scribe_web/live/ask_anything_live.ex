defmodule SocialScribeWeb.AskAnythingLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.CRMChat
  alias SocialScribe.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Get connected CRM info
    hubspot_credential = Accounts.get_user_hubspot_credential(user.id)
    salesforce_credential = Accounts.get_user_salesforce_credential(user.id)

    # Get all connected CRMs for multi-CRM search
    connected_crms = CRMChat.get_all_connected_crms(user)

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
      |> assign(:connected_crms, connected_crms)
      |> assign(:selected_contact, nil)
      |> assign(:contact_search_query, "")
      |> assign(:contact_search_results, [])
      |> assign(:contact_dropdown_open, false)
      |> assign(:searching_contacts, false)
      |> assign(:panel_open, true)
      # Inline @ mention state
      |> assign(:mention_active, false)
      |> assign(:mention_query, "")
      |> assign(:mention_results, [])
      |> assign(:mention_index, 0)
      |> assign(:mention_searching, false)
      # Track all mentioned contacts in the current message
      |> assign(:mentioned_contacts, %{})

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
      |> assign(:mentioned_contacts, %{})
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

        # Extract mentioned contacts from the message
        mentioned_contacts = socket.assigns.mentioned_contacts
        {contact_id, contact_name, crm_provider} = get_first_mentioned_contact(message, mentioned_contacts)

        # Add user message to UI immediately (with mentions info for display)
        user_message = %{
          role: "user",
          content: message,
          contact_name: contact_name,
          mentioned_contacts: mentioned_contacts,
          inserted_at: DateTime.utc_now()
        }

        socket =
          socket
          |> assign(:current_conversation, conversation)
          |> assign(:messages, socket.assigns.messages ++ [user_message])
          |> assign(:input_value, "")
          |> assign(:loading, true)
          |> assign(:mentioned_contacts, %{})

        # Send the question asynchronously with the correct CRM provider
        send(self(), {:ask_question, conversation, message, contact_id, crm_provider})

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
  def handle_event("toggle_panel", _params, socket) do
    {:noreply, assign(socket, :panel_open, !socket.assigns.panel_open)}
  end

  # Inline @ mention event handlers

  @impl true
  def handle_event("mention_search", %{"query" => query}, socket) do
    # Open mention dropdown and start searching
    socket =
      socket
      |> assign(:mention_active, true)
      |> assign(:mention_query, query)
      |> assign(:mention_index, 0)

    if String.length(query) >= 1 do
      socket = assign(socket, :mention_searching, true)
      send(self(), {:search_mention_contacts, query})
      {:noreply, socket}
    else
      # Show empty state or recent contacts when just "@" is typed
      {:noreply, assign(socket, mention_results: [], mention_searching: false)}
    end
  end

  @impl true
  def handle_event("close_mention", _params, socket) do
    socket =
      socket
      |> assign(:mention_active, false)
      |> assign(:mention_query, "")
      |> assign(:mention_results, [])
      |> assign(:mention_index, 0)
      |> assign(:mention_searching, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("mention_navigate", %{"direction" => direction}, socket) do
    results_count = length(socket.assigns.mention_results)

    if results_count > 0 do
      current_index = socket.assigns.mention_index

      new_index =
        case direction do
          "down" -> rem(current_index + 1, results_count)
          "up" -> rem(current_index - 1 + results_count, results_count)
          _ -> current_index
        end

      {:noreply, assign(socket, :mention_index, new_index)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("mention_select_current", _params, socket) do
    results = socket.assigns.mention_results
    index = socket.assigns.mention_index

    if length(results) > 0 and index < length(results) do
      contact = Enum.at(results, index)
      select_mention_contact(socket, contact)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_mention_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.mention_results, &(&1.id == contact_id))

    if contact do
      select_mention_contact(socket, contact)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input_value", %{"value" => value}, socket) do
    # Called from JS hook after inserting mention
    {:noreply, assign(socket, :input_value, value)}
  end

  defp select_mention_contact(socket, contact) do
    # Add contact to mentioned contacts map (keyed by display_name for lookup)
    mentioned_contacts = Map.put(
      socket.assigns.mentioned_contacts,
      contact.display_name,
      contact
    )

    socket =
      socket
      |> assign(:mentioned_contacts, mentioned_contacts)
      |> assign(:mention_active, false)
      |> assign(:mention_query, "")
      |> assign(:mention_results, [])
      |> assign(:mention_index, 0)
      |> assign(:mention_searching, false)
      # Push event to JS hook to insert the mention inline in the text
      |> push_event("insert_mention", %{
        contact_name: contact.display_name,
        contact_id: contact.id
      })

    {:noreply, socket}
  end

  # Extract the first mentioned contact from message text
  # Returns {contact_id, contact_name, crm_provider}
  defp get_first_mentioned_contact(message, mentioned_contacts) do
    # Find @mentions in the message
    case Regex.scan(~r/@([^@\s]+(?:\s+[^@\s]+)?)/, message) do
      [[_full, name] | _] ->
        # Try to find the contact by name (might be partial match)
        contact = find_contact_by_name(name, mentioned_contacts)
        if contact do
          {contact.id, contact.display_name, contact[:crm_provider]}
        else
          {nil, nil, nil}
        end

      _ ->
        {nil, nil, nil}
    end
  end

  defp find_contact_by_name(name, mentioned_contacts) do
    # Try exact match first
    case Map.get(mentioned_contacts, name) do
      nil ->
        # Try to find by prefix match (in case the name got truncated)
        Enum.find_value(mentioned_contacts, fn {display_name, contact} ->
          if String.starts_with?(display_name, name), do: contact
        end)

      contact ->
        contact
    end
  end

  @impl true
  def handle_info({:ask_question, conversation, question, contact_id, crm_provider}, socket) do
    user = socket.assigns.current_user

    case CRMChat.ask_question(user, conversation, question, contact_id, crm_provider) do
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
    # Search across all connected CRMs
    {:ok, contacts} = CRMChat.search_all_crms(socket.assigns.current_user, query)
    {:noreply, assign(socket, contact_search_results: contacts, searching_contacts: false)}
  end

  @impl true
  def handle_info({:search_mention_contacts, query}, socket) do
    # Only process if mention is still active (user might have closed it)
    if socket.assigns.mention_active do
      # Search across all connected CRMs
      {:ok, contacts} = CRMChat.search_all_crms(socket.assigns.current_user, query)
      {:noreply, assign(socket, mention_results: contacts, mention_searching: false)}
    else
      {:noreply, socket}
    end
  end

  # Helper functions

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%I:%M%P - %B %d, %Y")
    |> String.replace("am", "am")
    |> String.replace("pm", "pm")
  end

  defp get_welcome_message do
    "I can answer questions about Jump meetings and data – just ask!"
  end

  @doc """
  Renders message content with @mentions styled as pills.
  Returns a list of safe HTML parts that can be rendered in the template.
  """
  def render_message_with_mentions(content) when is_binary(content) do
    # Split the content by @mentions and render each part
    parts = Regex.split(~r/(@\w+(?:\s+\w+)?)/, content, include_captures: true)

    parts
    |> Enum.map(fn part ->
      if String.starts_with?(part, "@") do
        # This is a mention - render as styled pill
        mention_name = String.trim_leading(part, "@")
        escaped_name = Phoenix.HTML.html_escape(mention_name) |> Phoenix.HTML.safe_to_string()
        Phoenix.HTML.raw("""
        <span class="inline-flex items-center bg-blue-50 text-blue-700 rounded-full px-2 py-0.5 text-sm font-medium border border-blue-100">
          <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z" clip-rule="evenodd" />
          </svg>
          #{escaped_name}
        </span>
        """)
      else
        # Regular text
        Phoenix.HTML.html_escape(part)
      end
    end)
  end

  def render_message_with_mentions(_), do: ""
end
