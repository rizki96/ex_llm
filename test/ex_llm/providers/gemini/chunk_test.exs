defmodule ExLLM.Providers.Gemini.ChunkTest do
  use ExUnit.Case, async: true
  alias ExLLM.Gemini.Chunk

  @moduletag :gemini_chunk

  describe "build_create_request/1" do
    test "builds create request with text data only" do
      params = %{
        data: %{string_value: "This is a test chunk."}
      }

      request = Chunk.build_create_request(params)

      assert %{
               data: %{stringValue: "This is a test chunk."}
             } = request

      refute Map.has_key?(request, :name)
      refute Map.has_key?(request, :customMetadata)
    end

    test "builds create request with custom name" do
      params = %{
        name: "corpora/test-corpus/documents/test-doc/chunks/my-chunk",
        data: %{string_value: "Content with custom name."}
      }

      request = Chunk.build_create_request(params)

      assert %{
               name: "corpora/test-corpus/documents/test-doc/chunks/my-chunk",
               data: %{stringValue: "Content with custom name."}
             } = request
    end

    test "builds create request with custom metadata" do
      params = %{
        data: %{string_value: "Chunk with metadata."},
        custom_metadata: [
          %{key: "author", string_value: "Jane Doe"},
          %{key: "page", numeric_value: 42},
          %{key: "keywords", string_list_value: %{values: ["AI", "ML", "research"]}}
        ]
      }

      request = Chunk.build_create_request(params)

      assert %{
               data: %{stringValue: "Chunk with metadata."},
               customMetadata: metadata
             } = request

      assert length(metadata) == 3

      author_meta = Enum.find(metadata, &(&1.key == "author"))
      assert %{key: "author", stringValue: "Jane Doe"} = author_meta

      page_meta = Enum.find(metadata, &(&1.key == "page"))
      assert %{key: "page", numericValue: 42} = page_meta

      keywords_meta = Enum.find(metadata, &(&1.key == "keywords"))

      assert %{key: "keywords", stringListValue: %{values: ["AI", "ML", "research"]}} =
               keywords_meta
    end
  end

  describe "build_update_request/1" do
    test "builds update request with data only" do
      updates = %{
        data: %{string_value: "Updated chunk content."}
      }

      request = Chunk.build_update_request(updates)

      assert %{
               data: %{stringValue: "Updated chunk content."}
             } = request

      refute Map.has_key?(request, :customMetadata)
    end

    test "builds update request with custom metadata" do
      updates = %{
        custom_metadata: [
          %{key: "status", string_value: "reviewed"}
        ]
      }

      request = Chunk.build_update_request(updates)

      assert %{customMetadata: metadata} = request
      assert length(metadata) == 1
      assert %{key: "status", stringValue: "reviewed"} = hd(metadata)
    end

    test "builds update request with both data and metadata" do
      updates = %{
        data: %{string_value: "Updated content with metadata."},
        custom_metadata: [
          %{key: "version", numeric_value: 2}
        ]
      }

      request = Chunk.build_update_request(updates)

      assert %{
               data: %{stringValue: "Updated content with metadata."},
               customMetadata: [%{key: "version", numericValue: 2}]
             } = request
    end
  end

  describe "build_batch_create_request/1" do
    test "builds batch create request with multiple chunks" do
      chunks = [
        %{
          parent: "corpora/test-corpus/documents/test-doc",
          chunk: %{
            data: %{string_value: "First chunk content."}
          }
        },
        %{
          parent: "corpora/test-corpus/documents/test-doc",
          chunk: %{
            name: "corpora/test-corpus/documents/test-doc/chunks/chunk-2",
            data: %{string_value: "Second chunk content."},
            custom_metadata: [
              %{key: "priority", string_value: "high"}
            ]
          }
        }
      ]

      parent = "corpora/test-corpus/documents/test-doc"
      request = Chunk.build_batch_create_request(parent, chunks)

      assert %{requests: requests} = request
      assert length(requests) == 2

      [first_req, second_req] = requests

      assert %{
               parent: "corpora/test-corpus/documents/test-doc",
               chunk: %{data: %{stringValue: "First chunk content."}}
             } = first_req

      assert %{
               parent: "corpora/test-corpus/documents/test-doc",
               chunk: %{
                 name: "corpora/test-corpus/documents/test-doc/chunks/chunk-2",
                 data: %{stringValue: "Second chunk content."},
                 customMetadata: [%{key: "priority", stringValue: "high"}]
               }
             } = second_req
    end
  end

  describe "build_batch_update_request/1" do
    test "builds batch update request" do
      updates = [
        %{
          chunk: %{
            name: "corpora/test-corpus/documents/test-doc/chunks/chunk-1",
            data: %{string_value: "Updated first chunk."}
          },
          update_mask: "data"
        },
        %{
          chunk: %{
            name: "corpora/test-corpus/documents/test-doc/chunks/chunk-2",
            custom_metadata: [
              %{key: "status", string_value: "published"}
            ]
          },
          update_mask: "customMetadata"
        }
      ]

      request = Chunk.build_batch_update_request(updates)

      assert %{requests: requests} = request
      assert length(requests) == 2

      [first_req, second_req] = requests

      assert %{
               chunk: %{
                 name: "corpora/test-corpus/documents/test-doc/chunks/chunk-1",
                 data: %{stringValue: "Updated first chunk."}
               },
               updateMask: "data"
             } = first_req

      assert %{
               chunk: %{
                 name: "corpora/test-corpus/documents/test-doc/chunks/chunk-2",
                 customMetadata: [%{key: "status", stringValue: "published"}]
               },
               updateMask: "customMetadata"
             } = second_req
    end
  end

  describe "build_batch_delete_request/1" do
    test "builds batch delete request" do
      chunks = [
        %{name: "corpora/test-corpus/documents/test-doc/chunks/chunk-1"},
        %{name: "corpora/test-corpus/documents/test-doc/chunks/chunk-2"}
      ]

      request = Chunk.build_batch_delete_request(chunks)

      assert %{requests: requests} = request
      assert length(requests) == 2

      [first_req, second_req] = requests

      assert %{name: "corpora/test-corpus/documents/test-doc/chunks/chunk-1"} = first_req
      assert %{name: "corpora/test-corpus/documents/test-doc/chunks/chunk-2"} = second_req
    end
  end

  describe "parse_chunk/1" do
    test "parses basic chunk response" do
      response = %{
        "name" => "corpora/test-corpus/documents/test-doc/chunks/chunk-123",
        "data" => %{
          "stringValue" => "This is the chunk content."
        },
        "createTime" => "2024-01-01T00:00:00Z",
        "updateTime" => "2024-01-01T00:00:00Z",
        "state" => "STATE_ACTIVE"
      }

      chunk = Chunk.parse_chunk(response)

      assert %Chunk{
               name: "corpora/test-corpus/documents/test-doc/chunks/chunk-123",
               data: %Chunk.ChunkData{string_value: "This is the chunk content."},
               create_time: "2024-01-01T00:00:00Z",
               update_time: "2024-01-01T00:00:00Z",
               state: :STATE_ACTIVE
             } = chunk

      assert chunk.custom_metadata == nil
    end

    test "parses chunk with custom metadata" do
      response = %{
        "name" => "corpora/test-corpus/documents/test-doc/chunks/chunk-456",
        "data" => %{
          "stringValue" => "Chunk with metadata."
        },
        "customMetadata" => [
          %{
            "key" => "author",
            "stringValue" => "Alice Smith"
          },
          %{
            "key" => "confidence",
            "numericValue" => 0.95
          },
          %{
            "key" => "tags",
            "stringListValue" => %{
              "values" => ["important", "verified"]
            }
          }
        ],
        "state" => "STATE_PENDING_PROCESSING"
      }

      chunk = Chunk.parse_chunk(response)

      assert %Chunk{} = chunk
      assert length(chunk.custom_metadata) == 3
      assert chunk.state == :STATE_PENDING_PROCESSING

      author_meta = Enum.find(chunk.custom_metadata, &(&1.key == "author"))

      assert %Chunk.CustomMetadata{
               key: "author",
               string_value: "Alice Smith"
             } = author_meta

      confidence_meta = Enum.find(chunk.custom_metadata, &(&1.key == "confidence"))

      assert %Chunk.CustomMetadata{
               key: "confidence",
               numeric_value: 0.95
             } = confidence_meta

      tags_meta = Enum.find(chunk.custom_metadata, &(&1.key == "tags"))

      assert %Chunk.CustomMetadata{
               key: "tags",
               string_list_value: %Chunk.StringList{values: ["important", "verified"]}
             } = tags_meta
    end
  end

  describe "validation" do
    test "validates document name format" do
      # Valid document names
      assert :ok == Chunk.validate_document_name("corpora/test-corpus/documents/test-doc")
      assert :ok == Chunk.validate_document_name("corpora/corpus-123/documents/doc-456")

      # Invalid document names
      assert {:error, %{message: message}} = Chunk.validate_document_name("invalid-document-name")
      assert String.contains?(message, "document name must be in format")

      assert {:error, %{message: _}} =
               Chunk.validate_document_name("corpora/test-corpus/documents/")

      assert {:error, %{message: _}} =
               Chunk.validate_document_name("corpora/test-corpus/documents/-invalid")
    end

    test "validates chunk name format" do
      # Valid chunk names
      assert :ok ==
               Chunk.validate_chunk_name(
                 "corpora/test-corpus/documents/test-doc/chunks/chunk-123"
               )

      assert :ok ==
               Chunk.validate_chunk_name("corpora/corpus-456/documents/doc-789/chunks/abc123def")

      # Invalid chunk names
      assert {:error, %{message: message}} = Chunk.validate_chunk_name("invalid-chunk-name")
      assert String.contains?(message, "chunk name must be in format")

      assert {:error, %{message: _}} =
               Chunk.validate_chunk_name("corpora/test/documents/doc/chunks/")

      assert {:error, %{message: _}} =
               Chunk.validate_chunk_name("corpora/test/documents/doc/chunks/-invalid")

      assert {:error, %{message: _}} =
               Chunk.validate_chunk_name("corpora/test/documents/doc/chunks/invalid-")
    end

    test "validates create params" do
      # Valid params
      assert :ok == Chunk.validate_create_params(%{data: %{string_value: "Test content"}})

      # Missing data
      assert {:error, %{message: message}} = Chunk.validate_create_params(%{})
      assert String.contains?(message, "data is required")

      # Invalid data structure
      assert {:error, %{message: message}} = Chunk.validate_create_params(%{data: "invalid"})
      assert String.contains?(message, "data must contain string_value")

      # Empty string value
      assert {:error, %{message: message}} =
               Chunk.validate_create_params(%{data: %{string_value: ""}})

      assert String.contains?(message, "string_value cannot be empty")

      # Too many custom metadata items
      metadata = for i <- 1..21, do: %{key: "key#{i}", string_value: "value#{i}"}

      assert {:error, %{message: message}} =
               Chunk.validate_create_params(%{
                 data: %{string_value: "Test"},
                 custom_metadata: metadata
               })

      assert String.contains?(message, "maximum of 20 CustomMetadata")
    end

    test "validates list options" do
      # Valid options
      assert :ok == Chunk.validate_list_opts(%{})
      assert :ok == Chunk.validate_list_opts(%{page_size: 50})
      assert :ok == Chunk.validate_list_opts(%{page_token: "token"})

      # Page size too large
      assert {:error, %{message: message}} = Chunk.validate_list_opts(%{page_size: 150})
      assert String.contains?(message, "maximum size limit is 100")
    end

    test "validates update params" do
      # Valid params with update mask
      assert :ok ==
               Chunk.validate_update_params(%{data: %{string_value: "New content"}}, "data")

      assert :ok ==
               Chunk.validate_update_params(%{custom_metadata: []}, "customMetadata")

      # Missing update mask
      assert {:error, %{message: message}} =
               Chunk.validate_update_params(%{data: %{string_value: "New"}}, nil)

      assert String.contains?(message, "updateMask is required")

      # Invalid update mask
      assert {:error, %{message: message}} =
               Chunk.validate_update_params(%{data: %{string_value: "New"}}, "invalidField")

      assert String.contains?(message, "only supports updating data and customMetadata")

      # Empty string value when updating data
      assert {:error, %{message: message}} =
               Chunk.validate_update_params(%{data: %{string_value: ""}}, "data")

      assert String.contains?(message, "string_value cannot be empty")
    end

    test "validates batch create params" do
      # Valid batch
      chunks = [
        %{
          parent: "corpora/test/documents/doc",
          chunk: %{data: %{string_value: "Content 1"}}
        }
      ]

      assert :ok == Chunk.validate_batch_create_params(chunks)

      # Too many chunks
      chunks =
        for i <- 1..101 do
          %{
            parent: "corpora/test/documents/doc",
            chunk: %{data: %{string_value: "Content #{i}"}}
          }
        end

      assert {:error, %{message: message}} = Chunk.validate_batch_create_params(chunks)
      assert String.contains?(message, "maximum of 100 chunks")

      # Empty batch
      assert {:error, %{message: message}} = Chunk.validate_batch_create_params([])
      assert String.contains?(message, "at least one chunk")
    end
  end

  describe "struct definitions" do
    test "Chunk struct has correct fields" do
      chunk = %Chunk{
        name: "corpora/test/documents/doc/chunks/chunk1",
        data: %Chunk.ChunkData{string_value: "Test content"},
        state: :STATE_ACTIVE
      }

      assert chunk.name == "corpora/test/documents/doc/chunks/chunk1"
      assert chunk.data.string_value == "Test content"
      assert chunk.state == :STATE_ACTIVE
      assert is_nil(chunk.custom_metadata)
      assert is_nil(chunk.create_time)
      assert is_nil(chunk.update_time)
    end

    test "ChunkData struct supports string value" do
      data = %Chunk.ChunkData{string_value: "This is chunk content."}
      assert data.string_value == "This is chunk content."
    end

    test "CustomMetadata struct supports all value types" do
      # String value
      meta1 = %Chunk.CustomMetadata{
        key: "title",
        string_value: "Chapter 1"
      }

      assert meta1.key == "title"
      assert meta1.string_value == "Chapter 1"

      # Numeric value
      meta2 = %Chunk.CustomMetadata{
        key: "page_number",
        numeric_value: 42
      }

      assert meta2.key == "page_number"
      assert meta2.numeric_value == 42

      # String list value
      meta3 = %Chunk.CustomMetadata{
        key: "categories",
        string_list_value: %Chunk.StringList{values: ["fiction", "drama"]}
      }

      assert meta3.key == "categories"
      assert meta3.string_list_value.values == ["fiction", "drama"]
    end

    test "ListResult struct" do
      list_result = %Chunk.ListResult{
        chunks: [
          %Chunk{name: "chunk1", data: %Chunk.ChunkData{string_value: "Content 1"}},
          %Chunk{name: "chunk2", data: %Chunk.ChunkData{string_value: "Content 2"}}
        ],
        next_page_token: "next-token"
      }

      assert length(list_result.chunks) == 2
      assert list_result.next_page_token == "next-token"
    end

    test "BatchResult struct" do
      batch_result = %Chunk.BatchResult{
        chunks: [
          %Chunk{name: "chunk1", data: %Chunk.ChunkData{string_value: "Batch content 1"}},
          %Chunk{name: "chunk2", data: %Chunk.ChunkData{string_value: "Batch content 2"}}
        ]
      }

      assert length(batch_result.chunks) == 2
    end
  end
end
