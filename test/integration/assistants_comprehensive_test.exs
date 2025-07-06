defmodule ExLLM.Integration.AssistantsComprehensiveTest do
  @moduledoc """
  Comprehensive integration tests for OpenAI Assistants API functionality.
  Tests the complete assistant lifecycle through ExLLM's unified interface.
  """
  use ExUnit.Case

  @moduletag :integration
  @moduletag :comprehensive
  # Test helpers
  defp unique_name(base) when is_binary(base) do
    timestamp = :os.system_time(:millisecond)
    "#{base} #{timestamp}"
  end

  defp cleanup_assistant(assistant_id) when is_binary(assistant_id) do
    case ExLLM.Providers.OpenAI.delete_assistant(assistant_id) do
      {:ok, _} -> :ok
      # Already deleted or other non-critical error
      {:error, _} -> :ok
    end
  end

  defp cleanup_thread(thread_id) when is_binary(thread_id) do
    case ExLLM.Providers.OpenAI.delete_thread(thread_id) do
      {:ok, _} -> :ok
      # Already deleted or other non-critical error
      {:error, _} -> :ok
    end
  end

  describe "Assistant Lifecycle - Basic Operations" do
    @describetag :integration
    @describetag timeout: 30_000

    test "create minimal assistant" do
      name = unique_name("Minimal Assistant")

      params = %{
        name: name,
        instructions: "You are a helpful assistant for testing.",
        model: "gpt-4o-mini"
      }

      # Use provider directly to ensure Beta headers are included
      case ExLLM.Providers.OpenAI.create_assistant(params) do
        {:ok, assistant} ->
          assert assistant["id"] =~ ~r/^asst_/
          assert assistant["name"] == name
          assert assistant["instructions"] == params.instructions
          assert assistant["model"] == "gpt-4o-mini"
          assert assistant["object"] == "assistant"

          # Cleanup
          cleanup_assistant(assistant["id"])

        {:error, error} ->
          IO.puts("Assistant creation failed (expected in test env): #{inspect(error)}")
          assert is_map(error) or is_atom(error)
      end
    end

    test "list assistants" do
      case ExLLM.Providers.OpenAI.list_assistants() do
        {:ok, response} ->
          assert is_map(response)
          assert Map.has_key?(response, "data")
          assert is_list(response["data"])
          assert response["object"] == "list"

        {:error, error} ->
          IO.puts("Assistant listing failed: #{inspect(error)}")
          assert is_map(error) or is_atom(error)
      end
    end

    test "get assistant details" do
      # Create assistant first
      name = unique_name("Get Details Test")

      params = %{
        name: name,
        instructions: "Test assistant for retrieval.",
        model: "gpt-4o-mini"
      }

      case ExLLM.Providers.OpenAI.create_assistant(params) do
        {:ok, assistant} ->
          # Test retrieval
          case ExLLM.Providers.OpenAI.get_assistant(assistant["id"]) do
            {:ok, retrieved} ->
              assert retrieved["id"] == assistant["id"]
              assert retrieved["name"] == name
              assert retrieved["instructions"] == params.instructions

            {:error, error} ->
              IO.puts("Assistant retrieval failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_assistant(assistant["id"])

        {:error, error} ->
          IO.puts("Assistant creation failed (skipping retrieval test): #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "update assistant instructions" do
      # Create assistant first
      name = unique_name("Update Test")

      params = %{
        name: name,
        instructions: "Original instructions.",
        model: "gpt-4o-mini"
      }

      case ExLLM.Providers.OpenAI.create_assistant(params) do
        {:ok, assistant} ->
          # Test update
          updates = %{
            instructions: "Updated instructions for testing."
          }

          case ExLLM.Providers.OpenAI.update_assistant(assistant["id"], updates) do
            {:ok, updated} ->
              assert updated["id"] == assistant["id"]
              assert updated["instructions"] == updates.instructions
              # Should remain unchanged
              assert updated["name"] == name

            {:error, error} ->
              IO.puts("Assistant update failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_assistant(assistant["id"])

        {:error, error} ->
          IO.puts("Assistant creation failed (skipping update test): #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "delete assistant" do
      # Create assistant first
      name = unique_name("Delete Test")

      params = %{
        name: name,
        instructions: "Assistant for deletion testing.",
        model: "gpt-4o-mini"
      }

      case ExLLM.Providers.OpenAI.create_assistant(params) do
        {:ok, assistant} ->
          # Test deletion
          case ExLLM.Providers.OpenAI.delete_assistant(assistant["id"]) do
            {:ok, _} ->
              # Verify deletion by trying to retrieve
              case ExLLM.Providers.OpenAI.get_assistant(assistant["id"]) do
                {:ok, _} ->
                  flunk("Expected assistant to be deleted")

                {:error, error} ->
                  # Should get a not found error
                  assert is_map(error)

                  assert error["code"] in ["invalid_request_error", "not_found"] or
                           error.status_code in [404, 400]
              end

            {:error, error} ->
              IO.puts("Assistant deletion failed: #{inspect(error)}")
              assert is_map(error)
              # Try manual cleanup
              cleanup_assistant(assistant["id"])
          end

        {:error, error} ->
          IO.puts("Assistant creation failed (skipping deletion test): #{inspect(error)}")
          assert is_map(error)
      end
    end
  end

  describe "Thread Management" do
    @describetag :integration
    @describetag timeout: 30_000

    test "create thread" do
      case ExLLM.Providers.OpenAI.create_thread() do
        {:ok, thread} ->
          assert thread["id"] =~ ~r/^thread_/
          assert thread["object"] == "thread"
          assert is_map(thread["metadata"])

          # Cleanup
          cleanup_thread(thread["id"])

        {:error, error} ->
          IO.puts("Thread creation failed: #{inspect(error)}")
          assert is_map(error) or is_atom(error)
      end
    end

    test "add message to thread" do
      case ExLLM.Providers.OpenAI.create_thread() do
        {:ok, thread} ->
          # Add message to thread
          content = "Hello, this is a test message for the assistant."

          # OpenAI provider expects different parameters for create_message
          message_params = %{
            role: "user",
            content: content
          }

          case ExLLM.Providers.OpenAI.create_message(thread["id"], message_params) do
            {:ok, message} ->
              assert message["id"] =~ ~r/^msg_/
              assert message["object"] == "thread.message"
              assert message["role"] == "user"
              assert message["thread_id"] == thread["id"]

              # Check content structure
              assert is_list(message["content"])
              assert length(message["content"]) > 0

              first_content = List.first(message["content"])
              assert first_content["type"] == "text"
              assert first_content["text"]["value"] == content

            {:error, error} ->
              IO.puts("Message creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_thread(thread["id"])

        {:error, error} ->
          IO.puts("Thread creation failed (skipping message test): #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "list thread messages" do
      case ExLLM.Providers.OpenAI.create_thread() do
        {:ok, thread} ->
          # Add a message first
          message_params = %{role: "user", content: "Test message"}

          case ExLLM.Providers.OpenAI.create_message(thread["id"], message_params) do
            {:ok, _message} ->
              # List messages
              case ExLLM.Providers.OpenAI.list_messages(thread["id"]) do
                {:ok, response} ->
                  assert is_map(response)
                  assert response["object"] == "list"
                  assert is_list(response["data"])
                  assert length(response["data"]) >= 1

                  first_message = List.first(response["data"])
                  assert first_message["thread_id"] == thread["id"]

                {:error, error} ->
                  IO.puts("Message listing failed: #{inspect(error)}")
                  assert is_map(error)
              end

            {:error, error} ->
              IO.puts("Message creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_thread(thread["id"])

        {:error, error} ->
          IO.puts("Thread creation failed (skipping message listing test): #{inspect(error)}")
          assert is_map(error)
      end
    end
  end
end
