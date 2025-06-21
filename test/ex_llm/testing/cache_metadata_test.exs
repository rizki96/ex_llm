defmodule ExLLM.Infrastructure.CacheMetadataTest do
  use ExUnit.Case, async: false
  alias ExLLM.Providers.Shared.HTTPClient
  alias ExLLM.Testing.LiveApiCacheStorage

  setup do
    # Enable test cache
    Application.put_env(:ex_llm, :test_cache_enabled, true)
    Application.put_env(:ex_llm, :debug_test_cache, false)

    # Clear cache before test
    LiveApiCacheStorage.clear(:all)

    on_exit(fn ->
      LiveApiCacheStorage.clear(:all)
    end)

    :ok
  end

  describe "HTTPClient cache metadata" do
    test "adds from_cache metadata to cached responses" do
      # Mock response data
      response_data = %{
        "id" => "test-123",
        "object" => "chat.completion",
        "created" => 1_234_567_890,
        "model" => "test-model",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Test response"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 5,
          "total_tokens" => 15
        }
      }

      # Store in cache
      cache_key = "test/cache_metadata/test-key"

      metadata = %{
        status: "ok",
        cached_at: DateTime.utc_now(),
        cache_version: "1.0",
        api_version: "2023-01-01",
        response_time_ms: 100
      }

      LiveApiCacheStorage.store(cache_key, response_data, metadata)

      # Mock the interceptor to return our cached response
      # We'll directly test the add_cache_metadata function
      response_with_metadata = HTTPClient.add_cache_metadata(response_data)

      # Check that metadata was added
      assert response_with_metadata["metadata"][:from_cache] == true
    end

    test "preserves existing metadata when adding from_cache" do
      # Response with existing metadata
      response_data = %{
        "id" => "test-456",
        "metadata" => %{
          existing_key: "existing_value",
          timestamp: 123_456
        },
        "choices" => [
          %{
            "message" => %{
              "content" => "Test"
            }
          }
        ]
      }

      response_with_metadata = HTTPClient.add_cache_metadata(response_data)

      # Check that existing metadata is preserved
      assert response_with_metadata["metadata"][:existing_key] == "existing_value"
      assert response_with_metadata["metadata"][:timestamp] == 123_456
      # And from_cache is added
      assert response_with_metadata["metadata"][:from_cache] == true
    end
  end
end
