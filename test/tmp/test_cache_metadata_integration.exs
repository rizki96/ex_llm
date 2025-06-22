defmodule CacheMetadataIntegrationTest do
  use ExUnit.Case, async: false
  alias ExLLM.Testing.LiveApiCacheStorage
  
  setup do
    # Enable test cache
    System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")
    Application.put_env(:ex_llm, :test_cache_enabled, true)
    Application.put_env(:ex_llm, :debug_test_cache, true)
    
    # Clear any existing cache
    LiveApiCacheStorage.clear(:all)
    
    # Set fake API key to trigger the pipeline but avoid real calls
    System.put_env("OPENAI_API_KEY", "sk-test12345678901234567890123456789012345678901234567890")
    
    on_exit(fn ->
      # Clean up
      LiveApiCacheStorage.clear(:all)
    end)
    
    :ok
  end
  
  test "manually create cache entry and test metadata" do
    # First, let's manually create a cache entry
    cache_key = "openai/chat_completions/4927533d4ce0"
    
    # Mock response data
    response_data = %{
      "id" => "chatcmpl-test123",
      "object" => "chat.completion",
      "created" => 1_640_995_200,
      "model" => "gpt-4",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => "Hello! How can I help you today?"
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 10,
        "completion_tokens" => 8,
        "total_tokens" => 18
      }
    }
    
    # Store in cache
    metadata = %{
      status: "ok",
      cached_at: DateTime.utc_now(),
      cache_version: "1.0"
    }
    
    LiveApiCacheStorage.store(cache_key, response_data, metadata)
    
    # Now make the same request that should hit the cache
    case ExLLM.chat(:openai, [%{role: "user", content: "Hello test"}]) do
      {:ok, response} ->
        IO.inspect(response, label: "Response from cache")
        IO.inspect(response.metadata, label: "Response metadata")
        
        # Check if from_cache metadata is present
        if Map.has_key?(response.metadata, :from_cache) do
          assert response.metadata[:from_cache] == true
          IO.puts("✅ SUCCESS: from_cache metadata found!")
        else
          IO.puts("❌ FAIL: from_cache metadata not found")
          IO.inspect(response.metadata, label: "Available metadata keys")
          flunk("from_cache metadata not present in response")
        end
        
      {:error, error} ->
        IO.inspect(error, label: "Error - cache should have been hit")
        flunk("Expected cache hit but got error: #{inspect(error)}")
    end
  end
end