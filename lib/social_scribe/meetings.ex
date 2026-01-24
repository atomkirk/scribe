defmodule SocialScribe.Meetings do
  @moduledoc """
  The Meetings context.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo

  alias SocialScribe.Meetings.Meeting
  alias SocialScribe.Meetings.MeetingTranscript
  alias SocialScribe.Meetings.MeetingParticipant
  alias SocialScribe.Bots.RecallBot

  require Logger

  @doc """
  Returns the list of meetings.

  ## Examples

      iex> list_meetings()
      [%Meeting{}, ...]

  """
  def list_meetings do
    Repo.all(Meeting)
  end

  @doc """
  Gets a single meeting.

  Raises `Ecto.NoResultsError` if the Meeting does not exist.

  ## Examples

      iex> get_meeting!(123)
      %Meeting{}

      iex> get_meeting!(456)
      ** (Ecto.NoResultsError)

  """
  def get_meeting!(id), do: Repo.get!(Meeting, id)

  @doc """
  Gets a meeting by recall bot id.

  ## Examples

      iex> get_meeting_by_recall_bot_id(123)
      %Meeting{}

  """
  def get_meeting_by_recall_bot_id(recall_bot_id) do
    Repo.get_by(Meeting, recall_bot_id: recall_bot_id)
  end

  @doc """
  Creates a meeting.

  ## Examples

      iex> create_meeting(%{field: value})
      {:ok, %Meeting{}}

      iex> create_meeting(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_meeting(attrs \\ %{}) do
    %Meeting{}
    |> Meeting.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a meeting.

  ## Examples

      iex> update_meeting(meeting, %{field: new_value})
      {:ok, %Meeting{}}

      iex> update_meeting(meeting, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_meeting(%Meeting{} = meeting, attrs) do
    meeting
    |> Meeting.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a meeting.

  ## Examples

      iex> delete_meeting(meeting)
      {:ok, %Meeting{}}

      iex> delete_meeting(meeting)
      {:error, %Ecto.Changeset{}}

  """
  def delete_meeting(%Meeting{} = meeting) do
    Repo.delete(meeting)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking meeting changes.

  ## Examples

      iex> change_meeting(meeting)
      %Ecto.Changeset{data: %Meeting{}}

  """
  def change_meeting(%Meeting{} = meeting, attrs \\ %{}) do
    Meeting.changeset(meeting, attrs)
  end

  @doc """
  Lists all processed meetings for a user.
  """
  def list_user_meetings(user) do
    from(m in Meeting,
      join: ce in assoc(m, :calendar_event),
      where: ce.user_id == ^user.id,
      order_by: [desc: m.recorded_at],
      preload: [:meeting_transcript, :meeting_participants, :recall_bot]
    )
    |> Repo.all()
  end

  @doc """
  Gets the most recent meetings with transcripts for a user.
  Limit defaults to 3 meetings.
  """
  def get_user_recent_meetings_with_transcripts(user_id, limit \\ 3) do
    from(m in Meeting,
      join: ce in assoc(m, :calendar_event),
      join: mt in assoc(m, :meeting_transcript),
      where: ce.user_id == ^user_id and not is_nil(mt.id),
      order_by: [desc: m.recorded_at],
      limit: ^limit,
      preload: [:meeting_transcript]
    )
    |> Repo.all()
  end

  @doc """
  Gets a meeting with its details preloaded.

  ## Examples

      iex> get_meeting_with_details(123)
      %Meeting{}
  """
  def get_meeting_with_details(meeting_id) do
    Meeting
    |> Repo.get(meeting_id)
    |> Repo.preload([:calendar_event, :recall_bot, :meeting_transcript, :meeting_participants])
  end

  alias SocialScribe.Meetings.MeetingTranscript

  @doc """
  Returns the list of meeting_transcripts.

  ## Examples

      iex> list_meeting_transcripts()
      [%MeetingTranscript{}, ...]

  """
  def list_meeting_transcripts do
    Repo.all(MeetingTranscript)
  end

  @doc """
  Gets a single meeting_transcript.

  Raises `Ecto.NoResultsError` if the Meeting transcript does not exist.

  ## Examples

      iex> get_meeting_transcript!(123)
      %MeetingTranscript{}

      iex> get_meeting_transcript!(456)
      ** (Ecto.NoResultsError)

  """
  def get_meeting_transcript!(id), do: Repo.get!(MeetingTranscript, id)

  @doc """
  Creates a meeting_transcript.

  ## Examples

      iex> create_meeting_transcript(%{field: value})
      {:ok, %MeetingTranscript{}}

      iex> create_meeting_transcript(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_meeting_transcript(attrs \\ %{}) do
    %MeetingTranscript{}
    |> MeetingTranscript.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a meeting_transcript.

  ## Examples

      iex> update_meeting_transcript(meeting_transcript, %{field: new_value})
      {:ok, %MeetingTranscript{}}

      iex> update_meeting_transcript(meeting_transcript, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_meeting_transcript(%MeetingTranscript{} = meeting_transcript, attrs) do
    meeting_transcript
    |> MeetingTranscript.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a meeting_transcript.

  ## Examples

      iex> delete_meeting_transcript(meeting_transcript)
      {:ok, %MeetingTranscript{}}

      iex> delete_meeting_transcript(meeting_transcript)
      {:error, %Ecto.Changeset{}}

  """
  def delete_meeting_transcript(%MeetingTranscript{} = meeting_transcript) do
    Repo.delete(meeting_transcript)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking meeting_transcript changes.

  ## Examples

      iex> change_meeting_transcript(meeting_transcript)
      %Ecto.Changeset{data: %MeetingTranscript{}}

  """
  def change_meeting_transcript(%MeetingTranscript{} = meeting_transcript, attrs \\ %{}) do
    MeetingTranscript.changeset(meeting_transcript, attrs)
  end

  alias SocialScribe.Meetings.MeetingParticipant

  @doc """
  Returns the list of meeting_participants.

  ## Examples

      iex> list_meeting_participants()
      [%MeetingParticipant{}, ...]

  """
  def list_meeting_participants do
    Repo.all(MeetingParticipant)
  end

  @doc """
  Gets a single meeting_participant.

  Raises `Ecto.NoResultsError` if the Meeting participant does not exist.

  ## Examples

      iex> get_meeting_participant!(123)
      %MeetingParticipant{}

      iex> get_meeting_participant!(456)
      ** (Ecto.NoResultsError)

  """
  def get_meeting_participant!(id), do: Repo.get!(MeetingParticipant, id)

  @doc """
  Creates a meeting_participant.

  ## Examples

      iex> create_meeting_participant(%{field: value})
      {:ok, %MeetingParticipant{}}

      iex> create_meeting_participant(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_meeting_participant(attrs \\ %{}) do
    %MeetingParticipant{}
    |> MeetingParticipant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a meeting_participant.

  ## Examples

      iex> update_meeting_participant(meeting_participant, %{field: new_value})
      {:ok, %MeetingParticipant{}}

      iex> update_meeting_participant(meeting_participant, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_meeting_participant(%MeetingParticipant{} = meeting_participant, attrs) do
    meeting_participant
    |> MeetingParticipant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a meeting_participant.

  ## Examples

      iex> delete_meeting_participant(meeting_participant)
      {:ok, %MeetingParticipant{}}

      iex> delete_meeting_participant(meeting_participant)
      {:error, %Ecto.Changeset{}}

  """
  def delete_meeting_participant(%MeetingParticipant{} = meeting_participant) do
    Repo.delete(meeting_participant)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking meeting_participant changes.

  ## Examples

      iex> change_meeting_participant(meeting_participant)
      %Ecto.Changeset{data: %MeetingParticipant{}}

  """
  def change_meeting_participant(%MeetingParticipant{} = meeting_participant, attrs \\ %{}) do
    MeetingParticipant.changeset(meeting_participant, attrs)
  end

  @doc """
  Creates a complete meeting record from Recall.ai bot info, transcript data, and participants.
  This should be called when a bot's status is "done".
  """
  def create_meeting_from_recall_data(%RecallBot{} = recall_bot, bot_api_info, transcript_data, participants_data) do
    calendar_event = Repo.preload(recall_bot, :calendar_event).calendar_event

    Repo.transaction(fn ->
      meeting_attrs = parse_meeting_attrs(calendar_event, recall_bot, bot_api_info)

      {:ok, meeting} = create_meeting(meeting_attrs)

      transcript_attrs = parse_transcript_attrs(meeting, transcript_data)

      {:ok, _transcript} = create_meeting_transcript(transcript_attrs)

      # Use participants from Recall.ai participants endpoint (includes all attendees, not just speakers)
      participants = parse_participants_data(participants_data)

      Enum.each(participants, fn participant_data ->
        participant_attrs = parse_participant_attrs(meeting, participant_data)
        create_meeting_participant(participant_attrs)
      end)

      Repo.preload(meeting, [:meeting_transcript, :meeting_participants])
    end)
  end

  # --- Private Parser Functions ---

  defp parse_meeting_attrs(calendar_event, recall_bot, bot_api_info) do
    recording_info = List.first(bot_api_info.recordings || []) || %{}

    completed_at =
      case DateTime.from_iso8601(recording_info.completed_at) do
        {:ok, parsed_completed_at, _} -> parsed_completed_at
        _ -> nil
      end

    recorded_at =
      case DateTime.from_iso8601(recording_info.started_at) do
        {:ok, parsed_recorded_at, _} -> parsed_recorded_at
        _ -> nil
      end

    duration_seconds =
      if recorded_at && completed_at do
        DateTime.diff(completed_at, recorded_at, :second)
      else
        nil
      end

    title =
      calendar_event.summary || Map.get(bot_api_info, [:meeting_metadata, :title]) ||
        "Recorded Meeting"

    %{
      title: title,
      recorded_at: recorded_at,
      duration_seconds: duration_seconds,
      calendar_event_id: calendar_event.id,
      recall_bot_id: recall_bot.id
    }
  end

  defp parse_transcript_attrs(meeting, transcript_data) do
    # Handle case where transcript is a JSON string (new Recall API format)
    parsed_data =
      case transcript_data do
        data when is_binary(data) -> Jason.decode!(data, keys: :atoms)
        data when is_list(data) -> data
        _ -> []
      end

    %{
      meeting_id: meeting.id,
      content: %{data: parsed_data},
      language: List.first(parsed_data, %{}) |> Map.get(:language, "unknown")
    }
  end

  defp parse_participant_attrs(meeting, participant_data) do
    %{
      meeting_id: meeting.id,
      recall_participant_id: to_string(participant_data.id),
      name: participant_data.name,
      is_host: Map.get(participant_data, :is_host, false)
    }
  end

  defp parse_participants_data(participants_data) do
    # Participants data from Recall.ai participants_download_url
    # Format: list of participant objects with id, name, is_host, etc.
    case participants_data do
      data when is_list(data) ->
        Enum.uniq_by(data, & &1[:id])

      _ ->
        []
    end
  end


  @doc """
  Generates a prompt for a meeting.
  """
  def generate_prompt_for_meeting(%Meeting{} = meeting) do
    case participants_to_string(meeting.meeting_participants) do
      {:error, :no_participants} ->
        {:error, :no_participants}

      {:ok, participants_string} ->
        case transcript_to_string(meeting.meeting_transcript) do
          {:error, :no_transcript} ->
            {:error, :no_transcript}

          {:ok, transcript_string} ->
            {:ok,
             generate_prompt(
               meeting.title,
               meeting.recorded_at,
               meeting.duration_seconds,
               participants_string,
               transcript_string
             )}
        end
    end
  end

  defp generate_prompt(title, date, duration, participants, transcript) do
    """
    ## Meeting Info:
    title: #{title}
    date: #{date}
    duration: #{duration} seconds

    ### Participants:
    #{participants}

    ### Transcript:
    #{transcript}
    """
  end

  defp participants_to_string(participants) do
    if Enum.empty?(participants) do
      {:error, :no_participants}
    else
      participants_string =
        participants
        |> Enum.map(fn participant ->
          "#{participant.name} (#{if participant.is_host, do: "Host", else: "Participant"})"
        end)
        |> Enum.join("\n")

      {:ok, participants_string}
    end
  end

  defp transcript_to_string(%MeetingTranscript{content: %{"data" => transcript_data}})
       when not is_nil(transcript_data) do
    {:ok, format_transcript_for_prompt(transcript_data)}
  end

  defp transcript_to_string(_), do: {:error, :no_transcript}

  defp format_transcript_for_prompt(transcript_segments) when is_list(transcript_segments) do
    Enum.map_join(transcript_segments, "\n", fn segment ->
      speaker = Map.get(segment, "speaker", "Unknown Speaker")
      words = Map.get(segment, "words", [])
      text = Enum.map_join(words, " ", &Map.get(&1, "text", ""))
      timestamp = format_timestamp(List.first(words))
      "[#{timestamp}] #{speaker}: #{text}"
    end)
  end

  defp format_transcript_for_prompt(_), do: ""

  defp format_timestamp(nil), do: "00:00"

  defp format_timestamp(word) do
    seconds = extract_seconds(Map.get(word, "start_timestamp"))
    total_seconds = trunc(seconds)
    minutes = div(total_seconds, 60)
    secs = rem(total_seconds, 60)
    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  # Handle map format: %{"absolute" => "...", "relative" => 41.911842}
  defp extract_seconds(%{"relative" => relative}) when is_number(relative), do: relative
  # Handle direct float format: 0.48204318
  defp extract_seconds(seconds) when is_number(seconds), do: seconds
  defp extract_seconds(_), do: 0
end
