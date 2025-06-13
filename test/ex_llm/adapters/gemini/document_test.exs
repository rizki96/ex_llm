defmodule ExLLM.Gemini.DocumentTest do
  use ExUnit.Case, async: true
  alias ExLLM.Gemini.Document

  @moduletag :gemini_document

  describe "build_create_request/1" do
    test "builds create request with display name only" do
      params = %{display_name: "Test Document"}

      request = Document.build_create_request(params)

      assert %{displayName: "Test Document"} = request
      refute Map.has_key?(request, :name)
      refute Map.has_key?(request, :customMetadata)
    end

    test "builds create request with custom name" do
      params = %{
        name: "corpora/test-corpus/documents/my-doc",
        display_name: "Custom Document"
      }

      request = Document.build_create_request(params)

      assert %{
               name: "corpora/test-corpus/documents/my-doc",
               displayName: "Custom Document"
             } = request
    end

    test "builds create request with custom metadata" do
      params = %{
        display_name: "Document with Metadata",
        custom_metadata: [
          %{key: "author", string_value: "John Doe"},
          %{key: "year", numeric_value: 2024},
          %{key: "tags", string_list_value: %{values: ["science", "research"]}}
        ]
      }

      request = Document.build_create_request(params)

      assert %{
               displayName: "Document with Metadata",
               customMetadata: metadata
             } = request

      assert length(metadata) == 3

      author_meta = Enum.find(metadata, &(&1.key == "author"))
      assert %{key: "author", stringValue: "John Doe"} = author_meta

      year_meta = Enum.find(metadata, &(&1.key == "year"))
      assert %{key: "year", numericValue: 2024} = year_meta

      tags_meta = Enum.find(metadata, &(&1.key == "tags"))
      assert %{key: "tags", stringListValue: %{values: ["science", "research"]}} = tags_meta
    end
  end

  describe "build_update_request/1" do
    test "builds update request with display name" do
      updates = %{display_name: "Updated Name"}

      request = Document.build_update_request(updates)

      assert %{displayName: "Updated Name"} = request
      refute Map.has_key?(request, :customMetadata)
    end

    test "builds update request with custom metadata" do
      updates = %{
        custom_metadata: [
          %{key: "status", string_value: "published"}
        ]
      }

      request = Document.build_update_request(updates)

      assert %{customMetadata: metadata} = request
      assert length(metadata) == 1
      assert %{key: "status", stringValue: "published"} = hd(metadata)
    end
  end

  describe "build_query_request/2" do
    test "builds basic query request" do
      query = "artificial intelligence"
      opts = %{}

      request = Document.build_query_request(query, opts)

      assert %{query: "artificial intelligence"} = request
      refute Map.has_key?(request, :resultsCount)
      refute Map.has_key?(request, :metadataFilters)
    end

    test "builds query request with results count" do
      query = "machine learning"
      opts = %{results_count: 5}

      request = Document.build_query_request(query, opts)

      assert %{
               query: "machine learning",
               resultsCount: 5
             } = request
    end

    test "builds query request with metadata filters" do
      query = "neural networks"

      opts = %{
        metadata_filters: [
          %{
            key: "chunk.custom_metadata.category",
            conditions: [
              %{operation: "EQUAL", string_value: "research"}
            ]
          }
        ]
      }

      request = Document.build_query_request(query, opts)

      assert %{
               query: "neural networks",
               metadataFilters: filters
             } = request

      assert length(filters) == 1
      filter = hd(filters)

      assert %{
               key: "chunk.custom_metadata.category",
               conditions: [
                 %{operation: "EQUAL", stringValue: "research"}
               ]
             } = filter
    end
  end

  describe "parse_document/1" do
    test "parses basic document response" do
      response = %{
        "name" => "corpora/test-corpus/documents/test-doc",
        "displayName" => "Test Document",
        "createTime" => "2024-01-01T00:00:00Z",
        "updateTime" => "2024-01-01T00:00:00Z"
      }

      document = Document.parse_document(response)

      assert %Document{
               name: "corpora/test-corpus/documents/test-doc",
               display_name: "Test Document",
               create_time: "2024-01-01T00:00:00Z",
               update_time: "2024-01-01T00:00:00Z"
             } = document

      assert document.custom_metadata == nil
    end

    test "parses document with custom metadata" do
      response = %{
        "name" => "corpora/test-corpus/documents/test-doc",
        "displayName" => "Test Document",
        "customMetadata" => [
          %{
            "key" => "author",
            "stringValue" => "John Doe"
          },
          %{
            "key" => "year",
            "numericValue" => 2024
          },
          %{
            "key" => "tags",
            "stringListValue" => %{
              "values" => ["science", "research"]
            }
          }
        ]
      }

      document = Document.parse_document(response)

      assert %Document{} = document
      assert length(document.custom_metadata) == 3

      author_meta = Enum.find(document.custom_metadata, &(&1.key == "author"))

      assert %Document.CustomMetadata{
               key: "author",
               string_value: "John Doe"
             } = author_meta

      year_meta = Enum.find(document.custom_metadata, &(&1.key == "year"))

      assert %Document.CustomMetadata{
               key: "year",
               numeric_value: 2024
             } = year_meta

      tags_meta = Enum.find(document.custom_metadata, &(&1.key == "tags"))

      assert %Document.CustomMetadata{
               key: "tags",
               string_list_value: %Document.StringList{values: ["science", "research"]}
             } = tags_meta
    end
  end

  describe "validation" do
    test "validates corpus name format" do
      # Valid corpus names
      assert :ok == Document.validate_corpus_name("corpora/test-corpus")
      assert :ok == Document.validate_corpus_name("corpora/corpus-with-dashes")
      assert :ok == Document.validate_corpus_name("corpora/corpus123")

      # Invalid corpus names
      assert {:error, %{message: message}} = Document.validate_corpus_name("invalid-corpus")
      assert String.contains?(message, "corpus name must be in format")

      assert {:error, %{message: _}} = Document.validate_corpus_name("corpora/")
      assert {:error, %{message: _}} = Document.validate_corpus_name("corpora/-invalid")
      assert {:error, %{message: _}} = Document.validate_corpus_name("corpora/invalid-")
    end

    test "validates document name format" do
      # Valid document names
      assert :ok == Document.validate_document_name("corpora/test-corpus/documents/test-doc")
      assert :ok == Document.validate_document_name("corpora/corpus-123/documents/doc-456")

      # Invalid document names
      assert {:error, %{message: message}} =
               Document.validate_document_name("invalid-document-name")

      assert String.contains?(message, "document name must be in format")

      assert {:error, %{message: _}} =
               Document.validate_document_name("corpora/test-corpus/documents/")

      assert {:error, %{message: _}} =
               Document.validate_document_name("corpora/test-corpus/documents/-invalid")
    end

    test "validates create params" do
      # Valid params
      assert :ok == Document.validate_create_params(%{display_name: "Test"})

      # Display name too long
      long_name = String.duplicate("a", 513)

      assert {:error, %{message: message}} =
               Document.validate_create_params(%{display_name: long_name})

      assert String.contains?(message, "display name must be no more than 512 characters")

      # Too many custom metadata items
      metadata = for i <- 1..21, do: %{key: "key#{i}", string_value: "value#{i}"}

      assert {:error, %{message: message}} =
               Document.validate_create_params(%{custom_metadata: metadata})

      assert String.contains?(message, "maximum of 20 CustomMetadata")
    end

    test "validates list options" do
      # Valid options
      assert :ok == Document.validate_list_opts(%{})
      assert :ok == Document.validate_list_opts(%{page_size: 10})
      assert :ok == Document.validate_list_opts(%{page_token: "token"})

      # Page size too large
      assert {:error, %{message: message}} = Document.validate_list_opts(%{page_size: 25})
      assert String.contains?(message, "maximum size limit is 20")
    end

    test "validates update params" do
      # Valid params with update mask
      assert :ok ==
               Document.validate_update_params(%{display_name: "New Name"}, ["displayName"])

      assert :ok ==
               Document.validate_update_params(%{custom_metadata: []}, ["customMetadata"])

      # Missing update mask
      assert {:error, %{message: message}} =
               Document.validate_update_params(%{display_name: "New Name"}, [])

      assert String.contains?(message, "updateMask is required")

      # Invalid update mask
      assert {:error, %{message: message}} =
               Document.validate_update_params(%{display_name: "New Name"}, ["invalidField"])

      assert String.contains?(message, "only supports updating displayName and customMetadata")
    end

    test "validates query params" do
      # Valid query
      assert :ok == Document.validate_query_params("test query", %{})
      assert :ok == Document.validate_query_params("test query", %{results_count: 50})

      # Empty query
      assert {:error, %{message: message}} = Document.validate_query_params("", %{})
      assert String.contains?(message, "query is required")

      # Results count too large
      assert {:error, %{message: message}} =
               Document.validate_query_params("test", %{results_count: 150})

      assert String.contains?(message, "maximum specified result count is 100")
    end
  end

  describe "struct definitions" do
    test "Document struct has correct fields" do
      document = %Document{
        name: "corpora/test/documents/doc",
        display_name: "Test Document"
      }

      assert document.name == "corpora/test/documents/doc"
      assert document.display_name == "Test Document"
      assert is_nil(document.custom_metadata)
      assert is_nil(document.create_time)
      assert is_nil(document.update_time)
    end

    test "CustomMetadata struct supports all value types" do
      # String value
      meta1 = %Document.CustomMetadata{
        key: "author",
        string_value: "John Doe"
      }

      assert meta1.key == "author"
      assert meta1.string_value == "John Doe"

      # Numeric value
      meta2 = %Document.CustomMetadata{
        key: "year",
        numeric_value: 2024
      }

      assert meta2.key == "year"
      assert meta2.numeric_value == 2024

      # String list value
      meta3 = %Document.CustomMetadata{
        key: "tags",
        string_list_value: %Document.StringList{values: ["ai", "ml"]}
      }

      assert meta3.key == "tags"
      assert meta3.string_list_value.values == ["ai", "ml"]
    end

    test "QueryResult and RelevantChunk structs" do
      query_result = %Document.QueryResult{
        relevant_chunks: [
          %Document.RelevantChunk{
            chunk_relevance_score: 0.95,
            chunk: %{"name" => "chunk1", "data" => %{"text" => "test"}}
          }
        ]
      }

      assert length(query_result.relevant_chunks) == 1
      chunk = hd(query_result.relevant_chunks)
      assert chunk.chunk_relevance_score == 0.95
      assert chunk.chunk["name"] == "chunk1"
    end

    test "ListResult struct" do
      list_result = %Document.ListResult{
        documents: [
          %Document{name: "doc1", display_name: "Document 1"}
        ],
        next_page_token: "next-token"
      }

      assert length(list_result.documents) == 1
      assert list_result.next_page_token == "next-token"
    end
  end
end
