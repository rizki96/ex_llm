defmodule ExLLM.Providers.Gemini.OAuth2.QATest do
  @moduledoc """
  Tests for Gemini Question Answering API via OAuth2.

  This module tests the question answering functionality using semantic
  retrieval from corpora with documents and chunks.
  """

  use ExLLM.Testing.OAuth2TestCase, timeout: 300_000

  alias ExLLM.Providers.Gemini.{Chunk, Corpus, Document, QA}
  alias ExLLM.Providers.Gemini.OAuth2.SharedOAuth2Test
  alias ExLLM.Testing.GeminiOAuth2Helper

  @moduletag :gemini_oauth2_apis
  @moduletag :question_answering

  describe "Question Answering API" do
    @describetag :oauth2

    setup %{oauth_token: token} do
      # More aggressive cleanup and longer wait for eventual consistency
      SharedOAuth2Test.aggressive_cleanup(token)
      # Longer wait for cleanup to propagate across Google's infrastructure
      SharedOAuth2Test.wait_for_consistency(3000)

      # Create corpus with documents and chunks for QA testing
      corpus_name = SharedOAuth2Test.unique_name("qa-test-corpus")

      {:ok, corpus} =
        Corpus.create_corpus(
          %{display_name: corpus_name},
          oauth_token: token
        )

      # Wait for corpus creation to propagate
      SharedOAuth2Test.wait_for_consistency()

      # Create a document about Elixir
      {:ok, doc} =
        Document.create_document(
          corpus.name,
          %{
            display_name: "Elixir Guide",
            custom_metadata: [
              %{key: "topic", string_value: "programming"},
              %{key: "language", string_value: "elixir"}
            ]
          },
          oauth_token: token
        )

      # Wait for document creation to propagate
      SharedOAuth2Test.wait_for_consistency()

      # Add content chunks
      chunks = [
        "Elixir is a dynamic, functional language designed for building maintainable and scalable applications.",
        "Elixir leverages the Erlang VM, known for running low-latency, distributed and fault-tolerant systems.",
        "The Elixir syntax is similar to Ruby, making it familiar to many developers.",
        "Pattern matching is one of the most powerful features in Elixir.",
        "GenServer is a behavior module for implementing the server of a client-server relation."
      ]

      created_chunks =
        Enum.map(chunks, fn content ->
          {:ok, chunk} =
            Chunk.create_chunk(
              doc.name,
              %{data: %{string_value: content}},
              oauth_token: token
            )

          # Small delay between chunk creations to avoid rate limits
          Process.sleep(500)
          chunk
        end)

      # Ensure we created all chunks
      assert length(created_chunks) == 5

      # Give the API more time to index the chunks for semantic search (indexing takes time)
      SharedOAuth2Test.wait_for_consistency(5000)

      on_exit(fn ->
        Corpus.delete_corpus(corpus.name, oauth_token: token, force: true, skip_cache: true)
      end)

      {:ok, oauth_token: token, corpus_id: corpus.name}
    end

    test "generate answer from corpus", %{oauth_token: token, corpus_id: corpus_id} do
      # Ask a question about Elixir
      contents = [
        %{
          parts: [%{text: "What is Elixir and what VM does it use?"}],
          role: "user"
        }
      ]

      # Retry QA generation with eventual consistency for corpus indexing
      # Start an agent to store the response
      {:ok, response_agent} = Agent.start_link(fn -> nil end)

      assert_eventually(
        fn ->
          case QA.generate_answer(
                 "models/aqa",
                 contents,
                 :verbose,
                 semantic_retriever: %{
                   source: corpus_id,
                   query: %{parts: [%{text: "Elixir programming language VM"}]}
                 },
                 temperature: 0.3,
                 oauth_token: token
               ) do
            {:ok, response} ->
              # Check if we got a valid answer
              if response.answer != nil and response.answer["content"] != nil and
                   response.answer["content"]["parts"] != nil do
                # Store the response
                Agent.update(response_agent, fn _ -> response end)
                # Signal success
                true
              else
                # Retry - corpus might not be indexed yet
                false
              end

            {:error, %{reason: :network_error, message: message}} ->
              # Handle permission issues - corpus might not be ready for semantic search yet
              if String.contains?(message, "PERMISSION_DENIED") or
                   String.contains?(message, "403") do
                # Retry
                false
              else
                raise "QA failed: #{message}"
              end

            {:error, error} ->
              raise "QA failed: #{inspect(error)}"
          end
        end,
        timeout: 30_000,
        interval: 3000,
        description: "QA generation to work with corpus indexing"
      )

      # Get the stored response
      answer_response = Agent.get(response_agent, & &1)
      Agent.stop(response_agent)

      assert answer_response.answer["content"]["parts"] != []

      # The answer should mention Elixir and its characteristics
      answer_text =
        if answer_response.answer && answer_response.answer["content"] &&
             answer_response.answer["content"]["parts"] do
          answer_response.answer["content"]["parts"] |> Enum.map(& &1["text"]) |> Enum.join(" ")
        else
          ""
        end

      assert answer_text =~ ~r/Elixir/i
      # Should mention characteristics from the chunks we added
      assert answer_text =~ ~r/dynamic|functional|scalable|maintainable/i

      # Check grounding attributions (optional in response)
      assert is_nil(answer_response.answer["groundingAttributions"]) or
               is_list(answer_response.answer["groundingAttributions"])
    end

    test "generate answer with metadata filters", %{oauth_token: token, corpus_id: corpus_id} do
      contents = [
        %{
          parts: [%{text: "What are the features of Elixir?"}],
          role: "user"
        }
      ]

      {:ok, answer_response} =
        QA.generate_answer(
          "models/aqa",
          contents,
          :abstractive,
          semantic_retriever: %{
            source: corpus_id,
            query: %{parts: [%{text: "Elixir features"}]},
            metadata_filters: [
              %{
                key: "document.custom_metadata.language",
                conditions: [%{string_value: "elixir", operation: "EQUAL"}]
              }
            ]
          },
          temperature: 0.3,
          oauth_token: token
        )

      assert answer_response.answer["content"]["parts"] != []

      # Should mention pattern matching or other features
      answer_text =
        if answer_response.answer && answer_response.answer["content"] &&
             answer_response.answer["content"]["parts"] do
          answer_response.answer["content"]["parts"] |> Enum.map(& &1["text"]) |> Enum.join(" ")
        else
          ""
        end

      assert answer_text =~ ~r/pattern matching|GenServer|functional|scalable/i
    end
  end
end
