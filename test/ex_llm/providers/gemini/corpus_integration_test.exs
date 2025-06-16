defmodule ExLLM.Gemini.CorpusIntegrationTest do
  use ExUnit.Case, async: false

  alias ExLLM.Gemini.Corpus

  @moduletag :integration
  @moduletag :gemini_corpus_integration

  describe "corpus CRUD operations with API" do
    @describetag :skip_without_oauth
    setup do
      oauth_token = System.get_env("GEMINI_OAUTH_TOKEN")

      if is_nil(oauth_token) do
        {:skip, "GEMINI_OAUTH_TOKEN not set"}
      else
        {:ok, oauth_token: oauth_token}
      end
    end

    test "creates corpus with auto-generated name", %{oauth_token: oauth_token} do
      opts = [oauth_token: oauth_token]

      {:ok, corpus} =
        Corpus.create_corpus(
          %{
            display_name: "Test Corpus #{System.system_time(:second)}"
          },
          opts
        )

      assert corpus.name != nil
      assert String.starts_with?(corpus.name, "corpora/")
      assert corpus.display_name != nil
      assert corpus.create_time != nil
      assert corpus.update_time != nil

      # Clean up - delete the created corpus
      Corpus.delete_corpus(corpus.name, opts)
    end

    test "creates corpus with specified name", %{oauth_token: oauth_token} do
      corpus_id = "test-corpus-#{System.system_time(:second)}"
      corpus_name = "corpora/#{corpus_id}"

      opts = [oauth_token: oauth_token]

      {:ok, corpus} =
        Corpus.create_corpus(
          %{
            name: corpus_name,
            display_name: "Named Test Corpus"
          },
          opts
        )

      assert corpus.name == corpus_name
      assert corpus.display_name == "Named Test Corpus"

      # Clean up
      Corpus.delete_corpus(corpus.name, opts)
    end

    test "gets corpus information", %{oauth_token: oauth_token} do
      opts = [oauth_token: oauth_token]

      # Create a corpus first
      {:ok, created_corpus} =
        Corpus.create_corpus(
          %{
            display_name: "Get Test Corpus"
          },
          opts
        )

      # Get the corpus
      {:ok, retrieved_corpus} = Corpus.get_corpus(created_corpus.name, opts)

      assert retrieved_corpus.name == created_corpus.name
      assert retrieved_corpus.display_name == created_corpus.display_name
      assert retrieved_corpus.create_time == created_corpus.create_time

      # Clean up
      Corpus.delete_corpus(created_corpus.name, opts)
    end

    test "updates corpus display name", %{oauth_token: oauth_token} do
      opts = [oauth_token: oauth_token]

      # Create a corpus first
      {:ok, corpus} =
        Corpus.create_corpus(
          %{
            display_name: "Original Name"
          },
          opts
        )

      # Update the corpus
      {:ok, updated_corpus} =
        Corpus.update_corpus(
          corpus.name,
          %{
            display_name: "Updated Name"
          },
          ["displayName"],
          opts
        )

      assert updated_corpus.name == corpus.name
      assert updated_corpus.display_name == "Updated Name"
      assert updated_corpus.update_time != corpus.update_time

      # Verify the update persisted
      {:ok, retrieved_corpus} = Corpus.get_corpus(corpus.name, opts)
      assert retrieved_corpus.display_name == "Updated Name"

      # Clean up
      Corpus.delete_corpus(corpus.name, opts)
    end

    test "lists corpora with pagination", %{oauth_token: oauth_token} do
      opts = [oauth_token: oauth_token]

      # Create a few corpora for testing
      corpus_names =
        for i <- 1..3 do
          {:ok, corpus} =
            Corpus.create_corpus(
              %{
                display_name: "List Test Corpus #{i}"
              },
              opts
            )

          corpus.name
        end

      # List all corpora
      {:ok, response} = Corpus.list_corpora(%{}, opts)

      assert length(response.corpora) >= 3

      assert Enum.all?(response.corpora, fn corpus ->
               String.starts_with?(corpus.name, "corpora/")
             end)

      # Test pagination with page size
      {:ok, page_response} = Corpus.list_corpora(%{page_size: 2}, opts)

      assert length(page_response.corpora) <= 2

      # Clean up
      for corpus_name <- corpus_names do
        Corpus.delete_corpus(corpus_name, opts)
      end
    end

    test "deletes corpus", %{oauth_token: oauth_token} do
      opts = [oauth_token: oauth_token]

      # Create a corpus first
      {:ok, corpus} =
        Corpus.create_corpus(
          %{
            display_name: "Delete Test Corpus"
          },
          opts
        )

      # Delete the corpus
      :ok = Corpus.delete_corpus(corpus.name, opts)

      # Verify it's deleted
      {:error, error} = Corpus.get_corpus(corpus.name, opts)
      assert error.status in [404]
    end

    test "queries empty corpus", %{oauth_token: oauth_token} do
      opts = [oauth_token: oauth_token]

      # Create an empty corpus
      {:ok, corpus} =
        Corpus.create_corpus(
          %{
            display_name: "Query Test Corpus"
          },
          opts
        )

      # Query the empty corpus
      {:ok, response} = Corpus.query_corpus(corpus.name, "test query", %{}, opts)

      assert response.relevant_chunks == []

      # Clean up
      Corpus.delete_corpus(corpus.name, opts)
    end

    test "handles error cases", %{oauth_token: oauth_token} do
      opts = [oauth_token: oauth_token]

      # Test getting non-existent corpus
      {:error, error} = Corpus.get_corpus("corpora/non-existent", opts)
      assert error.status == 404

      # Test updating non-existent corpus
      {:error, error} =
        Corpus.update_corpus(
          "corpora/non-existent",
          %{
            display_name: "New Name"
          },
          ["displayName"],
          opts
        )

      assert error.status == 404

      # Test deleting non-existent corpus
      {:error, error} = Corpus.delete_corpus("corpora/non-existent", opts)
      assert error.status == 404

      # Test querying non-existent corpus
      {:error, error} = Corpus.query_corpus("corpora/non-existent", "test", %{}, opts)
      assert error.status == 404
    end

    test "validates project corpus limit", %{oauth_token: oauth_token} do
      opts = [oauth_token: oauth_token]

      # List existing corpora to check current count
      {:ok, response} = Corpus.list_corpora(%{}, opts)
      current_count = length(response.corpora)

      # If we're at the limit (5), we should get an error creating more
      if current_count >= 5 do
        {:error, error} =
          Corpus.create_corpus(
            %{
              display_name: "Over Limit Corpus"
            },
            opts
          )

        assert error.status in [400, 429]
        assert String.contains?(String.downcase(error.message), "limit")
      end
    end
  end

  describe "corpus operations with API key" do
    @describetag :skip_without_api_key
    setup do
      api_key = System.get_env("GEMINI_API_KEY")

      if is_nil(api_key) do
        {:skip, "GEMINI_API_KEY not set"}
      else
        {:ok, api_key: api_key}
      end
    end

    test "API key authentication should fail for corpus operations", %{api_key: api_key} do
      opts = [api_key: api_key]

      # Corpus operations require OAuth2, not API keys
      # These should all fail with authentication errors

      {:error, error} = Corpus.create_corpus(%{display_name: "Test"}, opts)
      assert error.status in [401, 403]

      {:error, error} = Corpus.list_corpora(%{}, opts)
      assert error.status in [401, 403]

      {:error, error} = Corpus.get_corpus("corpora/test", opts)
      assert error.status in [401, 403]

      {:error, error} =
        Corpus.update_corpus("corpora/test", %{display_name: "New"}, ["displayName"], opts)

      assert error.status in [401, 403]

      {:error, error} = Corpus.delete_corpus("corpora/test", opts)
      assert error.status in [401, 403]

      {:error, error} = Corpus.query_corpus("corpora/test", "query", %{}, opts)
      assert error.status in [401, 403]
    end
  end

  describe "corpus query with metadata filters" do
    @describetag :skip_without_oauth
    @describetag :skip_without_content
    setup do
      oauth_token = System.get_env("GEMINI_OAUTH_TOKEN")
      test_corpus = System.get_env("GEMINI_TEST_CORPUS_WITH_CONTENT")

      cond do
        is_nil(oauth_token) ->
          {:skip, "GEMINI_OAUTH_TOKEN not set"}

        is_nil(test_corpus) ->
          {:skip, "GEMINI_TEST_CORPUS_WITH_CONTENT not set"}

        true ->
          {:ok, oauth_token: oauth_token, test_corpus: test_corpus}
      end
    end

    test "queries corpus with metadata filters", %{
      oauth_token: oauth_token,
      test_corpus: test_corpus
    } do
      opts = [oauth_token: oauth_token]

      # Query with string metadata filter
      metadata_filters = [
        %{
          key: "document.custom_metadata.category",
          conditions: [
            %{string_value: "technology", operation: "EQUAL"}
          ]
        }
      ]

      {:ok, response} =
        Corpus.query_corpus(
          test_corpus,
          "artificial intelligence",
          %{
            results_count: 5,
            metadata_filters: metadata_filters
          },
          opts
        )

      # Should return chunks (assuming the test corpus has content)
      assert is_list(response.relevant_chunks)

      # Each chunk should have a relevance score
      for chunk <- response.relevant_chunks do
        assert is_number(chunk.chunk_relevance_score)
        assert chunk.chunk_relevance_score >= 0.0
        assert chunk.chunk_relevance_score <= 1.0
        assert is_map(chunk.chunk)
      end
    end

    test "queries corpus with numeric metadata filter", %{
      oauth_token: oauth_token,
      test_corpus: test_corpus
    } do
      opts = [oauth_token: oauth_token]

      # Query with numeric metadata filter
      metadata_filters = [
        %{
          key: "chunk.custom_metadata.importance",
          conditions: [
            %{numeric_value: 0.5, operation: "GREATER_EQUAL"}
          ]
        }
      ]

      {:ok, response} =
        Corpus.query_corpus(
          test_corpus,
          "important information",
          %{
            results_count: 3,
            metadata_filters: metadata_filters
          },
          opts
        )

      assert is_list(response.relevant_chunks)
    end

    test "queries corpus with multiple metadata filters", %{
      oauth_token: oauth_token,
      test_corpus: test_corpus
    } do
      opts = [oauth_token: oauth_token]

      # Query with multiple metadata filters (AND logic)
      metadata_filters = [
        %{
          key: "document.custom_metadata.type",
          conditions: [
            %{string_value: "article", operation: "EQUAL"},
            %{string_value: "blog", operation: "EQUAL"}
          ]
        },
        %{
          key: "chunk.custom_metadata.length",
          conditions: [
            %{numeric_value: 100, operation: "GREATER"}
          ]
        }
      ]

      {:ok, response} =
        Corpus.query_corpus(
          test_corpus,
          "comprehensive guide",
          %{
            results_count: 10,
            metadata_filters: metadata_filters
          },
          opts
        )

      assert is_list(response.relevant_chunks)
    end
  end
end
