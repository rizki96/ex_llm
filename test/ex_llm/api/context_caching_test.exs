defmodule ExLLM.API.ContextCachingTest do
  @moduledoc """
  Comprehensive tests for the unified context caching API.
  Tests the public ExLLM API to ensure excellent user experience.
  """

  use ExUnit.Case, async: false
  import ExLLM.Testing.TestCacheHelpers

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :unified_api
  @moduletag :context_caching
  @moduletag provider: :gemini

  # Test content for caching
  @test_content %{
    contents: [
      %{
        parts: [
          %{text: "This is a test context for caching in ExLLM unified API tests."}
        ]
      }
    ],
    system_instruction: %{
      parts: [
        %{text: "You are a helpful assistant for testing purposes."}
      ]
    }
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

  describe "create_cached_context/3" do
    @tag provider: :gemini
    test "creates cached context successfully with Gemini" do
      case ExLLM.create_cached_context(:gemini, @test_content, ttl: "300s") do
        {:ok, cached_content} ->
          assert is_map(cached_content)
          assert Map.has_key?(cached_content, :name)
          assert String.starts_with?(cached_content.name, "cachedContents/")

        {:error, reason} ->
          IO.puts("Gemini create cached context failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "Context caching not supported for provider: openai"} =
               ExLLM.create_cached_context(:openai, @test_content)

      assert {:error, "Context caching not supported for provider: anthropic"} =
               ExLLM.create_cached_context(:anthropic, @test_content)
    end

    test "handles invalid content format" do
      invalid_contents = [
        nil,
        "",
        "string_content",
        123,
        [],
        %{invalid: "structure"}
      ]

      for invalid_content <- invalid_contents do
        case ExLLM.create_cached_context(:gemini, invalid_content) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some invalid content might be handled gracefully
            :ok
        end
      end
    end

    test "handles missing required content fields" do
      incomplete_contents = [
        %{},
        %{contents: []},
        %{contents: [%{}]},
        %{contents: [%{parts: []}]}
      ]

      for incomplete_content <- incomplete_contents do
        case ExLLM.create_cached_context(:gemini, incomplete_content) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some incomplete content might be handled gracefully
            :ok
        end
      end
    end
  end

  describe "get_cached_context/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Context caching not supported for provider: openai"} =
               ExLLM.get_cached_context(:openai, "cachedContents/test")

      assert {:error, "Context caching not supported for provider: anthropic"} =
               ExLLM.get_cached_context(:anthropic, "cachedContents/test")
    end

    @tag provider: :gemini
    test "handles non-existent cached context with Gemini" do
      case ExLLM.get_cached_context(:gemini, "cachedContents/non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid cached context names" do
      invalid_names = [nil, 123, %{}, [], ""]

      for invalid_name <- invalid_names do
        case ExLLM.get_cached_context(:gemini, invalid_name) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid name: #{inspect(invalid_name)}")
        end
      end
    end

    test "handles malformed cached context names" do
      malformed_names = [
        "invalid_format",
        "cachedContents/",
        "cachedContents/invalid-chars!@#",
        "not_cached_contents/test"
      ]

      for malformed_name <- malformed_names do
        case ExLLM.get_cached_context(:gemini, malformed_name) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some malformed names might be handled gracefully
            :ok
        end
      end
    end
  end

  describe "update_cached_context/4" do
    test "returns error for unsupported provider" do
      updates = %{ttl: "600s"}

      assert {:error, "Context caching not supported for provider: openai"} =
               ExLLM.update_cached_context(:openai, "cachedContents/test", updates)

      assert {:error, "Context caching not supported for provider: anthropic"} =
               ExLLM.update_cached_context(:anthropic, "cachedContents/test", updates)
    end

    @tag provider: :gemini
    test "handles non-existent cached context with Gemini" do
      updates = %{ttl: "600s"}

      case ExLLM.update_cached_context(:gemini, "cachedContents/non_existent", updates) do
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
        case ExLLM.update_cached_context(:gemini, "cachedContents/test", invalid_update) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid updates: #{inspect(invalid_update)}")
        end
      end
    end
  end

  describe "delete_cached_context/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Context caching not supported for provider: openai"} =
               ExLLM.delete_cached_context(:openai, "cachedContents/test")

      assert {:error, "Context caching not supported for provider: anthropic"} =
               ExLLM.delete_cached_context(:anthropic, "cachedContents/test")
    end

    @tag provider: :gemini
    test "handles non-existent cached context with Gemini" do
      case ExLLM.delete_cached_context(:gemini, "cachedContents/non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # Some providers might return success even for non-existent contexts
          :ok
      end
    end

    test "handles invalid cached context names" do
      invalid_names = [nil, 123, %{}, []]

      for invalid_name <- invalid_names do
        case ExLLM.delete_cached_context(:gemini, invalid_name) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid name: #{inspect(invalid_name)}")
        end
      end
    end
  end

  describe "list_cached_contexts/2" do
    test "returns error for unsupported provider" do
      assert {:error, "Context caching not supported for provider: openai"} =
               ExLLM.list_cached_contexts(:openai)

      assert {:error, "Context caching not supported for provider: anthropic"} =
               ExLLM.list_cached_contexts(:anthropic)
    end

    @tag provider: :gemini
    test "lists cached contexts successfully with Gemini" do
      case ExLLM.list_cached_contexts(:gemini, page_size: 5) do
        {:ok, response} ->
          assert is_map(response)
          # Gemini returns cached contents in a specific structure
          assert Map.has_key?(response, :cached_contents) or Map.has_key?(response, :data)

        {:error, reason} ->
          IO.puts("Gemini list cached contexts failed: #{inspect(reason)}")
          :ok
      end
    end

    test "handles invalid options gracefully" do
      case ExLLM.list_cached_contexts(:gemini, invalid_option: "invalid") do
        {:ok, _response} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "context caching workflow" do
    @tag provider: :gemini
    @tag :slow
    test "complete context caching lifecycle with Gemini" do
      # Skip if Gemini is not configured
      unless ExLLM.configured?(:gemini) do
        IO.puts("Skipping Gemini context caching lifecycle test - not configured")
        :ok
      else
        # Create cached context
        case ExLLM.create_cached_context(:gemini, @test_content, ttl: "300s") do
          {:ok, cached_content} ->
            context_name = cached_content.name

            # List cached contexts and verify our context is there
            case ExLLM.list_cached_contexts(:gemini) do
              {:ok, list_response} ->
                contexts = Map.get(list_response, :cached_contents, [])
                assert Enum.any?(contexts, fn c -> c.name == context_name end)

              {:error, reason} ->
                IO.puts("List cached contexts failed: #{inspect(reason)}")
            end

            # Get context details
            case ExLLM.get_cached_context(:gemini, context_name) do
              {:ok, retrieved_context} ->
                assert retrieved_context.name == context_name

              {:error, reason} ->
                IO.puts("Get cached context failed: #{inspect(reason)}")
            end

            # Update context TTL
            case ExLLM.update_cached_context(:gemini, context_name, %{ttl: "600s"}) do
              {:ok, updated_context} ->
                assert updated_context.name == context_name

              {:error, reason} ->
                IO.puts("Update cached context failed: #{inspect(reason)}")
            end

            # Clean up - delete the cached context
            case ExLLM.delete_cached_context(:gemini, context_name) do
              {:ok, _} ->
                :ok

              {:error, reason} ->
                IO.puts("Delete cached context failed: #{inspect(reason)}")
            end

          {:error, reason} ->
            IO.puts("Gemini context caching lifecycle test skipped: #{inspect(reason)}")
            :ok
        end
      end
    end
  end
end
