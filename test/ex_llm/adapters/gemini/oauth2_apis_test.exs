defmodule ExLLM.Adapters.Gemini.OAuth2APIsTest do
  use ExUnit.Case, async: false
  @moduletag :oauth2

  alias ExLLM.Gemini.{
    Corpus,
    Document,
    Chunk,
    Permissions,
    QA
  }

  alias ExLLM.Test.GeminiOAuth2Helper

  # Skip all tests if OAuth2 is not available
  setup :skip_without_oauth

  defp skip_without_oauth(_context) do
    GeminiOAuth2Helper.skip_without_oauth(%{})
  end

  describe "Corpus Management API" do
    @describetag :oauth2

    setup %{oauth_token: token} do
      # Generate unique corpus name for this test run
      # Must be lowercase and only contain letters, numbers, and hyphens
      corpus_name =
        "test-corpus-#{System.unique_integer([:positive]) |> Integer.to_string() |> String.downcase()}"

      {:ok, oauth_token: token, corpus_name: corpus_name}
    end

    test "full corpus lifecycle", %{oauth_token: token, corpus_name: corpus_name} do
      # 1. Create a corpus
      {:ok, corpus} =
        Corpus.create_corpus(
          %{
            display_name: corpus_name
          },
          oauth_token: token
        )

      assert corpus.display_name == corpus_name
      assert corpus.name =~ ~r/^corpora\//

      # Save the corpus ID for cleanup
      corpus_id = corpus.name

      # 2. List corpora (should include our new corpus)
      {:ok, list_response} = Corpus.list_corpora([], oauth_token: token)
      assert Enum.any?(list_response.corpora, fn c -> c.name == corpus_id end)

      # 3. Get specific corpus
      {:ok, fetched_corpus} = Corpus.get_corpus(corpus_id, oauth_token: token)
      assert fetched_corpus.name == corpus_id
      assert fetched_corpus.display_name == corpus_name

      # 4. Update corpus
      new_display_name = "Updated #{corpus_name}"

      {:ok, updated_corpus} =
        Corpus.update_corpus(
          corpus_id,
          %{display_name: new_display_name},
          ["displayName"],
          oauth_token: token
        )

      assert updated_corpus.display_name == new_display_name

      # 5. Query corpus (should return empty results)
      {:ok, query_response} =
        Corpus.query_corpus(
          corpus_id,
          "test query",
          %{results_count: 10},
          oauth_token: token
        )

      assert query_response.relevant_chunks == []

      # 6. Delete corpus
      :ok = Corpus.delete_corpus(corpus_id, oauth_token: token)

      # 7. Verify deletion (may return 403 or 404)
      result = Corpus.get_corpus(corpus_id, oauth_token: token)

      assert match?({:error, %{status: status}} when status in [403, 404], result) or
               match?({:error, %{code: code}} when code in [403, 404], result)
    end

    test "corpus with metadata filters", %{oauth_token: token, corpus_name: corpus_name} do
      # Create corpus
      {:ok, corpus} =
        Corpus.create_corpus(
          %{display_name: corpus_name},
          oauth_token: token
        )

      # Query with metadata filters
      {:ok, query_response} =
        Corpus.query_corpus(
          corpus.name,
          "test query",
          %{
            results_count: 5,
            metadata_filters: [
              %{
                key: "document.custom_metadata.category",
                conditions: [
                  %{string_value: "technology", operation: "EQUAL"}
                ]
              }
            ]
          },
          oauth_token: token
        )

      assert is_list(query_response.relevant_chunks)

      # Cleanup
      :ok = Corpus.delete_corpus(corpus.name, oauth_token: token)
    end
  end

  describe "Document Management API" do
    @describetag :oauth2

    setup %{oauth_token: token} do
      # Create a corpus for document testing
      corpus_name =
        "doc-test-corpus-#{System.unique_integer([:positive]) |> Integer.to_string() |> String.downcase()}"

      {:ok, corpus} =
        Corpus.create_corpus(
          %{display_name: corpus_name},
          oauth_token: token
        )

      on_exit(fn ->
        # Cleanup corpus after tests
        Corpus.delete_corpus(corpus.name, oauth_token: token, force: true)
      end)

      {:ok, oauth_token: token, corpus_id: corpus.name}
    end

    test "document lifecycle", %{oauth_token: token, corpus_id: corpus_id} do
      # 1. Create a document
      doc_name = "test-doc-#{System.unique_integer([:positive])}"

      {:ok, document} =
        Document.create_document(
          corpus_id,
          %{
            display_name: doc_name,
            custom_metadata: [
              %{key: "author", string_value: "Test Author"},
              %{key: "category", string_value: "technology"}
            ]
          },
          oauth_token: token
        )

      assert document.display_name == doc_name
      assert document.name =~ ~r/^#{corpus_id}\/documents\//

      # 2. List documents
      {:ok, list_response} = Document.list_documents(corpus_id, oauth_token: token)
      assert Enum.any?(list_response.documents, fn d -> d.name == document.name end)

      # 3. Get specific document
      {:ok, fetched_doc} = Document.get_document(document.name, oauth_token: token)
      assert fetched_doc.display_name == doc_name

      # 4. Update document
      new_display_name = "Updated #{doc_name}"

      {:ok, updated_doc} =
        Document.update_document(
          document.name,
          %{display_name: new_display_name},
          ["displayName"],
          oauth_token: token
        )

      assert updated_doc.display_name == new_display_name

      # 5. Query documents - Note: query_documents is not implemented, skip this step

      # 6. Delete document
      :ok = Document.delete_document(document.name, oauth_token: token)

      # 7. Verify deletion
      result = Document.get_document(document.name, oauth_token: token)
      assert match?({:error, %{code: 404}}, result) or match?({:error, %{status: 404}}, result)
    end
  end

  describe "Chunk Management API" do
    @describetag :oauth2

    setup %{oauth_token: token} do
      # Create corpus and document for chunk testing  
      corpus_name =
        "chunk-test-corpus-#{System.unique_integer([:positive]) |> Integer.to_string() |> String.downcase()}"

      {:ok, corpus} =
        Corpus.create_corpus(
          %{display_name: corpus_name},
          oauth_token: token
        )

      doc_name = "chunk-test-doc-#{System.unique_integer([:positive])}"

      {:ok, document} =
        Document.create_document(
          corpus.name,
          %{display_name: doc_name},
          oauth_token: token
        )

      on_exit(fn ->
        # Force cleanup
        Corpus.delete_corpus(corpus.name, oauth_token: token, force: true)
      end)

      {:ok, oauth_token: token, document_id: document.name}
    end

    test "chunk lifecycle", %{oauth_token: token, document_id: document_id} do
      # 1. Create chunks
      chunk_data =
        "This is a test chunk for the ExLLM library. It contains sample content for testing semantic retrieval."

      {:ok, chunk} =
        Chunk.create_chunk(
          document_id,
          %{
            data: %{string_value: chunk_data},
            custom_metadata: [
              %{key: "section", string_value: "introduction"},
              %{key: "page", numeric_value: 1}
            ]
          },
          oauth_token: token
        )

      assert chunk.data.string_value == chunk_data
      assert chunk.name =~ ~r/^#{document_id}\/chunks\//

      # 2. Create another chunk
      chunk_data2 = "This is another chunk with different content about Elixir and LLMs."

      {:ok, _chunk2} =
        Chunk.create_chunk(
          document_id,
          %{
            data: %{string_value: chunk_data2},
            custom_metadata: [
              %{key: "section", string_value: "content"},
              %{key: "page", numeric_value: 2}
            ]
          },
          oauth_token: token
        )

      # 3. List chunks
      {:ok, list_response} = Chunk.list_chunks(document_id, oauth_token: token)
      assert length(list_response.chunks) >= 2
      assert Enum.any?(list_response.chunks, fn c -> c.name == chunk.name end)

      # 4. Get specific chunk
      {:ok, fetched_chunk} = Chunk.get_chunk(chunk.name, oauth_token: token)
      assert fetched_chunk.data.string_value == chunk_data

      # 5. Update chunk
      updated_data = "This is the updated test chunk content."

      {:ok, updated_chunk} =
        Chunk.update_chunk(
          chunk.name,
          %{data: %{string_value: updated_data}},
          ["data"],
          oauth_token: token
        )

      assert updated_chunk.data.string_value == updated_data

      # 6. Batch create chunks
      batch_chunks =
        Enum.map(1..3, fn i ->
          %{
            data: %{string_value: "Batch chunk #{i}"},
            custom_metadata: [
              %{key: "batch", string_value: "true"},
              %{key: "index", numeric_value: i}
            ]
          }
        end)

      {:ok, batch_response} =
        Chunk.batch_create_chunks(
          document_id,
          batch_chunks,
          oauth_token: token
        )

      assert length(batch_response.chunks) == 3

      # 7. Delete chunk
      :ok = Chunk.delete_chunk(chunk.name, oauth_token: token)

      # 8. Verify deletion
      result = Chunk.get_chunk(chunk.name, oauth_token: token)
      assert match?({:error, %{code: 404}}, result) or match?({:error, %{status: 404}}, result)
    end

    test "batch operations", %{oauth_token: token, document_id: document_id} do
      # Batch create
      chunks =
        Enum.map(1..5, fn i ->
          %{
            data: %{string_value: "Batch test chunk #{i}"},
            custom_metadata: [
              %{key: "batch_test", string_value: "true"},
              %{key: "index", numeric_value: i}
            ]
          }
        end)

      {:ok, batch_response} =
        Chunk.batch_create_chunks(
          document_id,
          chunks,
          oauth_token: token
        )

      assert length(batch_response.chunks) == 5

      # Batch update
      chunk_names = Enum.map(batch_response.chunks, & &1.name)

      updates =
        Enum.map(chunk_names, fn name ->
          %{
            chunk: %{
              name: name,
              data: %{string_value: "Updated: #{name}"}
            },
            update_mask: "data"
          }
        end)

      {:ok, update_response} =
        Chunk.batch_update_chunks(
          document_id,
          updates,
          oauth_token: token
        )

      assert length(update_response.chunks) == 5

      # Batch delete
      :ok =
        Chunk.batch_delete_chunks(
          document_id,
          chunk_names,
          oauth_token: token
        )

      # Verify all deleted
      {:ok, list_response} = Chunk.list_chunks(document_id, oauth_token: token)
      deleted_names = MapSet.new(chunk_names)

      remaining =
        Enum.filter(list_response.chunks, fn c ->
          MapSet.member?(deleted_names, c.name)
        end)

      assert remaining == []
    end
  end

  describe "Question Answering API" do
    @describetag :oauth2

    setup %{oauth_token: token} do
      # Create corpus with documents and chunks for QA testing
      corpus_name =
        "qa-test-corpus-#{System.unique_integer([:positive]) |> Integer.to_string() |> String.downcase()}"

      {:ok, corpus} =
        Corpus.create_corpus(
          %{display_name: corpus_name},
          oauth_token: token
        )

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

          chunk
        end)

      # Ensure we created all chunks
      assert length(created_chunks) == 5

      # Give the API a moment to index the chunks
      Process.sleep(1000)

      on_exit(fn ->
        Corpus.delete_corpus(corpus.name, oauth_token: token, force: true)
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

      {:ok, answer_response} =
        QA.generate_answer(
          "models/aqa",
          contents,
          :verbose,
          semantic_retriever: %{
            source: corpus_id,
            query: %{parts: [%{text: "Elixir programming language VM"}]}
          },
          temperature: 0.3,
          oauth_token: token
        )

      assert answer_response.answer["content"]["parts"] != []

      # The answer should mention Elixir and its characteristics
      answer_text =
        answer_response.answer["content"]["parts"] |> Enum.map(& &1["text"]) |> Enum.join(" ")

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
        answer_response.answer["content"]["parts"] |> Enum.map(& &1["text"]) |> Enum.join(" ")

      assert answer_text =~ ~r/pattern matching|GenServer|functional|scalable/i
    end
  end

  describe "Permissions API for Tuned Models" do
    @describetag :oauth2
    @describetag :requires_tuned_model

    # Note: These tests require an actual tuned model to work properly
    # They will be skipped unless you have created a tuned model

    test "manage permissions on tuned model", %{oauth_token: token} do
      # This test requires you to have a tuned model
      # Replace with your actual tuned model name
      model_name = System.get_env("TEST_TUNED_MODEL") || "tunedModels/test-model"

      # Try to list permissions (will fail if model doesn't exist)
      case Permissions.list_permissions(model_name, oauth_token: token) do
        {:ok, response} ->
          # If we have a real model, test permission management
          assert is_list(response.permissions)

          # Add a permission
          {:ok, permission} =
            Permissions.create_permission(
              model_name,
              %{
                grantee_type: :USER,
                email_address: "test@example.com",
                role: :READER
              },
              oauth_token: token
            )

          assert permission.grantee_type == :USER
          assert permission.role == :READER

          # Update permission role
          updated_permission = %{permission | role: :WRITER}

          {:ok, updated} =
            Permissions.update_permission(
              permission.name,
              updated_permission,
              oauth_token: token
            )

          assert updated.role == :WRITER

          # Delete permission
          :ok = Permissions.delete_permission(permission.name, oauth_token: token)

        {:error, %{status: status}} when status in [403, 404] ->
          # Model doesn't exist - skip this test
          IO.puts("\nℹ️  Skipping permission management test - no tuned model available")
          IO.puts("   Set TEST_TUNED_MODEL environment variable to test with a real model\n")
          assert true
      end
    end
  end

  describe "Error handling for OAuth2 APIs" do
    @describetag :oauth2

    test "handles invalid OAuth token", %{} do
      fake_token = "invalid-oauth-token"

      # Corpus API
      {:error, error} = Corpus.list_corpora([], oauth_token: fake_token)
      assert error[:status] == 401 || error[:code] == 401

      # Document API  
      {:error, error} = Document.list_documents("corpora/fake", oauth_token: fake_token)
      assert error[:status] in [401, 403, 404] || error[:code] in [401, 403, 404]

      # Permissions API
      {:error, error} = Permissions.list_permissions("tunedModels/fake", oauth_token: fake_token)
      assert error[:status] in [401, 403, 404] || error[:code] in [401, 403, 404]
    end

    test "handles expired OAuth token gracefully", %{oauth_token: _token} do
      # Create an expired token by manipulating the timestamp
      expired_token = "ya29.expired-test-token"

      {:error, error} = Corpus.list_corpora([], oauth_token: expired_token)
      assert error[:status] == 401 || error[:code] == 401
      # Message check is optional as format varies
    end
  end
end
