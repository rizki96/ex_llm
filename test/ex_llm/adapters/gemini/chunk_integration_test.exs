defmodule ExLLM.Adapters.Gemini.ChunkIntegrationTest do
  use ExUnit.Case, async: false

  alias ExLLM.Gemini.Chunk

  @api_key System.get_env("GEMINI_API_KEY") || "test-key"
  @moduletag :integration

  describe "Chunk API integration" do
    @tag :skip
    test "creates and manages a chunk with API key" do
      # Test requires a valid corpus and document to exist
      parent = "corpora/test-corpus/documents/test-doc"

      # Create chunk
      params = %{
        data: %{string_value: "This is a test chunk for integration testing."},
        custom_metadata: [
          %{key: "test_type", string_value: "integration"},
          %{key: "priority", numeric_value: 1}
        ]
      }

      assert {:ok, chunk} = Chunk.create_chunk(parent, params, api_key: @api_key)
      assert chunk.name
      assert chunk.data.string_value == "This is a test chunk for integration testing."
      assert chunk.state in [:STATE_PENDING_PROCESSING, :STATE_ACTIVE]

      chunk_name = chunk.name

      # Get chunk
      assert {:ok, retrieved} = Chunk.get_chunk(chunk_name, api_key: @api_key)
      assert retrieved.name == chunk_name
      assert retrieved.data.string_value == "This is a test chunk for integration testing."

      # Update chunk
      updates = %{
        data: %{string_value: "Updated content for integration test."}
      }

      opts = %{update_mask: "data"}

      assert {:ok, updated} = Chunk.update_chunk(chunk_name, updates, opts, api_key: @api_key)
      assert updated.data.string_value == "Updated content for integration test."

      # List chunks
      assert {:ok, list_result} = Chunk.list_chunks(parent, %{page_size: 10}, api_key: @api_key)
      assert is_list(list_result.chunks)

      # Find our created chunk in the list
      created_chunk = Enum.find(list_result.chunks, &(&1.name == chunk_name))
      assert created_chunk

      # Delete chunk
      assert :ok = Chunk.delete_chunk(chunk_name, api_key: @api_key)

      # Verify deletion
      assert {:error, %{code: status}} = Chunk.get_chunk(chunk_name, api_key: @api_key)
      assert status in [404, 403]
    end

    @tag :skip
    test "batch operations work correctly" do
      # Test requires a valid corpus and document to exist
      parent = "corpora/test-corpus/documents/test-doc"

      # Batch create chunks
      chunk_requests = [
        %{
          parent: parent,
          chunk: %{
            data: %{string_value: "First batch chunk content."},
            custom_metadata: [%{key: "batch_id", string_value: "batch_1"}]
          }
        },
        %{
          parent: parent,
          chunk: %{
            data: %{string_value: "Second batch chunk content."},
            custom_metadata: [%{key: "batch_id", string_value: "batch_1"}]
          }
        }
      ]

      assert {:ok, batch_result} =
               Chunk.batch_create_chunks(parent, chunk_requests, api_key: @api_key)

      assert length(batch_result.chunks) == 2

      [chunk1, chunk2] = batch_result.chunks
      assert chunk1.name
      assert chunk2.name
      assert chunk1.data.string_value == "First batch chunk content."
      assert chunk2.data.string_value == "Second batch chunk content."

      # Batch update chunks
      update_requests = [
        %{
          chunk: %{
            name: chunk1.name,
            data: %{string_value: "Updated first batch chunk."}
          },
          update_mask: "data"
        },
        %{
          chunk: %{
            name: chunk2.name,
            custom_metadata: [%{key: "status", string_value: "processed"}]
          },
          update_mask: "customMetadata"
        }
      ]

      assert {:ok, update_result} =
               Chunk.batch_update_chunks(parent, update_requests, api_key: @api_key)

      assert length(update_result.chunks) == 2

      # Batch delete chunks
      delete_requests = [
        %{name: chunk1.name},
        %{name: chunk2.name}
      ]

      assert :ok = Chunk.batch_delete_chunks(parent, delete_requests, api_key: @api_key)

      # Verify deletion
      assert {:error, %{code: status1}} = Chunk.get_chunk(chunk1.name, api_key: @api_key)
      assert {:error, %{code: status2}} = Chunk.get_chunk(chunk2.name, api_key: @api_key)
      assert status1 in [404, 403]
      assert status2 in [404, 403]
    end

    test "returns error for non-existent chunk" do
      non_existent_name = "corpora/non-existent/documents/non-existent/chunks/non-existent"

      assert {:error, %{code: status}} = Chunk.get_chunk(non_existent_name, api_key: @api_key)
      assert status in [400, 403, 404]
    end

    test "returns error for invalid document name in create" do
      invalid_parent = "invalid/document/name"
      params = %{data: %{string_value: "Test content"}}

      assert {:error, %{message: message}} =
               Chunk.create_chunk(invalid_parent, params, api_key: @api_key)

      assert String.contains?(message, "document name must be in format")
    end

    test "returns error for invalid chunk name in update" do
      invalid_name = "invalid/chunk/name"
      updates = %{data: %{string_value: "Updated content"}}
      opts = %{update_mask: "data"}

      assert {:error, %{message: message}} =
               Chunk.update_chunk(invalid_name, updates, opts, api_key: @api_key)

      assert String.contains?(message, "chunk name must be in format")
    end
  end
end
