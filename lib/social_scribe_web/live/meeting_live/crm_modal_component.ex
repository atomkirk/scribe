defmodule SocialScribeWeb.MeetingLive.CrmModalComponent do
  @moduledoc """
  A unified CRM modal component that works with any CRM provider.
  Accepts a `crm_provider` assign to configure behavior for HubSpot, Salesforce, or future CRMs.
  """
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents

  # CRM-specific configuration
  @crm_config %{
    hubspot: %{
      title: "Update in HubSpot",
      description: "Here are suggested updates to sync with your integrations based on this",
      search_event: :hubspot_search,
      suggestions_event: :generate_suggestions,
      apply_event: :apply_hubspot_updates,
      button_class: "bg-hubspot-button hover:bg-hubspot-button-hover",
      info_template: "1 object, %{count} fields in 1 integration selected to update"
    },
    salesforce: %{
      title: "Update in Salesforce",
      description: "Here are suggested updates to sync with your Salesforce CRM based on this",
      search_event: :salesforce_search,
      suggestions_event: :generate_salesforce_suggestions,
      apply_event: :apply_salesforce_updates,
      button_class: "bg-blue-600 hover:bg-blue-700",
      info_template: "1 contact, %{count} fields selected to update"
    }
  }

  @impl true
  def render(assigns) do
    config = get_config(assigns.crm_provider)
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "#{assigns.crm_provider}-modal-wrapper" end)
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="space-y-6">
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">{@config.title}</h2>
        <p id={"#{@modal_id}-description"} class="mt-2 text-base font-light leading-7 text-slate-500">
          {@config.description}
          <span class="block">meeting</span>
        </p>
      </div>

      <.contact_select
          selected_contact={@selected_contact}
          contacts={@contacts}
          loading={@searching}
          open={@dropdown_open}
          query={@query}
          target={@myself}
          error={@error}
        />

      <%= if @selected_contact do %>
        <.suggestions_section
          suggestions={@suggestions}
          loading={@loading}
          myself={@myself}
          patch={@patch}
          config={@config}
        />
      <% end %>
    </div>
    """
  end

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true
  attr :config, :map, required: true

  defp suggestions_section(assigns) do
    assigns = assign(assigns, :selected_count, Enum.count(assigns.suggestions, & &1.apply))
    info_text = String.replace(assigns.config.info_template, "%{count}", to_string(assigns.selected_count))
    assigns = assign(assigns, :info_text, info_text)

    ~H"""
    <div class="space-y-4">
      <%= if @loading do %>
        <div class="text-center py-8 text-slate-500">
          <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin mx-auto mb-2" />
          <p>Generating suggestions...</p>
        </div>
      <% else %>
        <%= if Enum.empty?(@suggestions) do %>
          <.empty_state
            message="No update suggestions found from this meeting."
            submessage="The AI didn't detect any new contact information in the transcript."
          />
        <% else %>
          <form phx-submit="apply_updates" phx-change="toggle_suggestion" phx-target={@myself}>
            <div class="space-y-4 max-h-[60vh] overflow-y-auto pr-2">
              <.suggestion_card :for={suggestion <- @suggestions} suggestion={suggestion} />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text={"Update #{format_crm_name(@config)}"}
              submit_class={@config.button_class}
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={@info_text}
            />
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp format_crm_name(%{title: title}) do
    # Extract CRM name from title (e.g., "Update in HubSpot" -> "HubSpot")
    title
    |> String.replace("Update in ", "")
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_select_all_suggestions(assigns)
      |> assign_new(:step, fn -> :search end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:contacts, fn -> [] end)
      |> assign_new(:selected_contact, fn -> nil end)
      |> assign_new(:suggestions, fn -> [] end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:searching, fn -> false end)
      |> assign_new(:dropdown_open, fn -> false end)
      |> assign_new(:error, fn -> nil end)

    {:ok, socket}
  end

  defp maybe_select_all_suggestions(socket, %{suggestions: suggestions}) when is_list(suggestions) do
    assign(socket, suggestions: Enum.map(suggestions, &Map.put(&1, :apply, true)))
  end

  defp maybe_select_all_suggestions(socket, _assigns), do: socket

  defp get_config(provider) when is_atom(provider), do: Map.fetch!(@crm_config, provider)
  defp get_config(provider) when is_binary(provider), do: get_config(String.to_existing_atom(provider))

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)
    config = get_config(socket.assigns.crm_provider)

    if String.length(query) >= 2 do
      socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
      send(self(), {config.search_event, query, socket.assigns.credential})
      {:noreply, socket}
    else
      {:noreply, assign(socket, query: query, contacts: [], dropdown_open: query != "")}
    end
  end

  @impl true
  def handle_event("open_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: true)}
  end

  @impl true
  def handle_event("close_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: false)}
  end

  @impl true
  def handle_event("toggle_contact_dropdown", _params, socket) do
    config = get_config(socket.assigns.crm_provider)

    if socket.assigns.dropdown_open do
      {:noreply, assign(socket, dropdown_open: false)}
    else
      # When opening dropdown with selected contact, search for similar contacts
      socket = assign(socket, dropdown_open: true, searching: true)
      query = "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"
      send(self(), {config.search_event, query, socket.assigns.credential})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))
    config = get_config(socket.assigns.crm_provider)

    if contact do
      socket = assign(socket,
        loading: true,
        selected_contact: contact,
        error: nil,
        dropdown_open: false,
        query: "",
        suggestions: []
      )
      send(self(), {config.suggestions_event, contact, socket.assigns.meeting, socket.assigns.credential})
      {:noreply, socket}
    else
      {:noreply, assign(socket, error: "Contact not found")}
    end
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    {:noreply,
     assign(socket,
       step: :search,
       selected_contact: nil,
       suggestions: [],
       loading: false,
       searching: false,
       dropdown_open: false,
       contacts: [],
       query: "",
       error: nil
     )}
  end

  @impl true
  def handle_event("toggle_suggestion", params, socket) do
    applied_fields = Map.get(params, "apply", %{})
    values = Map.get(params, "values", %{})
    checked_fields = Map.keys(applied_fields)

    updated_suggestions =
      Enum.map(socket.assigns.suggestions, fn suggestion ->
        apply? = suggestion.field in checked_fields

        suggestion =
          case Map.get(values, suggestion.field) do
            nil -> suggestion
            new_value -> %{suggestion | new_value: new_value}
          end

        %{suggestion | apply: apply?}
      end)

    {:noreply, assign(socket, suggestions: updated_suggestions)}
  end

  @impl true
  def handle_event("apply_updates", %{"apply" => selected, "values" => values}, socket) do
    socket = assign(socket, loading: true, error: nil)
    config = get_config(socket.assigns.crm_provider)

    updates =
      selected
      |> Map.keys()
      |> Enum.reduce(%{}, fn field, acc ->
        Map.put(acc, field, Map.get(values, field, ""))
      end)

    send(self(), {config.apply_event, updates, socket.assigns.selected_contact, socket.assigns.credential})
    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_updates", _params, socket) do
    {:noreply, assign(socket, error: "Please select at least one field to update")}
  end
end
