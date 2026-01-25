defmodule SocialScribe.ContactChats.ContactQuestionAnswererTest do
  use SocialScribe.DataCase

  import SocialScribe.AccountsFixtures
  import Mox

  alias SocialScribe.ContactChats.ContactQuestionAnswerer

  setup :verify_on_exit!

  describe "answer_question/5" do
    test "returns error when credential is nil" do
      assert {:error, :no_credential} =
               ContactQuestionAnswerer.answer_question(
                 "What's John's email?",
                 "hubspot",
                 nil,
                 [],
                 []
               )
    end

    test "uses selected_contacts as context and calls AI generator" do
      credential = hubspot_credential_fixture()

      selected_contacts = [
        %{id: "1", firstname: "John", lastname: "Doe", email: "john@example.com", phone: nil, company: "Acme"}
      ]

      meetings = [
        %{
          title: "Weekly",
          recorded_at: ~U[2026-01-01 10:00:00Z],
          meeting_transcript: %{content: %{"data" => [%{"words" => [%{"text" => "hello"}]}]}}
        }
      ]

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_contact_chat_response, fn prompt ->
        assert prompt =~ "User question:"
        assert prompt =~ "Here is relevant contact information"
        assert prompt =~ "Contact: John Doe"
        assert prompt =~ "Here are recent meeting transcripts"
        {:ok, "answer"}
      end)

      assert {:ok, "answer"} =
               ContactQuestionAnswerer.answer_question(
                 "What's John's email?",
                 "hubspot",
                 credential,
                 selected_contacts,
                 meetings
               )
    end

    test "searches CRM when no selected_contacts and question contains contact keyword" do
      credential = hubspot_credential_fixture()

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, term ->
        assert is_binary(term)
        {:ok, [%{id: "1", firstname: "John", lastname: "Doe", email: "john@example.com", phone: nil, company: "Acme"}]}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_contact_chat_response, fn prompt ->
        assert prompt =~ "Here is relevant contact information"
        {:ok, "answer"}
      end)

      assert {:ok, "answer"} =
               ContactQuestionAnswerer.answer_question(
                 "What is John's email?",
                 "hubspot",
                 credential,
                 [],
                 []
               )
    end

    test "does not search CRM when no search terms extracted" do
      credential = hubspot_credential_fixture()

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_contact_chat_response, fn prompt ->
        refute prompt =~ "Here is relevant contact information"
        {:ok, "answer"}
      end)

      assert {:ok, "answer"} =
               ContactQuestionAnswerer.answer_question(
                 "How are you?",
                 "hubspot",
                 credential,
                 [],
                 []
               )
    end

    test "supports salesforce provider" do
      credential = user_credential_fixture(%{provider: "salesforce"})

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, _term ->
        {:ok, [%{id: "sf1", firstname: "Jane", lastname: "Smith", email: "jane@example.com", phone: nil, company: "SF"}]}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_contact_chat_response, fn _prompt ->
        {:ok, "answer"}
      end)

      assert {:ok, "answer"} =
               ContactQuestionAnswerer.answer_question(
                 "What is Jane's email?",
                 "salesforce",
                 credential,
                 [],
                 []
               )
    end
  end
end
