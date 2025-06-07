defmodule ExLLM.CacheTest do
  use ExUnit.Case, async: false

  alias ExLLM.Cache
  alias ExLLM.Types.LLMResponse
  import ExLLM.TestHelpers

  setup :setup_cache_test

  describe "basic operations" do
    test "get returns miss for non-existent key" do
      assert Cache.get("non-existent") == :miss
    end

    test "put and get work correctly" do
      key = "test-key"
      value = %{data: "test"}

      assert Cache.put(key, value) == :ok
      assert {:ok, ^value} = Cache.get(key)
    end

    test "delete removes cached entry" do
      key = "test-key"
      value = %{data: "test"}

      Cache.put(key, value)
      assert {:ok, ^value} = Cache.get(key)

      Cache.delete(key)
      assert Cache.get(key) == :miss
    end

    test "clear removes all entries" do
      Cache.put("key1", "value1")
      Cache.put("key2", "value2")

      Cache.clear()

      assert Cache.get("key1") == :miss
      assert Cache.get("key2") == :miss
    end

    test "TTL expiration works" do
      key = "ttl-test"
      value = %{data: "test"}

      # Put with 100ms TTL
      Cache.put(key, value, ttl: 100)
      assert {:ok, ^value} = Cache.get(key)

      # Wait for expiration
      Process.sleep(150)
      assert Cache.get(key) == :miss
    end
  end

  describe "cache key generation" do
    test "generates consistent keys for same input" do
      provider = :anthropic
      messages = [%{role: "user", content: "Hello"}]
      options = [model: "claude-3-opus", temperature: 0.7]

      key1 = Cache.generate_cache_key(provider, messages, options)
      key2 = Cache.generate_cache_key(provider, messages, options)

      assert key1 == key2
    end

    test "generates different keys for different messages" do
      provider = :anthropic
      messages1 = [%{role: "user", content: "Hello"}]
      messages2 = [%{role: "user", content: "Hi"}]
      options = []

      key1 = Cache.generate_cache_key(provider, messages1, options)
      key2 = Cache.generate_cache_key(provider, messages2, options)

      assert key1 != key2
    end

    test "generates different keys for different options" do
      provider = :anthropic
      messages = [%{role: "user", content: "Hello"}]
      options1 = [temperature: 0.7]
      options2 = [temperature: 0.8]

      key1 = Cache.generate_cache_key(provider, messages, options1)
      key2 = Cache.generate_cache_key(provider, messages, options2)

      assert key1 != key2
    end

    test "ignores non-relevant options" do
      provider = :anthropic
      messages = [%{role: "user", content: "Hello"}]
      options1 = [temperature: 0.7, cache: true]
      options2 = [temperature: 0.7, stream: false]

      key1 = Cache.generate_cache_key(provider, messages, options1)
      key2 = Cache.generate_cache_key(provider, messages, options2)

      assert key1 == key2
    end
  end

  describe "should_cache?" do
    test "returns true when cache is explicitly enabled" do
      assert Cache.should_cache?(cache: true)
    end

    test "returns false when cache is explicitly disabled" do
      assert not Cache.should_cache?(cache: false)
    end

    test "returns false for streaming requests" do
      assert not Cache.should_cache?(cache: true, stream: true)
    end

    test "returns false for function calling" do
      assert not Cache.should_cache?(cache: true, functions: [])
      assert not Cache.should_cache?(cache: true, tools: [])
    end

    test "returns false for structured outputs" do
      assert not Cache.should_cache?(cache: true, response_model: SomeSchema)
    end
  end

  describe "with_cache" do
    test "returns cached response on hit" do
      key = "cache-hit-test"
      cached_response = %LLMResponse{content: "cached"}

      # Pre-populate cache
      Cache.put(key, cached_response)

      # Function should not be called
      result =
        Cache.with_cache(key, [cache: true], fn ->
          flunk("Function should not be called on cache hit")
        end)

      assert result == {:ok, cached_response}
    end

    test "executes function and caches on miss" do
      key = "cache-miss-test"
      response = {:ok, %LLMResponse{content: "fresh"}}

      result =
        Cache.with_cache(key, [cache: true], fn ->
          response
        end)

      assert result == response

      # Verify it was cached - Cache stores just the response, not the tuple
      assert {:ok, %LLMResponse{content: "fresh"}} = Cache.get(key)
    end

    test "bypasses cache when disabled" do
      key = "cache-disabled-test"
      cached_response = {:ok, %LLMResponse{content: "cached"}}
      fresh_response = {:ok, %LLMResponse{content: "fresh"}}

      # Pre-populate cache
      Cache.put(key, cached_response)

      # Should execute function despite cache hit
      result =
        Cache.with_cache(key, [cache: false], fn ->
          fresh_response
        end)

      assert result == fresh_response
    end

    test "doesn't cache error responses" do
      key = "error-test"
      error = {:error, :api_error}

      result =
        Cache.with_cache(key, [cache: true], fn ->
          error
        end)

      assert result == error

      # Verify it was not cached
      assert Cache.get(key) == :miss
    end
  end

  describe "statistics" do
    test "tracks hits and misses" do
      # Clear stats
      Cache.clear()

      # Generate some activity
      Cache.put("key1", "value1")
      # hit
      Cache.get("key1")
      # miss
      Cache.get("key2")
      # hit
      Cache.get("key1")
      # miss
      Cache.get("key3")

      stats = Cache.stats()
      assert stats.hits == 2
      assert stats.misses == 2
    end
  end

  describe "complex cache key scenarios" do
    test "handles messages with image content" do
      provider = :openai

      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "https://example.com/img.jpg"}}
          ]
        }
      ]

      options = [model: "gpt-4-vision-preview"]

      key = Cache.generate_cache_key(provider, messages, options)
      assert is_binary(key)

      # Same content should generate same key
      key2 = Cache.generate_cache_key(provider, messages, options)
      assert key == key2
    end

    test "handles messages with base64 images" do
      provider = :anthropic
      base64_data = Base.encode64("fake image data")

      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Analyze this"},
            %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,#{base64_data}"}}
          ]
        }
      ]

      key = Cache.generate_cache_key(provider, messages, [])
      assert is_binary(key)
    end

    test "handles deeply nested message structures" do
      provider = :openai

      messages = [
        %{
          role: "system",
          content: "You are a helpful assistant"
        },
        %{
          role: "user",
          content: "Hello"
        },
        %{
          role: "assistant",
          content: "Hi! How can I help you?"
        },
        %{
          role: "user",
          content: [
            %{type: "text", text: "Look at these images"},
            %{type: "image_url", image_url: %{url: "https://example.com/1.jpg", detail: "high"}},
            %{type: "image_url", image_url: %{url: "https://example.com/2.jpg", detail: "low"}}
          ]
        }
      ]

      key = Cache.generate_cache_key(provider, messages, temperature: 0)
      assert is_binary(key)
    end
  end

  describe "concurrent access" do
    test "handles concurrent puts and gets" do
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            key = "concurrent-#{rem(i, 10)}"

            if rem(i, 2) == 0 do
              Cache.put(key, %{value: i})
            else
              Cache.get(key)
            end
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert length(results) == 100
    end

    test "handles concurrent cache operations with TTL" do
      key = "ttl-concurrent-#{System.unique_integer()}"

      # First, prime the cache
      {:ok, _cached_value} =
        Cache.with_cache(key, [cache: true, cache_ttl: 1000], fn ->
          {:ok, %LLMResponse{content: "cached-result"}}
        end)

      # Now multiple tasks should all get the cached value
      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            Cache.with_cache(key, [cache: true], fn ->
              # This shouldn't execute since value is cached
              {:ok, %LLMResponse{content: "should-not-see-this"}}
            end)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should get the same cached result
      assert Enum.all?(results, fn {:ok, result} ->
               result.content == "cached-result"
             end)
    end
  end

  describe "storage backend interface" do
    test "ETS backend handles all operations" do
      # This is implicitly tested by all other tests since ETS is the default
      # But let's explicitly test the backend behavior
      backend = Cache.Storage.ETS
      table = :test_cache_table

      # Start a new ETS table
      {:ok, state} = backend.init(name: table)

      # Test put and get
      key = "backend-test"
      value = %{data: "test"}
      expires_at = System.system_time(:millisecond) + 1000

      assert {:ok, _state} = backend.put(key, value, expires_at, state)
      assert {:ok, ^value, _state} = backend.get(key, state)

      # Test delete
      assert {:ok, _state} = backend.delete(key, state)
      assert {:miss, _state} = backend.get(key, state)

      # Test clear
      backend.put("key1", "val1", :infinity, state)
      backend.put("key2", "val2", :infinity, state)
      assert {:ok, _state} = backend.clear(state)
      assert {:miss, _state} = backend.get("key1", state)
      assert {:miss, _state} = backend.get("key2", state)
    end
  end

  describe "integration with LLM calls" do
    setup do
      # Configure mock adapter
      original_config = Application.get_env(:ex_llm, :mock_responses, %{})

      Application.put_env(:ex_llm, :mock_responses, %{
        chat: %ExLLM.Types.LLMResponse{
          content: "Mock response",
          # Note: Internal ExLLM format uses input_tokens/output_tokens
          usage: %{input_tokens: 10, output_tokens: 20, total_tokens: 30},
          model: "mock-model",
          cost: %{input: 0.01, output: 0.02, total: 0.03}
        }
      })

      on_exit(fn ->
        Application.put_env(:ex_llm, :mock_responses, original_config)
      end)

      :ok
    end

    test "caches LLM responses when enabled" do
      messages = [%{role: "user", content: "Hello"}]
      options = [cache: true, cache_ttl: 5000]

      # First call - cache miss
      {:ok, response1} = ExLLM.chat(:mock, messages, options)
      assert response1.content == "Mock response"

      # Modify mock to return different response
      Application.put_env(:ex_llm, :mock_responses, %{
        chat: %ExLLM.Types.LLMResponse{
          content: "Different response",
          # Note: Internal ExLLM format uses input_tokens/output_tokens
          usage: %{input_tokens: 10, output_tokens: 20, total_tokens: 30},
          model: "mock-model",
          cost: %{input: 0.01, output: 0.02, total: 0.03}
        }
      })

      # Second call - should get cached response
      {:ok, response2} = ExLLM.chat(:mock, messages, options)
      # Still the cached response
      assert response2.content == "Mock response"
    end

    test "bypasses cache when disabled" do
      messages = [%{role: "user", content: "Hello"}]

      # First call with cache
      {:ok, response1} = ExLLM.chat(:mock, messages, cache: true)
      assert response1.content == "Mock response"

      # Change mock response
      Application.put_env(:ex_llm, :mock_responses, %{
        chat: %ExLLM.Types.LLMResponse{
          content: "New response",
          # Note: Internal ExLLM format uses input_tokens/output_tokens
          usage: %{input_tokens: 10, output_tokens: 20, total_tokens: 30},
          model: "mock-model",
          cost: %{input: 0.01, output: 0.02, total: 0.03}
        }
      })

      # Second call without cache - should get new response
      {:ok, response2} = ExLLM.chat(:mock, messages, cache: false)
      assert response2.content == "New response"
    end
  end
end
