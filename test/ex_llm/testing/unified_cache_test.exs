defmodule ExLLM.UnifiedCacheTest do
  use ExUnit.Case
  alias ExLLM.Infrastructure.Cache
  alias ExLLM.Testing.ResponseCache

  setup do
    # Ensure cache GenServer is started
    case GenServer.whereis(ExLLM.Infrastructure.Cache) do
      nil ->
        {:ok, _} = ExLLM.Infrastructure.Cache.start_link()
      _pid ->
        :ok
    end

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

      # Wait for async put operation to complete
      Process.sleep(10)

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

      # Wait for async put operation to complete
      Process.sleep(10)

      # Should be in ETS cache
      assert {:ok, ^value} = Cache.get(key)

      # Give async task time to complete and wait for file to exist
      cache_file = Path.join(["/tmp/ex_llm_cache_test", "openai", "chat.json"])
      wait_for_file_creation(cache_file, 1000)

      # Should also be persisted to disk (check file directly)
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

      # Wait for async put operation to complete
      Process.sleep(10)

      # Wait for disk persistence
      cache_file = Path.join(["/tmp/ex_llm_cache_test", "anthropic", "chat.json"])
      wait_for_file_creation(cache_file, 1000)

      # Verify response was cached to disk
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

      # Wait for async put operations to complete
      Process.sleep(10)

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

      # Wait for async put operations to complete
      Process.sleep(10)

      # Wait for persistence of both files
      chat_file = Path.join(["/tmp/ex_llm_cache_test", "openai", "chat.json"])
      streaming_file = Path.join(["/tmp/ex_llm_cache_test", "openai", "streaming.json"])
      wait_for_file_creation(chat_file, 1000)
      wait_for_file_creation(streaming_file, 1000)

      # Should have different endpoint files

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

        # Wait for async put operation to complete
        Process.sleep(10)

        # Wait for custom directory file to be created
        custom_cache_file = Path.join([custom_dir, "test", "chat.json"])
        wait_for_file_creation(custom_cache_file, 1000)

        # Should use custom directory
        assert File.exists?(custom_cache_file)
      after
        # Cleanup
        Cache.configure_disk_persistence(false)
        File.rm_rf(custom_dir)
      end
    end
  end

  # Helper function to wait for file creation with timeout
  defp wait_for_file_creation(file_path, timeout_ms) do
    start_time = System.monotonic_time(:millisecond)
    wait_for_file_creation_loop(file_path, start_time, timeout_ms)
  end

  defp wait_for_file_creation_loop(file_path, start_time, timeout_ms) do
    if File.exists?(file_path) do
      :ok
    else
      current_time = System.monotonic_time(:millisecond)

      if current_time - start_time >= timeout_ms do
        raise "File #{file_path} was not created within #{timeout_ms}ms"
      else
        Process.sleep(10)
        wait_for_file_creation_loop(file_path, start_time, timeout_ms)
      end
    end
  end
end
