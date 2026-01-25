defmodule SocialScribeWeb.MeetingLive.Show do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton
  import SocialScribeWeb.ModalComponents, only: [crm_modal: 1]

  alias SocialScribe.Meetings
  alias SocialScribe.Automations
  alias SocialScribe.Accounts
  alias SocialScribe.CrmSuggestions
  alias SocialScribe.CrmFieldConfig

  alias SocialScribeWeb.MeetingLive.CrmModalComponent

  @impl true
  def mount(%{"id" => meeting_id}, _session, socket) do
    meeting = Meetings.get_meeting_with_details(meeting_id)

    user_has_automations =
      Automations.list_active_user_automations(socket.assigns.current_user.id)
      |> length()
      |> Kernel.>(0)

    automation_results = Automations.list_automation_results_for_meeting(meeting_id)

    if meeting.calendar_event.user_id != socket.assigns.current_user.id do
      socket =
        socket
        |> put_flash(:error, "You do not have permission to view this meeting.")
        |> redirect(to: ~p"/dashboard/meetings")

      {:error, socket}
    else
      hubspot_credential = Accounts.get_user_hubspot_credential(socket.assigns.current_user.id)
      salesforce_credential = Accounts.get_user_salesforce_credential(socket.assigns.current_user.id)

      socket =
        socket
        |> assign(:page_title, "Meeting Details: #{meeting.title}")
        |> assign(:meeting, meeting)
        |> assign(:automation_results, automation_results)
        |> assign(:user_has_automations, user_has_automations)
        |> assign(:hubspot_credential, hubspot_credential)
        |> assign(:salesforce_credential, salesforce_credential)
        |> assign(
          :follow_up_email_form,
          to_form(%{
            "follow_up_email" => ""
          })
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"automation_result_id" => automation_result_id}, _uri, socket) do
    automation_result = Automations.get_automation_result!(automation_result_id)
    automation = Automations.get_automation!(automation_result.automation_id)

    socket =
      socket
      |> assign(:automation_result, automation_result)
      |> assign(:automation, automation)

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate-follow-up-email", params, socket) do
    socket =
      socket
      |> assign(:follow_up_email_form, to_form(params))

    {:noreply, socket}
  end

  # Generic CRM handlers - provider is passed as part of the event tuple

  @impl true
  def handle_info({:crm_search, provider, query, credential}, socket) do
    case get_crm_api(provider) do
      nil ->
        send_update(CrmModalComponent,
          id: "#{provider}-modal",
          error: "Unsupported CRM provider: #{provider}",
          searching: false
        )

      api ->
        case api.search_contacts(credential, query) do
          {:ok, contacts} ->
            send_update(CrmModalComponent,
              id: "#{provider}-modal",
              contacts: contacts,
              searching: false
            )

          {:error, reason} ->
            send_update(CrmModalComponent,
              id: "#{provider}-modal",
              error: "Failed to search contacts: #{inspect(reason)}",
              searching: false
            )
        end
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:crm_generate_suggestions, provider, contact, meeting, _credential}, socket) do
    case CrmSuggestions.generate_suggestions_from_meeting(meeting, provider) do
      {:ok, suggestions} ->
        merged = CrmSuggestions.merge_with_contact(suggestions, normalize_contact(contact), provider)

        send_update(CrmModalComponent,
          id: "#{provider}-modal",
          step: :suggestions,
          suggestions: merged,
          loading: false
        )

      {:error, reason} ->
        send_update(CrmModalComponent,
          id: "#{provider}-modal",
          error: "Failed to generate suggestions: #{inspect(reason)}",
          loading: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:crm_apply_updates, provider, updates, contact, credential}, socket) do
    display_name = CrmFieldConfig.display_name(provider)

    case get_crm_api(provider) do
      nil ->
        send_update(CrmModalComponent,
          id: "#{provider}-modal",
          error: "Unsupported CRM provider: #{provider}",
          loading: false
        )

        {:noreply, socket}

      api ->
        case api.update_contact(credential, contact.id, updates) do
          {:ok, _updated_contact} ->
            socket =
              socket
              |> put_flash(:info, "Successfully updated #{map_size(updates)} field(s) in #{display_name}")
              |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

            {:noreply, socket}

          {:error, reason} ->
            send_update(CrmModalComponent,
              id: "#{provider}-modal",
              error: "Failed to update contact: #{inspect(reason)}",
              loading: false
            )

            {:noreply, socket}
        end
    end
  end


  defp normalize_contact(contact) do
    # Contact is already formatted with atom keys from the CRM API
    contact
  end

  # CRM API dispatch - add new providers here
  defp get_crm_api("hubspot"), do: SocialScribe.HubspotApiBehaviour
  defp get_crm_api("salesforce"), do: SocialScribe.SalesforceApiBehaviour
  defp get_crm_api(_), do: nil

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 && remaining_seconds > 0 -> "#{minutes} min #{remaining_seconds} sec"
      minutes > 0 -> "#{minutes} min"
      seconds > 0 -> "#{seconds} sec"
      true -> "Less than a second"
    end
  end

  attr :meeting_transcript, :map, required: true

  defp transcript_content(assigns) do
    has_transcript =
      assigns.meeting_transcript &&
        assigns.meeting_transcript.content &&
        Map.get(assigns.meeting_transcript.content, "data") &&
        Enum.any?(Map.get(assigns.meeting_transcript.content, "data"))

    assigns =
      assigns
      |> assign(:has_transcript, has_transcript)

    ~H"""
    <div class="bg-white shadow-xl rounded-lg p-6 md:p-8">
      <h2 class="text-2xl font-semibold mb-4 text-slate-700">
        Meeting Transcript
      </h2>
      <div class="prose prose-sm sm:prose max-w-none h-96 overflow-y-auto pr-2">
        <%= if @has_transcript do %>
          <div :for={segment <- @meeting_transcript.content["data"]} class="mb-3">
            <p>
              <span class="font-semibold text-indigo-600">
                {segment["speaker"] || "Unknown Speaker"}:
              </span>
              {Enum.map_join(segment["words"] || [], " ", & &1["text"])}
            </p>
          </div>
        <% else %>
          <p class="text-slate-500">
            Transcript not available for this meeting.
          </p>
        <% end %>
      </div>
    </div>
    """
  end
end
