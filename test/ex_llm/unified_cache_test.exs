defmodule ExLLM.UnifiedCacheTest do
  use ExUnit.Case
  alias ExLLM.Cache
  alias ExLLM.ResponseCache

  setup do
    # Start the cache
    {:ok, _pid} = Cache.start_link([])

    # Clear any existing cache
    Cache.clear()
    ResponseCache.clear_all_cache()

    :ok
  end

  describe "unified cache with disk persistence disabled" do
    test "cache works normally without disk persistence" do
      # Test normal cache operation
      key = "test_key"
      value = %{content: "Hello world", model: "test-model"}

      # Store in cache
      Cache.put(key, value, provider: :test_provider)

      # Retrieve from cache
      assert {:ok, ^value} = Cache.get(key)

      # Should not have persisted to disk
      assert [] = ResponseCache.list_cached_providers()
    end
  end

  describe "unified cache with disk persistence enabled" do
    setup do
      # Enable disk persistence using the configuration function
      Cache.configure_disk_persistence(true, "/tmp/ex_llm_cache_test")

      on_exit(fn ->
        # Disable disk persistence and clean up
        Cache.configure_disk_persistence(false)
        ResponseCache.clear_all_cache()
      end)

      :ok
    end

    test "cache persists to disk when enabled" do
      # Store in cache with provider metadata
      key = "unified_test_key"

      value = %{
        content: "Hello from unified cache",
        model: "gpt-4",
        usage: %{input_tokens: 10, output_tokens: 20}
      }

      Cache.put(key, value,
        provider: :openai,
        model: "gpt-4",
        temperature: 0.7
      )

      # Should be in ETS cache
      assert {:ok, ^value} = Cache.get(key)

      # Give async task time to complete
      Process.sleep(200)

      # Should also be persisted to disk (check file directly)
      cache_file = Path.join(["/tmp/ex_llm_cache_test", "openai", "chat.json"])
      assert File.exists?(cache_file), "Cache file should exist"

      # Verify content
      content = File.read!(cache_file) |> Jason.decode!()
      assert length(content) >= 1

      assert Enum.any?(content, fn entry ->
               entry["request_hash"] == key and entry["provider"] == "openai"
             end)
    end

    test "mock adapter can use persisted cache" do
      # Cache a response
      key = "mock_test_key"

      value = %{
        content: "Cached response for mock",
        model: "claude-3-sonnet",
        usage: %{input_tokens: 15, output_tokens: 25}
      }

      Cache.put(key, value,
        provider: :anthropic,
        model: "claude-3-sonnet",
        temperature: 0.5
      )

      # Wait for disk persistence
      Process.sleep(200)

      # Verify response was cached to disk
      cache_file = Path.join(["/tmp/ex_llm_cache_test", "anthropic", "chat.json"])
      assert File.exists?(cache_file), "Anthropic cache file should exist"

      # Verify content includes our cached response
      content = File.read!(cache_file) |> Jason.decode!()

      assert Enum.any?(content, fn entry ->
               entry["request_hash"] == key and entry["provider"] == "anthropic"
             end)
    end

    test "cache handles multiple providers separately" do
      # Cache responses for different providers
      openai_value = %{content: "OpenAI response", model: "gpt-4"}
      anthropic_value = %{content: "Anthropic response", model: "claude-3-sonnet"}

      Cache.put("openai_key", openai_value, provider: :openai, model: "gpt-4")
      Cache.put("anthropic_key", anthropic_value, provider: :anthropic, model: "claude-3-sonnet")

      # Wait for persistence
      Process.sleep(200)

      # Should have separate provider cache files
      openai_file = Path.join(["/tmp/ex_llm_cache_test", "openai", "chat.json"])
      anthropic_file = Path.join(["/tmp/ex_llm_cache_test", "anthropic", "chat.json"])

      assert File.exists?(openai_file), "OpenAI cache file should exist"
      assert File.exists?(anthropic_file), "Anthropic cache file should exist"

      # Verify content
      openai_content = File.read!(openai_file) |> Jason.decode!()
      anthropic_content = File.read!(anthropic_file) |> Jason.decode!()

      assert Enum.any?(openai_content, fn entry -> entry["provider"] == "openai" end)
      assert Enum.any?(anthropic_content, fn entry -> entry["provider"] == "anthropic" end)
    end

    test "cache handles different endpoints" do
      # Test different endpoint types
      chat_value = %{content: "Chat response", model: "gpt-4"}
      streaming_value = %{content: "Streaming response", model: "gpt-4"}

      Cache.put("chat_key", chat_value,
        provider: :openai,
        model: "gpt-4"
      )

      Cache.put("streaming_key", streaming_value,
        provider: :openai,
        model: "gpt-4",
        stream: true
      )

      # Wait for persistence
      Process.sleep(200)

      # Should have different endpoint files
      chat_file = Path.join(["/tmp/ex_llm_cache_test", "openai", "chat.json"])
      streaming_file = Path.join(["/tmp/ex_llm_cache_test", "openai", "streaming.json"])

      assert File.exists?(chat_file), "Chat cache file should exist"
      assert File.exists?(streaming_file), "Streaming cache file should exist"

      # Verify endpoints are correctly separated
      chat_content = File.read!(chat_file) |> Jason.decode!()
      streaming_content = File.read!(streaming_file) |> Jason.decode!()

      assert Enum.any?(chat_content, fn entry -> entry["endpoint"] == "chat" end)
      assert Enum.any?(streaming_content, fn entry -> entry["endpoint"] == "streaming" end)
    end
  end

  describe "cache configuration" do
    test "can configure custom disk path" do
      custom_dir = "/tmp/test_ex_llm_cache_custom"

      try do
        # Configure cache with custom directory
        Cache.configure_disk_persistence(true, custom_dir)

        # Store something
        Cache.put("dir_test", %{content: "test"}, provider: :test)
        Process.sleep(100)

        # Should use custom directory
        assert File.exists?(Path.join([custom_dir, "test", "chat.json"]))
      after
        # Cleanup
        Cache.configure_disk_persistence(false)
        File.rm_rf(custom_dir)
      end
    end
  end
end
