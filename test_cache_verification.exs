#!/usr/bin/env elixir

# Test script to verify caching is working

IO.puts("\n=== Testing ExLLM Cache System ===\n")

# Environment variables are already loaded by run_with_env.sh

# Test with OpenAI
defmodule CacheTest do
  def run do
    # Enable test mode
    Application.put_env(:ex_llm, :test_cache, %{
      enabled: true,
      auto_detect: true,
      cache_integration_tests: true
    })
    
    # Set test context to enable caching
    ExLLM.TestCacheDetector.set_test_context(%{
      module: __MODULE__,
      test_name: "cache_verification_test",
      tags: [:integration],
      pid: self()
    })
    
    IO.puts("1. Making first API call (should be real)...")
    
    messages = [%{role: "user", content: "Say 'test' and nothing else"}]
    
    start_time = System.monotonic_time(:millisecond)
    result1 = ExLLM.chat(:openai, messages, max_tokens: 10)
    end_time = System.monotonic_time(:millisecond)
    first_duration = end_time - start_time
    
    case result1 do
      {:ok, response1} ->
        IO.puts("   ✓ Response: #{response1.content}")
        IO.puts("   ✓ Time: #{first_duration}ms")
        IO.puts("   ✓ From cache: #{response1.metadata[:from_cache] || false}")
        
        IO.puts("\n2. Making second API call (should be cached)...")
        
        start_time2 = System.monotonic_time(:millisecond)
        result2 = ExLLM.chat(:openai, messages, max_tokens: 10)
        end_time2 = System.monotonic_time(:millisecond)
        second_duration = end_time2 - start_time2
        
        case result2 do
          {:ok, response2} ->
            IO.puts("   ✓ Response: #{response2.content}")
            IO.puts("   ✓ Time: #{second_duration}ms")
            IO.puts("   ✓ From cache: #{response2.metadata[:from_cache] || false}")
            
            IO.puts("\n3. Checking cache directory...")
            cache_dir = "test/cache"
            
            case File.ls(cache_dir) do
              {:ok, files} ->
                IO.puts("   ✓ Cache files: #{length(files)}")
                Enum.each(files, fn file ->
                  IO.puts("     - #{file}")
                end)
              {:error, _} ->
                IO.puts("   ✗ Cache directory not found")
            end
            
            IO.puts("\n=== Summary ===")
            IO.puts("First call: #{first_duration}ms")
            IO.puts("Second call: #{second_duration}ms")
            
            if second_duration < first_duration / 2 do
              IO.puts("✓ Caching appears to be working! Second call was #{Float.round(first_duration / second_duration, 1)}x faster")
            else
              IO.puts("⚠ Caching may not be working properly")
            end
            
          {:error, error} ->
            IO.puts("   ✗ Error on second call: #{inspect(error)}")
        end
        
      {:error, error} ->
        IO.puts("   ✗ Error: #{inspect(error)}")
    end
    
    # Clear test context
    ExLLM.TestCacheDetector.clear_test_context()
  end
end

CacheTest.run()