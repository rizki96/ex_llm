defmodule ExLLM.Gemini.CorpusTest do
  use ExUnit.Case, async: true

  alias ExLLM.Providers.Gemini.Corpus

  alias ExLLM.Providers.Gemini.Corpus.{
    CreateCorpusRequest,
    UpdateCorpusRequest,
    QueryCorpusRequest,
    ListCorporaRequest,
    ListCorporaResponse,
    QueryCorpusResponse,
    CorpusInfo,
    MetadataFilter,
    RelevantChunk
  }

  @moduletag :gemini_corpus

  describe "create_corpus/2" do
    test "builds valid create request with display name only" do
      request = Corpus.build_create_corpus_request(%{display_name: "Test Corpus"})

      assert %CreateCorpusRequest{} = request
      assert request.display_name == "Test Corpus"
      assert request.name == nil
    end

    test "builds valid create request with name and display name" do
      request =
        Corpus.build_create_corpus_request(%{
          name: "corpora/my-test-corpus",
          display_name: "My Test Corpus"
        })

      assert %CreateCorpusRequest{} = request
      assert request.name == "corpora/my-test-corpus"
      assert request.display_name == "My Test Corpus"
    end

    test "validates display name length" do
      long_name = String.duplicate("a", 513)

      assert_raise ArgumentError, ~r/Display name must be 512 characters or less/, fn ->
        Corpus.build_create_corpus_request(%{display_name: long_name})
      end
    end

    test "validates corpus name format" do
      # Valid names
      for name <- ["corpora/my-corpus", "corpora/test-123", "corpora/a"] do
        request = Corpus.build_create_corpus_request(%{name: name, display_name: "Test"})
        assert request.name == name
      end

      # Invalid names
      invalid_names = [
        # No corpora/ prefix
        "invalid-format",
        # Starts with dash
        "corpora/-invalid",
        # Ends with dash
        "corpora/invalid-",
        # Uppercase
        "corpora/INVALID",
        # Underscore
        "corpora/has_underscore",
        # Too long
        "corpora/" <> String.duplicate("a", 41)
      ]

      for name <- invalid_names do
        assert_raise ArgumentError, ~r/Invalid corpus name format/, fn ->
          Corpus.build_create_corpus_request(%{name: name, display_name: "Test"})
        end
      end
    end

    test "allows empty corpus for auto-generation" do
      request = Corpus.build_create_corpus_request(%{})
      assert %CreateCorpusRequest{} = request
      assert request.name == nil
      assert request.display_name == nil
    end
  end

  describe "list_corpora/1" do
    test "builds valid list request with default parameters" do
      request = Corpus.build_list_corpora_request(%{})

      assert %ListCorporaRequest{} = request
      assert request.page_size == nil
      assert request.page_token == nil
    end

    test "builds valid list request with pagination" do
      request =
        Corpus.build_list_corpora_request(%{
          page_size: 5,
          page_token: "next_page_token"
        })

      assert %ListCorporaRequest{} = request
      assert request.page_size == 5
      assert request.page_token == "next_page_token"
    end

    test "validates page size limits" do
      # Valid page sizes
      for size <- [1, 10, 20] do
        request = Corpus.build_list_corpora_request(%{page_size: size})
        assert request.page_size == size
      end

      # Invalid page sizes
      for size <- [0, 21, 100] do
        assert_raise ArgumentError, ~r/Page size must be between 1 and 20/, fn ->
          Corpus.build_list_corpora_request(%{page_size: size})
        end
      end
    end
  end

  describe "update_corpus/3" do
    test "builds valid update request" do
      request =
        Corpus.build_update_corpus_request(
          "corpora/test-corpus",
          %{
            display_name: "Updated Corpus Name"
          },
          ["displayName"]
        )

      assert %UpdateCorpusRequest{} = request
      assert request.name == "corpora/test-corpus"
      assert request.display_name == "Updated Corpus Name"
      assert request.update_mask == ["displayName"]
    end

    test "validates update mask contains only supported fields" do
      valid_fields = ["displayName"]

      for field <- valid_fields do
        request =
          Corpus.build_update_corpus_request("corpora/test", %{display_name: "Test"}, [field])

        assert request.update_mask == [field]
      end

      # Invalid field
      assert_raise ArgumentError, ~r/Update mask can only contain: displayName/, fn ->
        Corpus.build_update_corpus_request("corpora/test", %{display_name: "Test"}, [
          "invalidField"
        ])
      end
    end

    test "requires update mask to be provided" do
      assert_raise ArgumentError, ~r/Update mask is required/, fn ->
        Corpus.build_update_corpus_request("corpora/test", %{display_name: "Test"}, [])
      end
    end
  end

  describe "query_corpus/3" do
    test "builds valid query request with minimal parameters" do
      request = Corpus.build_query_corpus_request("corpora/test-corpus", "search query", %{})

      assert %QueryCorpusRequest{} = request
      assert request.name == "corpora/test-corpus"
      assert request.query == "search query"
      assert request.results_count == nil
      assert request.metadata_filters == []
    end

    test "builds valid query request with all parameters" do
      metadata_filters = [
        %{
          key: "document.custom_metadata.genre",
          conditions: [
            %{string_value: "drama", operation: "EQUAL"},
            %{string_value: "action", operation: "EQUAL"}
          ]
        },
        %{
          key: "chunk.custom_metadata.year",
          conditions: [
            %{numeric_value: 2020, operation: "GREATER_EQUAL"}
          ]
        }
      ]

      request =
        Corpus.build_query_corpus_request("corpora/test-corpus", "search query", %{
          results_count: 25,
          metadata_filters: metadata_filters
        })

      assert %QueryCorpusRequest{} = request
      assert request.results_count == 25
      assert length(request.metadata_filters) == 2

      first_filter = List.first(request.metadata_filters)
      assert %MetadataFilter{} = first_filter
      assert first_filter.key == "document.custom_metadata.genre"
      assert length(first_filter.conditions) == 2
    end

    test "validates results count limits" do
      # Valid counts
      for count <- [1, 50, 100] do
        request =
          Corpus.build_query_corpus_request("corpora/test", "query", %{results_count: count})

        assert request.results_count == count
      end

      # Invalid counts
      for count <- [0, 101, 200] do
        assert_raise ArgumentError, ~r/Results count must be between 1 and 100/, fn ->
          Corpus.build_query_corpus_request("corpora/test", "query", %{results_count: count})
        end
      end
    end

    test "validates metadata filter structure" do
      # Valid filter
      valid_filter = %{
        key: "document.title",
        conditions: [
          %{string_value: "test", operation: "EQUAL"}
        ]
      }

      request =
        Corpus.build_query_corpus_request("corpora/test", "query", %{
          metadata_filters: [valid_filter]
        })

      assert length(request.metadata_filters) == 1

      # Invalid filter - missing key
      invalid_filter = %{
        conditions: [%{string_value: "test", operation: "EQUAL"}]
      }

      assert_raise ArgumentError, ~r/Metadata filter key is required/, fn ->
        Corpus.build_query_corpus_request("corpora/test", "query", %{
          metadata_filters: [invalid_filter]
        })
      end

      # Invalid filter - missing conditions
      invalid_filter = %{key: "test"}

      assert_raise ArgumentError, ~r/Metadata filter conditions are required/, fn ->
        Corpus.build_query_corpus_request("corpora/test", "query", %{
          metadata_filters: [invalid_filter]
        })
      end
    end

    test "validates condition structure" do
      # Valid conditions
      valid_conditions = [
        %{string_value: "test", operation: "EQUAL"},
        %{numeric_value: 42, operation: "GREATER"},
        %{string_value: "include_me", operation: "INCLUDES"}
      ]

      for condition <- valid_conditions do
        filter = %{
          key: "test.key",
          conditions: [condition]
        }

        request =
          Corpus.build_query_corpus_request("corpora/test", "query", %{
            metadata_filters: [filter]
          })

        assert length(request.metadata_filters) == 1
      end

      # Invalid condition - missing operation
      invalid_condition = %{string_value: "test"}

      assert_raise ArgumentError, ~r/Condition operation is required/, fn ->
        Corpus.build_query_corpus_request("corpora/test", "query", %{
          metadata_filters: [%{key: "test", conditions: [invalid_condition]}]
        })
      end

      # Invalid condition - missing value
      invalid_condition = %{operation: "EQUAL"}

      assert_raise ArgumentError,
                   ~r/Condition must have either string_value or numeric_value/,
                   fn ->
                     Corpus.build_query_corpus_request("corpora/test", "query", %{
                       metadata_filters: [%{key: "test", conditions: [invalid_condition]}]
                     })
                   end
    end
  end

  describe "parse responses" do
    test "parses create corpus response" do
      response_body = %{
        "name" => "corpora/test-corpus-123",
        "displayName" => "Test Corpus",
        "createTime" => "2024-01-15T10:00:00Z",
        "updateTime" => "2024-01-15T10:00:00Z"
      }

      result = Corpus.parse_corpus_response(response_body)

      assert %CorpusInfo{} = result
      assert result.name == "corpora/test-corpus-123"
      assert result.display_name == "Test Corpus"
      assert result.create_time == "2024-01-15T10:00:00Z"
      assert result.update_time == "2024-01-15T10:00:00Z"
    end

    test "parses list corpora response" do
      response_body = %{
        "corpora" => [
          %{
            "name" => "corpora/corpus-1",
            "displayName" => "First Corpus",
            "createTime" => "2024-01-15T10:00:00Z",
            "updateTime" => "2024-01-15T10:00:00Z"
          },
          %{
            "name" => "corpora/corpus-2",
            "displayName" => "Second Corpus",
            "createTime" => "2024-01-15T11:00:00Z",
            "updateTime" => "2024-01-15T11:00:00Z"
          }
        ],
        "nextPageToken" => "next_page_token_123"
      }

      result = Corpus.parse_list_corpora_response(response_body)

      assert %ListCorporaResponse{} = result
      assert length(result.corpora) == 2
      assert result.next_page_token == "next_page_token_123"

      first_corpus = List.first(result.corpora)
      assert %CorpusInfo{} = first_corpus
      assert first_corpus.name == "corpora/corpus-1"
      assert first_corpus.display_name == "First Corpus"
    end

    test "parses query corpus response" do
      response_body = %{
        "relevantChunks" => [
          %{
            "chunkRelevanceScore" => 0.95,
            "chunk" => %{
              "name" => "corpora/test/documents/doc1/chunks/chunk1",
              "data" => %{
                "stringValue" => "This is the content of chunk 1"
              },
              "customMetadata" => [
                %{
                  "key" => "category",
                  "stringValue" => "technology"
                }
              ]
            }
          },
          %{
            "chunkRelevanceScore" => 0.87,
            "chunk" => %{
              "name" => "corpora/test/documents/doc2/chunks/chunk1",
              "data" => %{
                "stringValue" => "This is another relevant chunk"
              }
            }
          }
        ]
      }

      result = Corpus.parse_query_corpus_response(response_body)

      assert %QueryCorpusResponse{} = result
      assert length(result.relevant_chunks) == 2

      first_chunk = List.first(result.relevant_chunks)
      assert %RelevantChunk{} = first_chunk
      assert first_chunk.chunk_relevance_score == 0.95
      assert first_chunk.chunk["name"] == "corpora/test/documents/doc1/chunks/chunk1"
      assert first_chunk.chunk["data"]["stringValue"] == "This is the content of chunk 1"
    end

    test "handles empty responses" do
      # Empty list response
      empty_list = %{"corpora" => []}
      result = Corpus.parse_list_corpora_response(empty_list)
      assert %ListCorporaResponse{} = result
      assert result.corpora == []
      assert result.next_page_token == nil

      # Empty query response
      empty_query = %{"relevantChunks" => []}
      result = Corpus.parse_query_corpus_response(empty_query)
      assert %QueryCorpusResponse{} = result
      assert result.relevant_chunks == []
    end
  end

  describe "format functions" do
    test "formats operators correctly" do
      assert Corpus.format_operator("EQUAL") == :equal
      assert Corpus.format_operator("GREATER") == :greater
      assert Corpus.format_operator("LESS_EQUAL") == :less_equal
      assert Corpus.format_operator("INCLUDES") == :includes
      assert Corpus.format_operator("NOT_EQUAL") == :not_equal
      assert Corpus.format_operator("UNKNOWN_OP") == :unknown
    end

    test "formats operator to API string" do
      assert Corpus.operator_to_api_string(:equal) == "EQUAL"
      assert Corpus.operator_to_api_string(:greater) == "GREATER"
      assert Corpus.operator_to_api_string(:less_equal) == "LESS_EQUAL"
      assert Corpus.operator_to_api_string(:includes) == "INCLUDES"
      assert Corpus.operator_to_api_string(:not_equal) == "NOT_EQUAL"

      assert_raise ArgumentError, ~r/Invalid operator/, fn ->
        Corpus.operator_to_api_string(:invalid_op)
      end
    end
  end

  describe "validation helpers" do
    test "validates corpus name format helper" do
      # Valid names
      valid_names = [
        "corpora/test",
        "corpora/my-corpus-123",
        "corpora/a",
        "corpora/" <> String.duplicate("a", 40)
      ]

      for name <- valid_names do
        assert Corpus.valid_corpus_name?(name) == true
      end

      # Invalid names
      invalid_names = [
        # No prefix
        "test",
        # Empty ID
        "corpora/",
        # Starts with dash
        "corpora/-test",
        # Ends with dash
        "corpora/test-",
        # Uppercase
        "corpora/Test",
        # Underscore
        "corpora/test_name",
        # Too long
        "corpora/" <> String.duplicate("a", 41)
      ]

      for name <- invalid_names do
        assert Corpus.valid_corpus_name?(name) == false
      end
    end

    test "validates display name length helper" do
      assert Corpus.valid_display_name?("") == true
      assert Corpus.valid_display_name?("Test") == true
      assert Corpus.valid_display_name?(String.duplicate("a", 512)) == true
      assert Corpus.valid_display_name?(String.duplicate("a", 513)) == false
    end
  end
end
