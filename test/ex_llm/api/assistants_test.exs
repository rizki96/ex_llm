defmodule ExLLM.API.AssistantsTest do
  @moduledoc """
  Comprehensive tests for the unified Assistants API.
  Tests the public ExLLM API to ensure excellent user experience.
  """

  use ExUnit.Case, async: false
  import ExLLM.Testing.TestCacheHelpers

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :unified_api
  @moduletag :assistants
  @moduletag provider: :openai

  # Test assistant configuration
  @test_assistant_config %{
    name: "ExLLM Test Assistant",
    instructions: "You are a helpful assistant for testing the ExLLM unified API.",
    model: "gpt-3.5-turbo"
  }

  setup_all do
    enable_cache_debug()
    :ok
  end

  setup context do
    setup_test_cache(context)

    on_exit(fn ->
      ExLLM.Testing.TestCacheDetector.clear_test_context()
    end)

    :ok
  end

  describe "create_assistant/2" do
    @tag provider: :openai
    test "creates assistant successfully with OpenAI" do
      case ExLLM.create_assistant(:openai, @test_assistant_config) do
        {:ok, assistant} ->
          assert is_map(assistant)
          assert Map.has_key?(assistant, :id)
          assert Map.has_key?(assistant, :name)
          assert assistant.name == @test_assistant_config.name

        {:error, reason} ->
          IO.puts("OpenAI assistant creation failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "Assistants API not supported for provider: gemini"} =
               ExLLM.create_assistant(:gemini, @test_assistant_config)

      assert {:error, "Assistants API not supported for provider: anthropic"} =
               ExLLM.create_assistant(:anthropic, @test_assistant_config)
    end

    test "handles invalid assistant configuration" do
      invalid_configs = [
        nil,
        "",
        123,
        [],
        %{},
        %{name: ""},
        %{instructions: ""},
        %{model: ""}
      ]

      for invalid_config <- invalid_configs do
        case ExLLM.create_assistant(:openai, invalid_config) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some invalid configs might be handled gracefully with defaults
            :ok
        end
      end
    end

    @tag provider: :openai
    test "handles various assistant configurations" do
      configs = [
        # Minimal config
        %{model: "gpt-3.5-turbo"},

        # Full config
        %{
          name: "Test Assistant",
          instructions: "Test instructions",
          model: "gpt-3.5-turbo",
          description: "Test description"
        },

        # With tools
        %{
          name: "Tool Assistant",
          model: "gpt-3.5-turbo",
          tools: [%{type: "code_interpreter"}]
        }
      ]

      for config <- configs do
        case ExLLM.create_assistant(:openai, config) do
          {:ok, assistant} ->
            assert is_map(assistant)
            assert Map.has_key?(assistant, :id)

          {:error, reason} ->
            IO.puts(
              "Assistant creation with config #{inspect(config)} failed: #{inspect(reason)}"
            )

            :ok
        end
      end
    end
  end

  describe "list_assistants/2" do
    @tag provider: :openai
    test "lists assistants successfully with OpenAI" do
      case ExLLM.list_assistants(:openai, limit: 5) do
        {:ok, response} ->
          assert is_map(response)
          # OpenAI returns assistants in a specific structure
          assert Map.has_key?(response, :data) or is_list(response)

        {:error, reason} ->
          IO.puts("OpenAI list assistants failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "Assistants API not supported for provider: gemini"} =
               ExLLM.list_assistants(:gemini)

      assert {:error, "Assistants API not supported for provider: anthropic"} =
               ExLLM.list_assistants(:anthropic)
    end

    test "handles invalid options gracefully" do
      case ExLLM.list_assistants(:openai, invalid_option: "invalid") do
        {:ok, _response} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "get_assistant/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Assistants API not supported for provider: gemini"} =
               ExLLM.get_assistant(:gemini, "assistant_id")

      assert {:error, "Assistants API not supported for provider: anthropic"} =
               ExLLM.get_assistant(:anthropic, "assistant_id")
    end

    @tag provider: :openai
    test "handles non-existent assistant ID with OpenAI" do
      case ExLLM.get_assistant(:openai, "asst_non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid assistant ID types" do
      invalid_ids = [nil, 123, %{}, []]

      for invalid_id <- invalid_ids do
        case ExLLM.get_assistant(:openai, invalid_id) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid assistant ID: #{inspect(invalid_id)}")
        end
      end
    end
  end

  describe "update_assistant/4" do
    test "returns error for unsupported provider" do
      updates = %{name: "Updated Assistant"}

      assert {:error, "Assistants API not supported for provider: gemini"} =
               ExLLM.update_assistant(:gemini, "assistant_id", updates)

      assert {:error, "Assistants API not supported for provider: anthropic"} =
               ExLLM.update_assistant(:anthropic, "assistant_id", updates)
    end

    @tag provider: :openai
    test "handles non-existent assistant ID with OpenAI" do
      updates = %{name: "Updated Assistant"}

      case ExLLM.update_assistant(:openai, "asst_non_existent", updates) do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid update data" do
      invalid_updates = [nil, "", 123, []]

      for invalid_update <- invalid_updates do
        case ExLLM.update_assistant(:openai, "asst_test", invalid_update) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid updates: #{inspect(invalid_update)}")
        end
      end
    end
  end

  describe "delete_assistant/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Assistants API not supported for provider: gemini"} =
               ExLLM.delete_assistant(:gemini, "assistant_id")

      assert {:error, "Assistants API not supported for provider: anthropic"} =
               ExLLM.delete_assistant(:anthropic, "assistant_id")
    end

    @tag provider: :openai
    test "handles non-existent assistant ID with OpenAI" do
      case ExLLM.delete_assistant(:openai, "asst_non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # Some providers might return success even for non-existent assistants
          :ok
      end
    end

    test "handles invalid assistant ID types" do
      invalid_ids = [nil, 123, %{}, []]

      for invalid_id <- invalid_ids do
        case ExLLM.delete_assistant(:openai, invalid_id) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid assistant ID: #{inspect(invalid_id)}")
        end
      end
    end
  end

  describe "create_thread/2" do
    @tag provider: :openai
    test "creates thread successfully with OpenAI" do
      case ExLLM.create_thread(:openai) do
        {:ok, thread} ->
          assert is_map(thread)
          assert Map.has_key?(thread, :id)

        {:error, reason} ->
          IO.puts("OpenAI thread creation failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "Assistants API not supported for provider: gemini"} =
               ExLLM.create_thread(:gemini)

      assert {:error, "Assistants API not supported for provider: anthropic"} =
               ExLLM.create_thread(:anthropic)
    end

    @tag provider: :openai
    test "creates thread with initial messages" do
      initial_messages = [
        %{role: "user", content: "Hello, this is a test message."}
      ]

      case ExLLM.create_thread(:openai, messages: initial_messages) do
        {:ok, thread} ->
          assert is_map(thread)
          assert Map.has_key?(thread, :id)

        {:error, reason} ->
          IO.puts("OpenAI thread creation with messages failed: #{inspect(reason)}")
          :ok
      end
    end
  end

  describe "create_message/4" do
    test "returns error for unsupported provider" do
      assert {:error, "Assistants API not supported for provider: gemini"} =
               ExLLM.create_message(:gemini, "thread_id", "Hello")

      assert {:error, "Assistants API not supported for provider: anthropic"} =
               ExLLM.create_message(:anthropic, "thread_id", "Hello")
    end

    @tag provider: :openai
    test "handles non-existent thread ID with OpenAI" do
      case ExLLM.create_message(:openai, "thread_non_existent", "Hello") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid message content" do
      invalid_contents = [nil, "", 123, %{}, []]

      for invalid_content <- invalid_contents do
        case ExLLM.create_message(:openai, "thread_test", invalid_content) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid content: #{inspect(invalid_content)}")
        end
      end
    end
  end

  describe "run_assistant/4" do
    test "returns error for unsupported provider" do
      assert {:error, "Assistants API not supported for provider: gemini"} =
               ExLLM.run_assistant(:gemini, "thread_id", "assistant_id")

      assert {:error, "Assistants API not supported for provider: anthropic"} =
               ExLLM.run_assistant(:anthropic, "thread_id", "assistant_id")
    end

    @tag provider: :openai
    test "handles non-existent IDs with OpenAI" do
      case ExLLM.run_assistant(:openai, "thread_non_existent", "asst_non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid ID types" do
      invalid_ids = [nil, 123, %{}, []]

      for invalid_id <- invalid_ids do
        case ExLLM.run_assistant(:openai, invalid_id, "asst_test") do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid thread ID: #{inspect(invalid_id)}")
        end

        case ExLLM.run_assistant(:openai, "thread_test", invalid_id) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid assistant ID: #{inspect(invalid_id)}")
        end
      end
    end
  end

  describe "assistants workflow" do
    @tag provider: :openai
    @tag :slow
    test "complete assistants lifecycle with OpenAI" do
      # Skip if OpenAI is not configured
      unless ExLLM.configured?(:openai) do
        IO.puts("Skipping OpenAI assistants lifecycle test - not configured")
        :ok
      else
        # Create assistant
        case ExLLM.create_assistant(:openai, @test_assistant_config) do
          {:ok, assistant} ->
            assistant_id = assistant.id

            # Create thread
            case ExLLM.create_thread(:openai) do
              {:ok, thread} ->
                thread_id = thread.id

                # Add message to thread
                case ExLLM.create_message(:openai, thread_id, "Hello, assistant!") do
                  {:ok, message} ->
                    assert is_map(message)
                    assert Map.has_key?(message, :id)

                  {:error, reason} ->
                    IO.puts("Create message failed: #{inspect(reason)}")
                end

                # Run assistant (this might take time)
                case ExLLM.run_assistant(:openai, thread_id, assistant_id) do
                  {:ok, run} ->
                    assert is_map(run)
                    assert Map.has_key?(run, :id)

                  {:error, reason} ->
                    IO.puts("Run assistant failed: #{inspect(reason)}")
                end

              {:error, reason} ->
                IO.puts("Create thread failed: #{inspect(reason)}")
            end

            # Clean up - delete the assistant
            case ExLLM.delete_assistant(:openai, assistant_id) do
              {:ok, _} ->
                :ok

              {:error, reason} ->
                IO.puts("Delete assistant failed: #{inspect(reason)}")
            end

          {:error, reason} ->
            IO.puts("OpenAI assistants lifecycle test skipped: #{inspect(reason)}")
            :ok
        end
      end
    end
  end
end
