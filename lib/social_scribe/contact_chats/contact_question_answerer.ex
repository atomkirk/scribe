defmodule SocialScribe.ContactChats.ContactQuestionAnswerer do
  @moduledoc """
  Answers questions about contacts using Gemini AI based on data from HubSpot or Salesforce.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi

  @doc """
  Answers a question about contacts using AI.

  The function:
  1. Uses provided selected_contacts if available, otherwise searches the CRM
  2. Fetches detailed information if needed
  3. Uses Gemini to generate a natural language response

  Returns {:ok, answer} or {:error, reason}
  """
  def answer_question(question, provider, credential, selected_contacts \\ []) when is_binary(question) and provider in ["hubspot", "salesforce"] do
    if credential == nil do
      {:error, :no_credential}
    else
      case get_relevant_context(question, provider, credential, selected_contacts) do
        {:ok, context} ->
          generate_answer(question, context, provider)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Builds a prompt for Gemini and generates a response.
  """
  defp generate_answer(question, context, provider) do
    prompt = build_prompt(question, context, provider)

    case AIContentGeneratorApi.generate_contact_chat_response(prompt) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets relevant contact data from the CRM to use as context.

  If selected_contacts are provided, uses those directly.
  Otherwise, parses the question to extract contact names and searches.
  """
  defp get_relevant_context(question, provider, credential, selected_contacts) when is_list(selected_contacts) and length(selected_contacts) > 0 do
    # Use the selected contacts directly
    {:ok, format_contacts_for_context(selected_contacts, provider)}
  end

  defp get_relevant_context(question, provider, credential, _selected_contacts) do
    case extract_search_terms(question) do
      {:ok, search_term} ->
        case search_contacts(provider, credential, search_term) do
          {:ok, contacts} ->
            {:ok, format_contacts_for_context(contacts, provider)}

          {:error, reason} ->
            {:error, reason}
        end

      :no_search_term ->
        # Return empty context - AI will handle generic questions
        {:ok, []}
    end
  end

  @doc """
  Searches for contacts in the CRM based on search terms.
  """
  defp search_contacts(provider, credential, search_term) do
    case provider do
      "hubspot" ->
        HubspotApi.search_contacts(credential, search_term)

      "salesforce" ->
        SalesforceApi.search_contacts(credential, search_term)
    end
  end

  @doc """
  Extracts potential search terms from a question.

  Examples:
    "What's John Doe's email?" -> {:ok, "John Doe"}
    "Tell me about the company" -> {:ok, "company"}
    "How are you?" -> :no_search_term
  """
  defp extract_search_terms(question) do
    question = String.downcase(question)

    # Simple heuristic: look for common contact-related keywords
    contact_keywords = ["name", "email", "phone", "company", "jobtitle",]

    has_contact_keyword = Enum.any?(contact_keywords, &String.contains?(question, &1))

    if has_contact_keyword do
      # Extract a simple search term
      terms = question
        |> String.split(~w(what's what is about for the a an in at))
        |> Enum.reject(&(&1 == "" || String.length(&1) < 2))
        |> Enum.map(&String.trim/1)

      case terms do
        [] -> :no_search_term
        [term | _] -> {:ok, term}
      end
    else
      :no_search_term
    end
  end

  @doc """
  Formats contact data for use in the AI prompt.
  """
  defp format_contacts_for_context(contacts, _provider) when is_list(contacts) do
    contacts
    |> Enum.map(&format_single_contact/1)
    |> Enum.join("\n\n")
  end

  defp format_contacts_for_context(_, _), do: ""

  @doc """
  Formats a single contact record into readable text.
  """
  defp format_single_contact(contact) when is_map(contact) do
    """
    Contact: #{contact.firstname || ""} #{contact.lastname || ""}
    Email: #{contact.email || "N/A"}
    Phone: #{contact.phone || "N/A"}
    Company: #{contact.company || "N/A"}
    """
  end

  defp format_single_contact(_), do: ""

  @doc """
  Builds a prompt for the AI to answer the question using the contact context.
  """
  defp build_prompt(question, context, provider) do
    context_text = if is_list(context) && Enum.empty?(context) do
      ""
    else
      "\n\nHere is relevant contact information from #{provider}:\n#{context}"
    end

    """
    You are a helpful assistant that answers questions about CRM contacts.

    User question: #{question}
    #{context_text}

    Please answer the user's question based on the contact information provided.
    Be concise and natural in your response. If you don't have enough information to answer,
    say so and suggest how to get more information.
    """
  end
end
