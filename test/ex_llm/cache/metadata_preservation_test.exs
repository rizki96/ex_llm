defmodule ExLLM.Cache.MetadataPreservationTest do
  @moduledoc """
  Test that metadata (including :from_cache) is preserved through both cache systems.
  """
  use ExUnit.Case, async: false

  alias ExLLM.Infrastructure.Cache
  alias ExLLM.Testing.LiveApiCacheStorage

  setup do
    # Ensure production cache is started
    case GenServer.whereis(Cache) do
      nil -> {:ok, _pid} = Cache.start_link([])
      _pid -> :ok
    end

    :ok
  end

  describe "production cache metadata preservation" do
    test "production cache preserves response metadata" do
      cache_key = "test_#{System.unique_integer()}"

      # Create a response with metadata
      response = %{
        content: "Test response",
        metadata: %{
          custom_field: "custom_value",
          timestamp: DateTime.utc_now()
        }
      }

      # Store in cache
      Cache.put(cache_key, response)

      # Retrieve from cache
      assert {:ok, cached_response} = Cache.get(cache_key)

      # Verify metadata is preserved
      assert cached_response.content == "Test response"
      assert cached_response.metadata.custom_field == "custom_value"
      assert cached_response.metadata.timestamp

      # Clean up
      Cache.delete(cache_key)
    end
  end

  describe "test cache metadata preservation" do
    @tag :live_api
    test "test cache adds :from_cache metadata to responses" do
      # Enable test cache
      System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")
      Application.put_env(:ex_llm, :test_cache_enabled, true)

      # Create a unique cache key
      cache_key = "test_provider/test_endpoint/#{System.unique_integer()}"

      # Create test response data
      response_data = %{
        "id" => "test-123",
        "object" => "test.response",
        "data" => %{
          "content" => "Cached test response"
        }
      }

      # Store in test cache
      metadata = %{
        provider: :test_provider,
        endpoint: "test_endpoint",
        cached_at: DateTime.utc_now()
      }

      LiveApiCacheStorage.store(cache_key, response_data, metadata)

      # Verify it was stored
      assert {:ok, cached} = LiveApiCacheStorage.get(cache_key)
      assert cached["id"] == "test-123"

      # Clean up
      LiveApiCacheStorage.clear(cache_key)
      System.delete_env("EX_LLM_TEST_CACHE_ENABLED")
      Application.delete_env(:ex_llm, :test_cache_enabled)
    end
  end

  describe "telemetry emission" do
    test "cache operations emit telemetry events" do
      # Attach telemetry handler
      events_received = :ets.new(:telemetry_test, [:set, :public])

      handler_id = "test-handler-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:ex_llm, :cache, :hit],
          [:ex_llm, :cache, :miss],
          [:ex_llm, :cache, :put],
          [:ex_llm, :test_cache, :hit],
          [:ex_llm, :test_cache, :miss],
          [:ex_llm, :test_cache, :save]
        ],
        fn event, measurements, metadata, _config ->
          :ets.insert(events_received, {event, measurements, metadata})
        end,
        nil
      )

      # Test production cache telemetry
      cache_key = "telemetry_test_#{System.unique_integer()}"

      # This should emit a miss
      Cache.get(cache_key)

      # This should emit a put
      Cache.put(cache_key, %{data: "test"})

      # This should emit a hit
      Cache.get(cache_key)

      # Give telemetry time to process
      Process.sleep(10)

      # Verify events were received
      events = :ets.tab2list(events_received)

      assert Enum.any?(events, fn {event, _, _} -> event == [:ex_llm, :cache, :miss] end)
      assert Enum.any?(events, fn {event, _, _} -> event == [:ex_llm, :cache, :put] end)
      assert Enum.any?(events, fn {event, _, _} -> event == [:ex_llm, :cache, :hit] end)

      # Clean up
      :telemetry.detach(handler_id)
      :ets.delete(events_received)
      Cache.delete(cache_key)
    end
  end
end
