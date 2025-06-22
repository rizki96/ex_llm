defmodule CacheVerificationTest do
  use ExUnit.Case
  import ExLLM.Testing.TestCacheHelpers

  @moduletag :integration
  @moduletag :cache_test

  setup context do
    # Enable cache for this test AND enable caching for integration tests
    Application.put_env(:ex_llm, :test_cache, %{
      enabled: true,
      cache_integration_tests: true,
      cache_live_api_tests: true,
      save_on_miss: true,
      ttl: :infinity
    })
    
    setup_test_cache(context)

    on_exit(fn ->
      ExLLM.Testing.TestCacheDetector.clear_test_context()
      Application.delete_env(:ex_llm, :test_cache)
    end)
  end

  test "verify caching works for OpenAI calls" do
    messages = [%{role: "user", content: "Say 'test' and nothing else"}]

    # Check test context before first call
    IO.puts("\nTest context before first call:")

    case ExLLM.Testing.TestCacheDetector.get_current_test_context() do
      {:ok, context} -> IO.puts("  Module: #{context.module}, Tags: #{inspect(context.tags)}")
      :error -> IO.puts("  No test context found!")
    end

    IO.puts("  Should cache: #{ExLLM.Testing.TestCacheDetector.should_cache_responses?()}")

    IO.puts("\nCalling API first time...")
    # First call - should hit API
    start1 = System.monotonic_time(:millisecond)
    {:ok, response1} = ExLLM.chat(:openai, messages, max_tokens: 10)
    duration1 = System.monotonic_time(:millisecond) - start1

    IO.puts("\nFirst call:")
    IO.puts("  Response: #{response1.content}")
    IO.puts("  Duration: #{duration1}ms")
    IO.puts("  From cache: #{response1.metadata[:from_cache] || false}")

    # Wait a bit to ensure cache is written
    :timer.sleep(100)

    # Check test context before second call
    IO.puts("\nTest context before second call:")

    case ExLLM.Testing.TestCacheDetector.get_current_test_context() do
      {:ok, context} -> IO.puts("  Module: #{context.module}, Tags: #{inspect(context.tags)}")
      :error -> IO.puts("  No test context found!")
    end

    IO.puts("  Should cache: #{ExLLM.Testing.TestCacheDetector.should_cache_responses?()}")

    IO.puts("\nCalling API second time (should use cache)...")
    # Second call - should be cached
    start2 = System.monotonic_time(:millisecond)
    {:ok, response2} = ExLLM.chat(:openai, messages, max_tokens: 10)
    duration2 = System.monotonic_time(:millisecond) - start2

    IO.puts("\nSecond call:")
    IO.puts("  Response: #{response2.content}")
    IO.puts("  Duration: #{duration2}ms")
    IO.puts("  From cache: #{response2.metadata[:from_cache] || false}")

    # Verify responses are the same
    assert response1.content == response2.content

    # Verify second call was from cache
    assert response2.metadata[:from_cache] == true || duration2 < duration1 / 2

    # Check cache files
    cache_stats = get_cache_stats("#{__MODULE__}")
    IO.puts("\nCache stats:")
    IO.puts("  Hits: #{cache_stats.cache_hits}")
    IO.puts("  Misses: #{cache_stats.cache_misses}")
    IO.puts("  Hit rate: #{Float.round(cache_stats.hit_rate * 100, 1)}%")
  end

  test "verify caching works for Gemini OAuth2 calls" do
    # Skip if no OAuth2 tokens
    unless File.exists?(".gemini_tokens") do
      IO.puts("Skipping OAuth2 test - no tokens file")
      :ok
    else
      messages = [%{role: "user", content: "Say 'oauth test' and nothing else"}]

      # First call - should hit API
      start1 = System.monotonic_time(:millisecond)
      result1 = ExLLM.chat(:gemini, messages, model: "gemini-1.5-flash-latest", max_tokens: 10)

      case result1 do
        {:ok, response1} ->
          duration1 = System.monotonic_time(:millisecond) - start1

          IO.puts("\nFirst OAuth2 call:")
          IO.puts("  Response: #{response1.content}")
          IO.puts("  Duration: #{duration1}ms")
          IO.puts("  From cache: #{response1.metadata[:from_cache] || false}")

          # Second call - should be cached
          start2 = System.monotonic_time(:millisecond)

          {:ok, response2} =
            ExLLM.chat(:gemini, messages, model: "gemini-1.5-flash-latest", max_tokens: 10)

          duration2 = System.monotonic_time(:millisecond) - start2

          IO.puts("\nSecond OAuth2 call:")
          IO.puts("  Response: #{response2.content}")
          IO.puts("  Duration: #{duration2}ms")
          IO.puts("  From cache: #{response2.metadata[:from_cache] || false}")

          # Verify caching worked
          assert response1.content == response2.content
          assert response2.metadata[:from_cache] == true || duration2 < duration1 / 2

        {:error, error} ->
          IO.puts("OAuth2 test error: #{inspect(error)}")
          # Don't fail the test if OAuth2 isn't configured
          :ok
      end
    end
  end
end
