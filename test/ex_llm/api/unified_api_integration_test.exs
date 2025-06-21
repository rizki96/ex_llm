defmodule ExLLM.API.UnifiedAPIIntegrationTest do
  @moduledoc """
  Integration tests for the unified API to ensure excellent user experience.
  Tests cross-provider functionality and API consistency.
  """

  use ExUnit.Case, async: false
  import ExLLM.Testing.TestCacheHelpers

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :unified_api
  @moduletag :integration_test

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

  describe "unified API consistency" do
    test "all functions follow consistent error patterns for unsupported providers" do
      # Test that all unified API functions return consistent error messages
      # for providers that don't support them

      unsupported_combinations = [
        # File management - not supported by Anthropic
        {:upload_file, [:anthropic, "test.txt"],
         "File upload not supported for provider: anthropic"},
        {:list_files, [:anthropic], "File listing not supported for provider: anthropic"},
        {:get_file, [:anthropic, "file_id"],
         "File retrieval not supported for provider: anthropic"},
        {:delete_file, [:anthropic, "file_id"],
         "File deletion not supported for provider: anthropic"},

        # Context caching - only supported by Gemini
        {:create_cached_context, [:openai, %{}],
         "Context caching not supported for provider: openai"},
        {:get_cached_context, [:anthropic, "name"],
         "Context caching not supported for provider: anthropic"},

        # Knowledge bases - only supported by Gemini
        {:create_knowledge_base, [:openai, "kb"],
         "Knowledge base creation not supported for provider: openai"},
        {:semantic_search, [:anthropic, "kb", "query"],
         "Semantic search not supported for provider: anthropic"},

        # Fine-tuning - not supported by Anthropic
        {:create_fine_tune, [:anthropic, %{}],
         "Fine-tuning not supported for provider: anthropic"},
        {:list_fine_tunes, [:anthropic], "Fine-tuning not supported for provider: anthropic"},

        # Assistants - only supported by OpenAI
        {:create_assistant, [:gemini, %{}], "Assistants API not supported for provider: gemini"},
        {:create_thread, [:anthropic], "Assistants API not supported for provider: anthropic"},

        # Batch processing - only supported by Anthropic
        {:create_batch, [:openai, []], "Message batches not supported for provider: openai"},
        {:get_batch, [:gemini, "batch_id"], "Message batches not supported for provider: gemini"},

        # Token counting - only supported by Gemini
        {:count_tokens, [:openai, "model", "text"],
         "Token counting not supported for provider: openai"}
      ]

      for {function, args, expected_error} <- unsupported_combinations do
        result = apply(ExLLM, function, args)

        assert {:error, ^expected_error} = result,
               "Function #{function} with args #{inspect(args)} should return #{expected_error}, got #{inspect(result)}"
      end
    end

    test "all functions handle nil and invalid provider gracefully" do
      functions_with_args = [
        {:upload_file, ["test.txt"]},
        {:list_files, []},
        {:get_file, ["file_id"]},
        {:delete_file, ["file_id"]},
        {:create_cached_context, [%{}]},
        {:get_cached_context, ["name"]},
        {:create_knowledge_base, ["kb"]},
        {:semantic_search, ["kb", "query"]},
        {:create_fine_tune, [%{}]},
        {:list_fine_tunes, []},
        {:create_assistant, [%{}]},
        {:create_thread, []},
        {:create_batch, [[]]},
        {:get_batch, ["batch_id"]},
        {:count_tokens, ["model", "text"]}
      ]

      invalid_providers = [nil, "", :invalid_provider, 123, %{}, []]

      for {function, args} <- functions_with_args do
        for invalid_provider <- invalid_providers do
          result = apply(ExLLM, function, [invalid_provider | args])

          case result do
            {:error, _reason} ->
              :ok

            {:ok, _} ->
              flunk(
                "Function #{function} should return error for invalid provider #{inspect(invalid_provider)}"
              )

            other ->
              flunk(
                "Function #{function} returned unexpected result for invalid provider #{inspect(invalid_provider)}: #{inspect(other)}"
              )
          end
        end
      end
    end
  end

  describe "provider capability discovery" do
    test "can check which providers support which features" do
      # Test that we can programmatically determine which providers support which features

      providers = [:openai, :anthropic, :gemini, :groq, :mistral]

      for provider <- providers do
        # File management
        file_support =
          case ExLLM.upload_file(provider, "/tmp/nonexistent") do
            {:error, msg} when is_binary(msg) ->
              if String.contains?(msg, "not supported for provider"), do: false, else: true

            # Supported but failed for other reasons
            {:error, _other_reason} ->
              true

            {:ok, _} ->
              true
          end

        # Context caching
        cache_support =
          case ExLLM.create_cached_context(provider, %{}) do
            {:error, msg} when is_binary(msg) ->
              if String.contains?(msg, "not supported for provider"), do: false, else: true

            {:error, _other_reason} ->
              true

            {:ok, _} ->
              true
          end

        # Fine-tuning
        tuning_support =
          case ExLLM.create_fine_tune(provider, %{}) do
            {:error, msg} when is_binary(msg) ->
              if String.contains?(msg, "not supported for provider"), do: false, else: true

            {:error, _other_reason} ->
              true

            {:ok, _} ->
              true
          end

        # Assistants
        assistant_support =
          case ExLLM.create_assistant(provider, %{}) do
            {:error, msg} when is_binary(msg) ->
              if String.contains?(msg, "not supported for provider"), do: false, else: true

            {:error, _other_reason} ->
              true

            {:ok, _} ->
              true
          end

        # Batch processing
        batch_support =
          case ExLLM.create_batch(provider, []) do
            {:error, msg} when is_binary(msg) ->
              if String.contains?(msg, "not supported for provider"), do: false, else: true

            {:error, _other_reason} ->
              true

            {:ok, _} ->
              true
          end

        # Token counting
        token_support =
          case ExLLM.count_tokens(provider, "model", "text") do
            {:error, msg} when is_binary(msg) ->
              if String.contains?(msg, "not supported for provider"), do: false, else: true

            {:error, _other_reason} ->
              true

            {:ok, _} ->
              true
          end

        capabilities = %{
          file_management: file_support,
          context_caching: cache_support,
          fine_tuning: tuning_support,
          assistants: assistant_support,
          batch_processing: batch_support,
          token_counting: token_support
        }

        IO.puts("Provider #{provider} capabilities: #{inspect(capabilities)}")

        # Verify expected capabilities based on our knowledge
        case provider do
          :gemini ->
            assert capabilities.context_caching == true
            assert capabilities.token_counting == true

          :openai ->
            assert capabilities.assistants == true

          :anthropic ->
            assert capabilities.batch_processing == true

          _ ->
            # Other providers - just ensure we get consistent responses
            :ok
        end
      end
    end
  end

  describe "unified API user experience" do
    test "provides helpful error messages for common mistakes" do
      # Test that the API provides helpful error messages for common user mistakes

      # Wrong parameter types
      assert {:error, _} = ExLLM.upload_file(:gemini, nil)
      assert {:error, _} = ExLLM.count_tokens(:gemini, nil, "text")
      assert {:error, _} = ExLLM.create_cached_context(:gemini, "not_a_map")

      # Empty or invalid data
      assert {:error, _} = ExLLM.create_knowledge_base(:gemini, "")
      assert {:error, _} = ExLLM.semantic_search(:gemini, "kb", nil)
      assert {:error, _} = ExLLM.create_fine_tune(:gemini, %{})
    end

    test "maintains consistent return value structure" do
      # Test that all functions return either {:ok, result} or {:error, reason}

      functions_to_test = [
        {ExLLM, :upload_file, [:invalid_provider, "test.txt"]},
        {ExLLM, :list_files, [:invalid_provider]},
        {ExLLM, :create_cached_context, [:invalid_provider, %{}]},
        {ExLLM, :create_knowledge_base, [:invalid_provider, "kb"]},
        {ExLLM, :create_fine_tune, [:invalid_provider, %{}]},
        {ExLLM, :create_assistant, [:invalid_provider, %{}]},
        {ExLLM, :create_batch, [:invalid_provider, []]},
        {ExLLM, :count_tokens, [:invalid_provider, "model", "text"]}
      ]

      for {module, function, args} <- functions_to_test do
        result = apply(module, function, args)

        case result do
          {:ok, _} -> :ok
          {:error, _} -> :ok
          other -> flunk("Function #{function} returned invalid format: #{inspect(other)}")
        end
      end
    end

    test "handles concurrent requests gracefully" do
      # Test that the unified API can handle concurrent requests without issues

      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            # Mix of different API calls
            case rem(i, 3) do
              0 -> ExLLM.list_files(:invalid_provider)
              1 -> ExLLM.create_cached_context(:invalid_provider, %{})
              2 -> ExLLM.count_tokens(:invalid_provider, "model", "text")
            end
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should return error tuples for invalid provider
      for result <- results do
        assert {:error, _} = result
      end
    end
  end

  describe "unified API documentation compliance" do
    test "all functions have proper typespecs" do
      # This test ensures that all unified API functions have proper typespecs
      # We can't directly test typespecs, but we can ensure functions exist and behave consistently

      unified_api_functions = [
        :upload_file,
        :list_files,
        :get_file,
        :delete_file,
        :create_cached_context,
        :get_cached_context,
        :update_cached_context,
        :delete_cached_context,
        :list_cached_contexts,
        :create_knowledge_base,
        :list_knowledge_bases,
        :get_knowledge_base,
        :delete_knowledge_base,
        :add_document,
        :list_documents,
        :get_document,
        :delete_document,
        :semantic_search,
        :create_fine_tune,
        :list_fine_tunes,
        :get_fine_tune,
        :cancel_fine_tune,
        :create_assistant,
        :list_assistants,
        :get_assistant,
        :update_assistant,
        :delete_assistant,
        :create_thread,
        :create_message,
        :run_assistant,
        :create_batch,
        :get_batch,
        :cancel_batch,
        :count_tokens
      ]

      for function <- unified_api_functions do
        assert function_exported?(ExLLM, function, 2) or
                 function_exported?(ExLLM, function, 3) or
                 function_exported?(ExLLM, function, 4),
               "Function #{function} should be exported from ExLLM module"
      end
    end

    test "all functions accept options parameter" do
      # Test that all unified API functions can accept an options parameter

      functions_with_minimal_args = [
        {:upload_file, [:invalid_provider, "test.txt", []]},
        {:list_files, [:invalid_provider, []]},
        {:get_file, [:invalid_provider, "file_id", []]},
        {:delete_file, [:invalid_provider, "file_id", []]},
        {:create_cached_context, [:invalid_provider, %{}, []]},
        {:get_cached_context, [:invalid_provider, "name", []]},
        {:create_knowledge_base, [:invalid_provider, "kb", []]},
        {:semantic_search, [:invalid_provider, "kb", "query", []]},
        {:create_fine_tune, [:invalid_provider, %{}, []]},
        {:list_fine_tunes, [:invalid_provider, []]},
        {:create_assistant, [:invalid_provider, []]},
        {:create_batch, [:invalid_provider, [], []]},
        {:count_tokens, [:invalid_provider, "model", "text"]}
      ]

      for {function, args} <- functions_with_minimal_args do
        result = apply(ExLLM, function, args)
        # Should return error for invalid provider, but not crash
        assert {:error, _} = result
      end
    end
  end
end
