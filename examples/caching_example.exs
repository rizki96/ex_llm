# Response Caching Example with ExLLM
#
# This example demonstrates how to use response caching to:
# - Reduce API costs by avoiding duplicate requests
# - Improve response times for repeated queries
# - Configure cache behavior
#
# Run with: mix run examples/caching_example.exs

defmodule CachingExample do
  def run do
    IO.puts("\n🚀 ExLLM Response Caching Example\n")
    
    # Start the cache if not already running
    ensure_cache_started()
    
    # Example 1: Basic Caching
    IO.puts("1️⃣ Basic Caching Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    messages = [
      %{role: "user", content: "What is the capital of France?"}
    ]
    
    # First request - will hit the API
    IO.puts("Making first request (cache miss)...")
    start_time = System.monotonic_time(:millisecond)
    
    {:ok, response1} = ExLLM.chat(:mock, messages,
      mock_response: "The capital of France is Paris.",
      capture_requests: true,
      cache: true
    )
    
    time1 = System.monotonic_time(:millisecond) - start_time
    IO.puts("Response: #{response1.content}")
    IO.puts("Time: #{time1}ms")
    
    # Second request - should hit cache
    IO.puts("\nMaking second request (cache hit)...")
    start_time = System.monotonic_time(:millisecond)
    
    {:ok, response2} = ExLLM.chat(:mock, messages,
      mock_response: "This should not be returned",
      cache: true
    )
    
    time2 = System.monotonic_time(:millisecond) - start_time
    IO.puts("Response: #{response2.content}")
    IO.puts("Time: #{time2}ms")
    IO.puts("Cache speedup: #{Float.round(time1 / max(time2, 1), 1)}x faster")
    
    # Verify only one API call was made
    requests = ExLLM.Adapters.Mock.get_captured_requests()
    IO.puts("API calls made: #{length(requests)}")
    
    # Example 2: Cache TTL
    IO.puts("\n\n2️⃣ Cache TTL Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    ExLLM.Cache.clear()
    ExLLM.Adapters.Mock.clear_captured_requests()
    
    ttl_messages = [
      %{role: "user", content: "What time is it?"}
    ]
    
    # Cache with short TTL
    IO.puts("Caching response with 500ms TTL...")
    {:ok, response1} = ExLLM.chat(:mock, ttl_messages,
      mock_response: "It's 3:00 PM",
      cache: true,
      cache_ttl: 500  # 500ms TTL
    )
    IO.puts("Response: #{response1.content}")
    
    # Immediate second request - should hit cache
    {:ok, response2} = ExLLM.chat(:mock, ttl_messages,
      mock_response: "It's 3:01 PM",
      cache: true
    )
    IO.puts("Immediate retry: #{response2.content} (from cache)")
    
    # Wait for expiration
    IO.puts("\nWaiting for cache to expire...")
    Process.sleep(600)
    
    # Third request - cache expired, should hit API
    {:ok, response3} = ExLLM.chat(:mock, ttl_messages,
      mock_response: "It's 3:01 PM",
      cache: true
    )
    IO.puts("After expiration: #{response3.content} (fresh response)")
    
    # Example 3: Selective Caching
    IO.puts("\n\n3️⃣ Selective Caching Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Some requests should not be cached
    function_messages = [
      %{role: "user", content: "Call the weather API for London"}
    ]
    
    functions = [
      %{
        name: "get_weather",
        description: "Get current weather",
        parameters: %{}
      }
    ]
    
    IO.puts("Request with functions (not cached):")
    {:ok, _} = ExLLM.chat(:mock, function_messages,
      mock_response: "I'll check the weather",
      functions: functions,
      cache: true  # Cache requested but will be ignored
    )
    
    # Second identical request
    {:ok, _} = ExLLM.chat(:mock, function_messages,
      mock_response: "Weather might have changed",
      functions: functions,
      cache: true
    )
    
    IO.puts("Function calls are never cached (for safety)")
    
    # Example 4: Cache Statistics
    IO.puts("\n\n4️⃣ Cache Statistics Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Clear and generate some cache activity
    ExLLM.Cache.clear()
    
    # Make various requests
    queries = [
      "What is 2+2?",
      "What is the meaning of life?",
      "What is 2+2?",  # Duplicate
      "Tell me a joke",
      "What is the meaning of life?",  # Duplicate
      "What is 2+2?"  # Duplicate
    ]
    
    Enum.each(queries, fn query ->
      ExLLM.chat(:mock, [%{role: "user", content: query}],
        mock_response: "Response for: #{query}",
        cache: true
      )
    end)
    
    # Get statistics
    stats = ExLLM.Cache.stats()
    IO.puts("Cache Statistics:")
    IO.puts("  Hits: #{stats.hits}")
    IO.puts("  Misses: #{stats.misses}")
    IO.puts("  Hit Rate: #{Float.round(stats.hits / (stats.hits + stats.misses) * 100, 1)}%")
    
    # Example 5: Different Models/Options
    IO.puts("\n\n5️⃣ Cache Key Sensitivity Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    base_messages = [%{role: "user", content: "Explain quantum computing"}]
    
    # Same question, different temperature
    IO.puts("Same question with different parameters:")
    
    {:ok, r1} = ExLLM.chat(:mock, base_messages,
      mock_response: "Response at temp 0.7",
      temperature: 0.7,
      cache: true
    )
    
    {:ok, r2} = ExLLM.chat(:mock, base_messages,
      mock_response: "Response at temp 0.9",
      temperature: 0.9,
      cache: true
    )
    
    IO.puts("Temperature 0.7: #{r1.content}")
    IO.puts("Temperature 0.9: #{r2.content}")
    IO.puts("Different parameters = different cache keys")
    
    # Example 6: Cost Savings Calculation
    IO.puts("\n\n6️⃣ Cost Savings Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Simulate a scenario with repeated questions
    common_questions = [
      "How do I reset my password?",
      "What are your business hours?",
      "How do I contact support?",
      "What is your refund policy?",
      "How do I reset my password?",  # Repeat
      "What are your business hours?",  # Repeat
      "How do I upgrade my plan?",
      "How do I reset my password?",  # Repeat
      "What is your refund policy?"   # Repeat
    ]
    
    # Track API calls
    ExLLM.Adapters.Mock.clear_captured_requests()
    api_calls = 0
    cache_hits = 0
    
    Enum.each(common_questions, fn question ->
      messages = [%{role: "user", content: question}]
      cache_key = ExLLM.Cache.generate_cache_key(:anthropic, messages, [])
      
      case ExLLM.Cache.get(cache_key) do
        {:ok, _} ->
          cache_hits = cache_hits + 1
        :miss ->
          api_calls = api_calls + 1
          # Simulate API response
          ExLLM.Cache.put(cache_key, %{content: "Answer to: #{question}"})
      end
    end)
    
    IO.puts("Total requests: #{length(common_questions)}")
    IO.puts("API calls made: #{api_calls}")
    IO.puts("Cache hits: #{cache_hits}")
    
    # Calculate savings (example pricing)
    cost_per_call = 0.002  # $0.002 per API call
    saved = cache_hits * cost_per_call
    
    IO.puts("\nEstimated savings:")
    IO.puts("  Without cache: $#{Float.round(length(common_questions) * cost_per_call, 4)}")
    IO.puts("  With cache: $#{Float.round(api_calls * cost_per_call, 4)}")
    IO.puts("  Saved: $#{Float.round(saved, 4)} (#{Float.round(cache_hits / length(common_questions) * 100, 1)}%)")
    
    IO.puts("\n\n✅ Caching examples completed!")
    IO.puts("\nKey takeaways:")
    IO.puts("- Caching can significantly reduce API costs")
    IO.puts("- Response times improve dramatically for cached requests")
    IO.puts("- TTL ensures data freshness")
    IO.puts("- Some requests (functions, streaming) are never cached")
    IO.puts("- Different parameters create different cache keys")
  end
  
  defp ensure_cache_started do
    case GenServer.whereis(ExLLM.Cache) do
      nil ->
        {:ok, _} = ExLLM.Cache.start_link()
      _ ->
        :ok
    end
  end
end

# Run the examples
CachingExample.run()