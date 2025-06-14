#!/usr/bin/env elixir
#
# Demo script to test the automatic response caching system
#

# Start the application
Application.put_env(:ex_llm, :test_cache, enabled: true)

Mix.install([
  {:ex_llm, path: "."}
])

# Enable test caching
Application.put_env(:ex_llm, :test_cache, [
  enabled: true,
  cache_dir: "test/cache",
  ttl: :timer.hours(24),
  save_on_miss: true,
  replay_by_default: true
])

# Create a mock test to simulate integration test caching
defmodule CacheDemo do
  def run do
    IO.puts("🧪 Testing ExLLM Automatic Response Caching")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Check cache stats before
    IO.puts("\n📊 Cache Stats Before:")
    show_cache_stats()
    
    # Create some mock cached responses by simulating what the caching system would do
    create_sample_cache_data()
    
    # Check cache stats after
    IO.puts("\n📊 Cache Stats After:")
    show_cache_stats()
    
    # List cache contents
    IO.puts("\n📂 Cache Contents:")
    list_cache_contents()
  end
  
  defp show_cache_stats do
    stats = ExLLM.TestCacheStats.get_global_stats()
    IO.puts("  Total Requests: #{stats.total_requests}")
    IO.puts("  Cache Hits: #{stats.cache_hits}")
    IO.puts("  Cache Misses: #{stats.cache_misses}")
    IO.puts("  Hit Rate: #{ExLLM.TestCacheStats.format_percentage(stats.hit_rate)}")
    IO.puts("  Storage Used: #{format_bytes(stats.total_cache_size)}")
  end
  
  defp list_cache_contents do
    cache_keys = ExLLM.Cache.Storage.TestCache.list_cache_keys()
    IO.puts("  Found #{length(cache_keys)} cache keys:")
    Enum.each(cache_keys, fn key ->
      IO.puts("    - #{key}")
    end)
  end
  
  defp create_sample_cache_data do
    IO.puts("\n🔧 Creating sample cache data...")
    
    # Create cache directory structure
    cache_dir = "test/cache/openai/chat_completion/sample_request"
    File.mkdir_p!(cache_dir)
    
    # Create a sample cached response
    sample_response = %{
      choices: [
        %{
          message: %{
            role: "assistant",
            content: "Hello! This is a cached response from the ExLLM test caching system."
          },
          finish_reason: "stop"
        }
      ],
      usage: %{
        prompt_tokens: 10,
        completion_tokens: 15,
        total_tokens: 25
      },
      model: "gpt-3.5-turbo"
    }
    
    # Save response with timestamp
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
    filename = Path.join(cache_dir, "#{timestamp}.json")
    File.write!(filename, Jason.encode!(sample_response, pretty: true))
    
    # Create index file
    index_data = %{
      cache_key: "openai/chat_completion/sample_request",
      entries: [
        %{
          timestamp: DateTime.utc_now(),
          filename: "#{timestamp}.json",
          status: :success,
          size: byte_size(File.read!(filename)),
          content_hash: :crypto.hash(:sha256, File.read!(filename)) |> Base.encode16(case: :lower),
          response_time_ms: 245,
          api_version: "v1",
          cost: %{
            input: 0.001,
            output: 0.002,
            total: 0.003
          }
        }
      ],
      total_requests: 1,
      cache_hits: 0,
      last_accessed: DateTime.utc_now(),
      access_count: 1,
      last_cleanup: nil,
      cleanup_before: nil
    }
    
    index_file = Path.join(cache_dir, "index.json")
    File.write!(index_file, Jason.encode!(index_data, pretty: true))
    
    IO.puts("  ✅ Created sample cache entry: #{cache_dir}")
    IO.puts("  📄 Response file: #{timestamp}.json")
    IO.puts("  📋 Index file: index.json")
  end
  
  defp format_bytes(bytes) when is_number(bytes) do
    cond do
      bytes < 1024 -> "#{bytes}B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)}KB"
      true -> "#{Float.round(bytes / (1024 * 1024), 1)}MB"
    end
  end
  defp format_bytes(_), do: "0B"
end

# Run the demo
CacheDemo.run()