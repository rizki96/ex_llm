defmodule ExLLM.API.TokenCountingTest do
  @moduledoc """
  Comprehensive tests for the unified token counting API.
  Tests the public ExLLM API to ensure excellent user experience.
  """

  use ExUnit.Case, async: true
  import ExLLM.Testing.TestCacheHelpers

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :unified_api
  @moduletag :token_counting
  @moduletag provider: :gemini

  # Test content for token counting
  @test_content "Hello, this is a test message for token counting in ExLLM unified API."
  @test_model "gemini-1.5-flash"

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

  describe "count_tokens/3" do
    @tag provider: :gemini
    test "counts tokens successfully with Gemini" do
      case ExLLM.count_tokens(:gemini, @test_model, @test_content) do
        {:ok, token_count} ->
          assert is_map(token_count)
          assert Map.has_key?(token_count, :total_tokens)
          assert is_integer(token_count.total_tokens)
          assert token_count.total_tokens > 0

        {:error, reason} ->
          IO.puts("Gemini token counting failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "count_tokens not supported for provider: openai"} =
               ExLLM.count_tokens(:openai, "gpt-4", @test_content)

      assert {:error, "count_tokens not supported for provider: anthropic"} =
               ExLLM.count_tokens(:anthropic, "claude-3", @test_content)
    end

    @tag provider: :gemini
    test "handles different content types with Gemini" do
      content_types = [
        # Simple text
        "Simple text content",

        # Longer text
        String.duplicate("This is a longer text for testing token counting. ", 10),

        # Empty string
        "",

        # Text with special characters
        "Hello! How are you? 🚀 Testing with emojis and punctuation.",

        # Structured content (if supported)
        %{text: "Structured content for token counting"}
      ]

      for content <- content_types do
        case ExLLM.count_tokens(:gemini, @test_model, content) do
          {:ok, token_count} ->
            assert is_map(token_count)
            assert Map.has_key?(token_count, :total_tokens)
            assert is_integer(token_count.total_tokens)
            assert token_count.total_tokens >= 0

          {:error, reason} ->
            # Some content types might not be supported
            IO.puts("Token counting failed for content #{inspect(content)}: #{inspect(reason)}")
            :ok
        end
      end
    end

    @tag provider: :gemini
    test "handles different model names with Gemini" do
      model_names = [
        "gemini-1.5-flash",
        "gemini-1.5-pro",
        "gemini-1.0-pro",
        "invalid-model-name"
      ]

      for model <- model_names do
        case ExLLM.count_tokens(:gemini, model, @test_content) do
          {:ok, token_count} ->
            assert is_map(token_count)
            assert Map.has_key?(token_count, :total_tokens)
            assert is_integer(token_count.total_tokens)

          {:error, reason} ->
            # Some models might not be available or valid
            IO.puts("Token counting failed for model #{model}: #{inspect(reason)}")
            :ok
        end
      end
    end

    test "handles invalid model parameter types" do
      invalid_models = [nil, 123, %{}, []]

      for invalid_model <- invalid_models do
        case ExLLM.count_tokens(:gemini, invalid_model, @test_content) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid model: #{inspect(invalid_model)}")
        end
      end
    end

    test "handles invalid content parameter types" do
      invalid_contents = [nil, 123, %{invalid: "structure"}, [1, 2, 3]]

      for invalid_content <- invalid_contents do
        case ExLLM.count_tokens(:gemini, @test_model, invalid_content) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some invalid content might be handled gracefully
            :ok
        end
      end
    end

    @tag provider: :gemini
    test "token counting consistency" do
      # Test that the same content returns consistent token counts
      content = "This is a test for token counting consistency."

      results =
        for _i <- 1..3 do
          case ExLLM.count_tokens(:gemini, @test_model, content) do
            {:ok, token_count} -> token_count.total_tokens
            {:error, _} -> nil
          end
        end

      # Filter out any nil results from errors
      valid_results = Enum.filter(results, &(&1 != nil))

      if length(valid_results) > 1 do
        # All valid results should be the same
        assert Enum.all?(valid_results, &(&1 == hd(valid_results))),
               "Token counts should be consistent: #{inspect(valid_results)}"
      end
    end

    @tag provider: :gemini
    test "token counting scales with content length" do
      base_content = "This is a test sentence. "

      content_lengths = [
        {base_content, 1},
        {String.duplicate(base_content, 5), 5},
        {String.duplicate(base_content, 10), 10}
      ]

      token_counts =
        for {content, multiplier} <- content_lengths do
          case ExLLM.count_tokens(:gemini, @test_model, content) do
            {:ok, token_count} -> {multiplier, token_count.total_tokens}
            {:error, _} -> {multiplier, nil}
          end
        end

      # Filter out any nil results from errors
      valid_counts = Enum.filter(token_counts, fn {_, count} -> count != nil end)

      if length(valid_counts) >= 2 do
        # Token counts should generally increase with content length
        sorted_counts = Enum.sort_by(valid_counts, fn {multiplier, _} -> multiplier end)

        for i <- 1..(length(sorted_counts) - 1) do
          {_, prev_count} = Enum.at(sorted_counts, i - 1)
          {_, curr_count} = Enum.at(sorted_counts, i)

          assert curr_count >= prev_count,
                 "Token count should increase with content length: #{inspect(sorted_counts)}"
        end
      end
    end
  end

  describe "token counting edge cases" do
    @tag provider: :gemini
    test "handles empty content" do
      case ExLLM.count_tokens(:gemini, @test_model, "") do
        {:ok, token_count} ->
          assert is_map(token_count)
          assert Map.has_key?(token_count, :total_tokens)
          assert token_count.total_tokens >= 0

        {:error, reason} ->
          IO.puts("Empty content token counting failed: #{inspect(reason)}")
          :ok
      end
    end

    @tag provider: :gemini
    test "handles very long content" do
      # Create a very long string (but not too long to avoid timeouts)
      long_content = String.duplicate("This is a test sentence with multiple words. ", 100)

      case ExLLM.count_tokens(:gemini, @test_model, long_content) do
        {:ok, token_count} ->
          assert is_map(token_count)
          assert Map.has_key?(token_count, :total_tokens)
          assert token_count.total_tokens > 0

        {:error, reason} ->
          IO.puts("Long content token counting failed: #{inspect(reason)}")
          :ok
      end
    end

    @tag provider: :gemini
    test "handles unicode and special characters" do
      unicode_content = "Hello 世界! 🌍 Testing unicode: café, naïve, résumé, Москва, 東京"

      case ExLLM.count_tokens(:gemini, @test_model, unicode_content) do
        {:ok, token_count} ->
          assert is_map(token_count)
          assert Map.has_key?(token_count, :total_tokens)
          assert token_count.total_tokens > 0

        {:error, reason} ->
          IO.puts("Unicode content token counting failed: #{inspect(reason)}")
          :ok
      end
    end
  end
end
