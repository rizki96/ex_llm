defmodule ExLLM.TestCacheStrategyTest do
  use ExUnit.Case, async: false
  alias ExLLM.Testing.TestCacheStrategy
  alias ExLLM.Testing.TestCacheDetector
  alias ExLLM.Testing.TestCacheConfig
  alias ExLLM.Testing.TestCacheIndex
  alias ExLLM.Infrastructure.Cache.Storage.TestCache

  setup do
    # Store original configs
    original_cache_config = Application.get_env(:ex_llm, :test_cache, %{})
    original_test_context = TestCacheDetector.get_current_test_context()

    # Create test directory
    test_dir = "test/tmp/strategy_test_#{:rand.uniform(10000)}"
    File.mkdir_p!(test_dir)

    # Configure test cache
    Application.put_env(:ex_llm, :test_cache, %{
      enabled: true,
      auto_detect: true,
      cache_dir: test_dir,
      ttl: :timer.hours(1),
      fallback_strategy: :latest_success,
      cache_integration_tests: true,
      cache_oauth2_tests: true,
      cache_live_api_tests: true
    })

    on_exit(fn ->
      Application.put_env(:ex_llm, :test_cache, original_cache_config)
      TestCacheDetector.clear_test_context()
      File.rm_rf!(test_dir)
    end)

    {:ok, test_dir: test_dir}
  end

  describe "execute/2" do
    test "returns proceed when caching is disabled" do
      Application.put_env(:ex_llm, :test_cache, %{enabled: false})

      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4"},
        headers: []
      }

      assert {:proceed, metadata} = TestCacheStrategy.execute(request)
      assert metadata.cache_key == nil
    end

    test "returns proceed when not in cacheable test context" do
      # Clear test context
      TestCacheDetector.clear_test_context()

      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4"},
        headers: []
      }

      assert {:proceed, metadata} = TestCacheStrategy.execute(request)
      assert metadata.cache_key == nil
    end

    test "returns cached response when cache hit", %{test_dir: test_dir} do
      # Set up test context
      TestCacheDetector.set_test_context(%{
        module: ExLLM.IntegrationTest,
        test_name: "test chat",
        tags: [:integration],
        pid: self()
      })

      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4", "messages" => [%{"role" => "user", "content" => "Hello"}]},
        headers: [{"Authorization", "Bearer sk-test"}]
      }

      # Store a cached response
      cache_key = TestCacheStrategy.generate_cache_key(request)
      cache_dir = Path.join(test_dir, cache_key)

      cached_response = %{
        status: 200,
        body: %{"choices" => [%{"message" => %{"content" => "Hello!"}}]},
        headers: [%{"name" => "Content-Type", "value" => "application/json"}]
      }

      test_context =
        case TestCacheDetector.get_current_test_context() do
          {:ok, ctx} ->
            # Sanitize the context to remove PIDs
            ctx
            |> Map.put(:pid, inspect(ctx[:pid]))

          :error ->
            nil
        end

      metadata = %{
        test_context: test_context,
        provider: "openai",
        endpoint: "/v1/chat/completions"
      }

      {:ok, _} = TestCache.store(cache_key, cached_response, metadata)

      # Execute strategy
      assert {:cached, response, cache_metadata} = TestCacheStrategy.execute(request)
      assert response["status"] == 200

      assert response["body"]["choices"] |> hd |> Map.get("message") |> Map.get("content") ==
               "Hello!"

      assert cache_metadata.from_cache == true
    end

    test "returns proceed when cache miss", %{test_dir: test_dir} do
      # Set up test context
      TestCacheDetector.set_test_context(%{
        module: ExLLM.IntegrationTest,
        test_name: "test chat",
        tags: [:integration],
        pid: self()
      })

      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{
          "model" => "gpt-4",
          "messages" => [%{"role" => "user", "content" => "New request"}]
        },
        headers: []
      }

      assert {:proceed, metadata} = TestCacheStrategy.execute(request)
      assert metadata.cache_key != nil
      assert metadata.should_save == true
    end

    test "handles expired cache entries", %{test_dir: test_dir} do
      # Set up test context
      TestCacheDetector.set_test_context(%{
        module: ExLLM.IntegrationTest,
        test_name: "test chat",
        tags: [:integration],
        pid: self()
      })

      # Configure short TTL
      Application.put_env(:ex_llm, :test_cache, %{
        enabled: true,
        cache_dir: test_dir,
        # 100ms TTL
        ttl: 100
      })

      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4"},
        headers: []
      }

      # Store an old response
      cache_key = TestCacheStrategy.generate_cache_key(request)
      cached_response = %{status: 200, body: %{}, headers: []}
      {:ok, _} = TestCache.store(cache_key, cached_response, %{})

      # Wait for TTL to expire
      Process.sleep(150)

      # Should proceed due to expired cache
      assert {:proceed, metadata} = TestCacheStrategy.execute(request)
      assert metadata.cache_expired == true
    end
  end

  describe "generate_cache_key/1" do
    test "generates consistent cache keys for same requests" do
      request1 = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4", "messages" => []},
        headers: []
      }

      request2 = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4", "messages" => []},
        headers: []
      }

      key1 = TestCacheStrategy.generate_cache_key(request1)
      key2 = TestCacheStrategy.generate_cache_key(request2)

      assert key1 == key2
    end

    test "generates different keys for different requests" do
      request1 = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4"},
        headers: []
      }

      request2 = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-3.5"},
        headers: []
      }

      key1 = TestCacheStrategy.generate_cache_key(request1)
      key2 = TestCacheStrategy.generate_cache_key(request2)

      assert key1 != key2
    end

    test "ignores sensitive headers in cache key" do
      request1 = %{
        url: "test",
        body: %{},
        headers: [{"Authorization", "Bearer secret1"}]
      }

      request2 = %{
        url: "test",
        body: %{},
        headers: [{"Authorization", "Bearer secret2"}]
      }

      key1 = TestCacheStrategy.generate_cache_key(request1)
      key2 = TestCacheStrategy.generate_cache_key(request2)

      # Should generate same key despite different auth tokens
      assert key1 == key2
    end

    test "includes provider in cache key" do
      request_openai = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{},
        headers: []
      }

      request_anthropic = %{
        url: "https://api.anthropic.com/v1/messages",
        body: %{},
        headers: []
      }

      key_openai = TestCacheStrategy.generate_cache_key(request_openai)
      key_anthropic = TestCacheStrategy.generate_cache_key(request_anthropic)

      assert String.contains?(key_openai, "openai")
      assert String.contains?(key_anthropic, "anthropic")
    end
  end

  describe "save_response/3" do
    test "saves response when caching is enabled", %{test_dir: test_dir} do
      TestCacheDetector.set_test_context(%{
        module: ExLLM.IntegrationTest,
        test_name: "test save",
        tags: [:integration],
        pid: self()
      })

      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4"},
        headers: []
      }

      response = %{
        status: 200,
        body: %{"result" => "success"},
        headers: [{"Content-Type", "application/json"}]
      }

      metadata = %{
        cache_key: TestCacheStrategy.generate_cache_key(request),
        provider: "openai",
        response_time_ms: 100
      }

      assert :ok = TestCacheStrategy.save_response(request, response, metadata)

      # Verify it was saved
      cache_dir = Path.join(test_dir, metadata.cache_key)
      assert File.exists?(cache_dir)

      # Check index was updated
      index = TestCacheIndex.load_index(cache_dir)
      assert length(index.entries) == 1
    end

    test "skips saving when should_save is false", %{test_dir: test_dir} do
      request = %{url: "test", body: %{}, headers: []}
      response = %{status: 200, body: %{}, headers: []}
      metadata = %{cache_key: "test_key", should_save: false}

      assert :ok = TestCacheStrategy.save_response(request, response, metadata)

      # Should not create cache directory
      cache_dir = Path.join(test_dir, "test_key")
      assert not File.exists?(cache_dir)
    end

    test "handles save errors gracefully" do
      request = %{url: "test", body: %{}, headers: []}
      response = %{status: 200, body: %{}, headers: []}

      # Invalid cache key that would cause file system error
      metadata = %{cache_key: "/invalid/path/\0/key", should_save: true}

      # Should not crash
      assert :ok = TestCacheStrategy.save_response(request, response, metadata)
    end
  end

  describe "get_cached_response/3" do
    test "retrieves cached response within TTL", %{test_dir: test_dir} do
      cache_key = "test/cache_retrieval"
      cache_dir = Path.join(test_dir, cache_key)

      cached_response = %{
        status: 200,
        body: %{"cached" => true},
        headers: []
      }

      {:ok, _} = TestCache.store(cache_key, cached_response, %{})

      request = %{url: "test", body: %{}, headers: []}
      fallback_opts = [strategy: :latest_success]

      assert {:ok, response, metadata} =
               TestCacheStrategy.get_cached_response(
                 cache_key,
                 request,
                 fallback_opts
               )

      assert response["body"]["cached"] == true
      assert Map.has_key?(metadata, :from_cache)
    end

    test "returns miss for non-existent cache", %{test_dir: test_dir} do
      cache_key = "test/nonexistent"
      request = %{url: "test", body: %{}, headers: []}

      assert :miss = TestCacheStrategy.get_cached_response(cache_key, request, [])
    end

    test "uses fallback strategy when primary fails", %{test_dir: test_dir} do
      cache_key = "test/fallback_test"
      request = %{url: "test", body: %{}, headers: []}

      # Store an error response and a success response
      error_response = %{status: 500, body: %{"error" => true}, headers: []}
      success_response = %{status: 200, body: %{"success" => true}, headers: []}

      {:ok, _} = TestCache.store(cache_key, error_response, %{status: :error})
      # Ensure different timestamps
      Process.sleep(10)
      {:ok, _} = TestCache.store(cache_key, success_response, %{status: :success})

      # With latest_success strategy, should return the success response
      fallback_opts = [strategy: :latest_success]

      {:ok, response, _} =
        TestCacheStrategy.get_cached_response(
          cache_key,
          request,
          fallback_opts
        )

      assert response["body"]["success"] == true
    end
  end

  describe "build_request_metadata/2" do
    test "builds complete metadata for caching" do
      cache_key = "test/metadata"

      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4"},
        headers: [{"User-Agent", "ExLLM"}]
      }

      metadata = TestCacheStrategy.build_request_metadata(cache_key, request)

      assert metadata.cache_key == cache_key
      assert metadata.provider == "openai"
      assert metadata.endpoint == "/v1/chat/completions"
      assert metadata.should_save == true
      assert metadata.request_hash != nil
    end

    test "extracts provider from URL" do
      requests = [
        {%{url: "https://api.openai.com/v1/test", body: %{}, headers: []}, "openai"},
        {%{url: "https://api.anthropic.com/v1/test", body: %{}, headers: []}, "anthropic"},
        {%{url: "https://generativelanguage.googleapis.com/v1/test", body: %{}, headers: []},
         "gemini"},
        {%{url: "https://api.example.com/test", body: %{}, headers: []}, "unknown"}
      ]

      for {request, expected_provider} <- requests do
        metadata = TestCacheStrategy.build_request_metadata("key", request)
        assert metadata.provider == expected_provider
      end
    end
  end

  describe "should_use_cache?/1" do
    test "returns true for normal requests" do
      # Set up test context
      TestCacheDetector.set_test_context(%{
        module: __MODULE__,
        tags: [:integration],
        test_name: "test should_use_cache",
        pid: self()
      })

      options = []
      assert TestCacheStrategy.should_use_cache?(options) == true
    end

    test "returns false when force_refresh is true" do
      options = [force_refresh: true]
      assert TestCacheStrategy.should_use_cache?(options) == false
    end

    test "returns false when cache is explicitly disabled" do
      options = [cache: false]
      assert TestCacheStrategy.should_use_cache?(options) == false
    end

    test "returns false for streaming requests" do
      options = [stream: true]
      assert TestCacheStrategy.should_use_cache?(options) == false
    end
  end

  describe "extract_provider/1" do
    test "extracts provider from various URLs" do
      assert TestCacheStrategy.extract_provider("https://api.openai.com/v1/chat") == "openai"

      assert TestCacheStrategy.extract_provider("https://api.anthropic.com/v1/messages") ==
               "anthropic"

      assert TestCacheStrategy.extract_provider("https://api.groq.com/openai/v1/chat") == "groq"

      assert TestCacheStrategy.extract_provider("https://generativelanguage.googleapis.com/v1") ==
               "gemini"

      assert TestCacheStrategy.extract_provider("http://localhost:11434/api/chat") == "ollama"
      assert TestCacheStrategy.extract_provider("https://unknown.com/api") == "unknown"
    end
  end

  describe "normalize_request_for_cache/1" do
    test "removes sensitive data from request" do
      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{
          "model" => "gpt-4",
          "messages" => [%{"role" => "user", "content" => "Hello"}],
          # Should be removed
          "user" => "user-123"
        },
        headers: [
          # Should be removed
          {"Authorization", "Bearer sk-secret"},
          {"Content-Type", "application/json"},
          # Should be removed
          {"X-API-Key", "secret-key"}
        ]
      }

      normalized = TestCacheStrategy.normalize_request_for_cache(request)

      # Check sensitive data removed
      assert not Map.has_key?(normalized.body, "user")

      # Check sensitive headers removed
      header_keys = normalized.headers |> Enum.map(&elem(&1, 0))
      assert "Authorization" not in header_keys
      assert "X-API-Key" not in header_keys
      assert "Content-Type" in header_keys
    end

    test "sorts body keys for consistent hashing" do
      request = %{
        url: "test",
        body: %{
          "z" => 1,
          "a" => 2,
          "m" => %{"b" => 3, "a" => 4}
        },
        headers: []
      }

      normalized = TestCacheStrategy.normalize_request_for_cache(request)

      # Keys should be sorted
      keys = Map.keys(normalized.body)
      assert keys == ["a", "m", "z"]

      # Nested keys should also be sorted
      nested_keys = Map.keys(normalized.body["m"])
      assert nested_keys == ["a", "b"]
    end
  end
end
