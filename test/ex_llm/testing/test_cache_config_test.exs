defmodule ExLLM.TestCacheConfigTest do
  use ExUnit.Case, async: false
  alias ExLLM.Testing.TestCacheConfig

  describe "get_config/0" do
    setup do
      # Store original config
      original_config = Application.get_env(:ex_llm, :test_cache, %{})

      on_exit(fn ->
        # Restore original config
        Application.put_env(:ex_llm, :test_cache, original_config)
        # Clear any env vars we set
        System.delete_env("EX_LLM_TEST_CACHE_ENABLED")
        System.delete_env("EX_LLM_TEST_CACHE_DIR")
        System.delete_env("EX_LLM_TEST_CACHE_TTL")
        System.delete_env("EX_LLM_TEST_CACHE_FALLBACK_STRATEGY")
        System.delete_env("EX_LLM_TEST_CACHE_OAUTH2_TTL")
        System.delete_env("EX_LLM_TEST_CACHE_OPENAI_TTL")
        System.delete_env("EX_LLM_TEST_CACHE_GEMINI_TTL")
        System.delete_env("EX_LLM_TEST_CACHE_ANTHROPIC_TTL")
      end)

      :ok
    end

    test "returns default configuration when no overrides" do
      Application.delete_env(:ex_llm, :test_cache)

      config = TestCacheConfig.get_config()

      assert config.enabled == true
      assert config.auto_detect == true
      assert config.cache_dir == "test/cache"
      assert config.organization == :by_provider
      assert config.cache_integration_tests == true
      assert config.cache_oauth2_tests == true
      assert config.replay_by_default == true
      assert config.save_on_miss == true
      # 7 days in milliseconds
      assert config.ttl == 7 * 24 * 60 * 60 * 1000
      assert config.timestamp_format == :iso8601
      assert config.fallback_strategy == :latest_success
      assert config.max_entries_per_cache == 10
      # 30 days in milliseconds
      assert config.cleanup_older_than == 30 * 24 * 60 * 60 * 1000
      # 7 days in milliseconds
      assert config.compress_older_than == 7 * 24 * 60 * 60 * 1000
      assert config.deduplicate_content == true
      assert config.content_hash_algorithm == :sha256
    end

    test "merges application config with defaults" do
      Application.put_env(:ex_llm, :test_cache, %{
        enabled: false,
        cache_dir: "custom/cache",
        ttl: 3600,
        fallback_strategy: :latest_any
      })

      config = TestCacheConfig.get_config()

      assert config.enabled == false
      assert config.cache_dir == "custom/cache"
      assert config.ttl == 3600
      assert config.fallback_strategy == :latest_any
      # Other values should be defaults
      assert config.auto_detect == true
      assert config.max_entries_per_cache == 10
    end

    test "environment variables override all other config" do
      Application.put_env(:ex_llm, :test_cache, %{
        enabled: true,
        cache_dir: "app/cache"
      })

      System.put_env("EX_LLM_TEST_CACHE_ENABLED", "false")
      System.put_env("EX_LLM_TEST_CACHE_DIR", "env/cache")
      System.put_env("EX_LLM_TEST_CACHE_TTL", "3600")
      System.put_env("EX_LLM_TEST_CACHE_FALLBACK_STRATEGY", "latest_any")

      config = TestCacheConfig.get_config()

      assert config.enabled == false
      assert config.cache_dir == "env/cache"
      # Converted to milliseconds
      assert config.ttl == 3600_000
      assert config.fallback_strategy == :latest_any
    end

    test "handles TTL special values from environment" do
      System.put_env("EX_LLM_TEST_CACHE_TTL", "0")
      config = TestCacheConfig.get_config()
      assert config.ttl == :infinity

      System.put_env("EX_LLM_TEST_CACHE_TTL", "infinity")
      config = TestCacheConfig.get_config()
      assert config.ttl == :infinity

      System.put_env("EX_LLM_TEST_CACHE_TTL", "300")
      config = TestCacheConfig.get_config()
      # 300 seconds in milliseconds
      assert config.ttl == 300_000
    end

    test "validates configuration and creates cache directory" do
      Application.put_env(:ex_llm, :test_cache, %{
        enabled: true,
        cache_dir: "test/tmp/cache_test_#{:rand.uniform(10000)}"
      })

      config = TestCacheConfig.get_config()

      assert File.exists?(config.cache_dir)

      # Cleanup
      File.rm_rf!(config.cache_dir)
    end

    test "raises error for invalid fallback strategy" do
      Application.put_env(:ex_llm, :test_cache, %{
        fallback_strategy: :invalid_strategy
      })

      assert_raise ArgumentError, ~r/Invalid fallback_strategy/, fn ->
        TestCacheConfig.get_config()
      end
    end

    test "raises error for invalid TTL" do
      Application.put_env(:ex_llm, :test_cache, %{
        ttl: -100
      })

      assert_raise ArgumentError, ~r/Invalid TTL/, fn ->
        TestCacheConfig.get_config()
      end
    end
  end

  describe "enabled?/0" do
    setup do
      original_config = Application.get_env(:ex_llm, :test_cache, %{})
      on_exit(fn -> Application.put_env(:ex_llm, :test_cache, original_config) end)
      :ok
    end

    test "returns true when enabled in test environment" do
      Application.put_env(:ex_llm, :test_cache, %{enabled: true, auto_detect: true})
      assert TestCacheConfig.enabled?() == true
    end

    test "returns false when explicitly disabled" do
      Application.put_env(:ex_llm, :test_cache, %{enabled: false})
      assert TestCacheConfig.enabled?() == false
    end

    test "returns config value when auto_detect is false" do
      Application.put_env(:ex_llm, :test_cache, %{enabled: true, auto_detect: false})
      assert TestCacheConfig.enabled?() == true

      Application.put_env(:ex_llm, :test_cache, %{enabled: false, auto_detect: false})
      assert TestCacheConfig.enabled?() == false
    end
  end

  describe "cache_dir/0" do
    setup do
      original_config = Application.get_env(:ex_llm, :test_cache, %{})
      on_exit(fn -> Application.put_env(:ex_llm, :test_cache, original_config) end)
      :ok
    end

    test "returns cache directory and ensures it exists" do
      test_dir = "test/tmp/cache_dir_test_#{:rand.uniform(10000)}"
      Application.put_env(:ex_llm, :test_cache, %{cache_dir: test_dir})

      assert TestCacheConfig.cache_dir() == test_dir
      assert File.exists?(test_dir)

      # Cleanup
      File.rm_rf!(test_dir)
    end
  end

  describe "get_ttl/2" do
    setup do
      original_config = Application.get_env(:ex_llm, :test_cache, %{})

      on_exit(fn ->
        Application.put_env(:ex_llm, :test_cache, original_config)
        System.delete_env("EX_LLM_TEST_CACHE_TTL")
        System.delete_env("EX_LLM_TEST_CACHE_OAUTH2_TTL")
        System.delete_env("EX_LLM_TEST_CACHE_OPENAI_TTL")
      end)

      :ok
    end

    test "returns base TTL when no specific overrides" do
      Application.put_env(:ex_llm, :test_cache, %{ttl: 5000})

      assert TestCacheConfig.get_ttl([], :openai) == 5000
      assert TestCacheConfig.get_ttl([:integration], :anthropic) == 5000
    end

    test "returns OAuth2-specific TTL when OAuth2 tag present" do
      Application.put_env(:ex_llm, :test_cache, %{ttl: 5000})
      System.put_env("EX_LLM_TEST_CACHE_OAUTH2_TTL", "10")

      assert TestCacheConfig.get_ttl([:oauth2], :gemini) == 10_000
      assert TestCacheConfig.get_ttl([:integration], :gemini) == 5000
    end

    test "returns provider-specific TTL when configured" do
      Application.put_env(:ex_llm, :test_cache, %{ttl: 5000})
      System.put_env("EX_LLM_TEST_CACHE_OPENAI_TTL", "20")

      assert TestCacheConfig.get_ttl([], :openai) == 20_000
      assert TestCacheConfig.get_ttl([], :anthropic) == 5000
    end

    test "OAuth2 TTL takes precedence over provider TTL" do
      Application.put_env(:ex_llm, :test_cache, %{ttl: 5000})
      System.put_env("EX_LLM_TEST_CACHE_OAUTH2_TTL", "10")
      System.put_env("EX_LLM_TEST_CACHE_GEMINI_TTL", "20")

      assert TestCacheConfig.get_ttl([:oauth2], :gemini) == 10_000
      assert TestCacheConfig.get_ttl([], :gemini) == 20_000
    end
  end

  describe "get_fallback_strategy/1" do
    setup do
      original_config = Application.get_env(:ex_llm, :test_cache, %{})

      on_exit(fn ->
        Application.put_env(:ex_llm, :test_cache, original_config)
        System.delete_env("EX_LLM_TEST_CACHE_OAUTH2_STRATEGY")
        System.delete_env("EX_LLM_TEST_CACHE_INTEGRATION_STRATEGY")
      end)

      :ok
    end

    test "returns base strategy when no specific overrides" do
      Application.put_env(:ex_llm, :test_cache, %{fallback_strategy: :latest_success})

      assert TestCacheConfig.get_fallback_strategy([]) == :latest_success
      assert TestCacheConfig.get_fallback_strategy([:unit]) == :latest_success
    end

    test "returns OAuth2-specific strategy when configured" do
      Application.put_env(:ex_llm, :test_cache, %{fallback_strategy: :latest_success})
      System.put_env("EX_LLM_TEST_CACHE_OAUTH2_STRATEGY", "latest_any")

      assert TestCacheConfig.get_fallback_strategy([:oauth2]) == :latest_any
      assert TestCacheConfig.get_fallback_strategy([:integration]) == :latest_success
    end

    test "returns integration-specific strategy when configured" do
      Application.put_env(:ex_llm, :test_cache, %{fallback_strategy: :latest_success})
      System.put_env("EX_LLM_TEST_CACHE_INTEGRATION_STRATEGY", "best_match")

      assert TestCacheConfig.get_fallback_strategy([:integration]) == :best_match
      assert TestCacheConfig.get_fallback_strategy([:oauth2]) == :latest_success
    end
  end

  describe "environment variable parsing" do
    setup do
      on_exit(fn ->
        System.delete_env("EX_LLM_TEST_CACHE_ENABLED")
        System.delete_env("EX_LLM_TEST_CACHE_MAX_ENTRIES")
        System.delete_env("EX_LLM_TEST_CACHE_CLEANUP_OLDER_THAN")
      end)

      :ok
    end

    test "parses boolean environment variables correctly" do
      System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")
      config = TestCacheConfig.get_config()
      assert config.enabled == true

      System.put_env("EX_LLM_TEST_CACHE_ENABLED", "false")
      config = TestCacheConfig.get_config()
      assert config.enabled == false

      System.put_env("EX_LLM_TEST_CACHE_ENABLED", "invalid")
      config = TestCacheConfig.get_config()
      # Falls back to default
      assert config.enabled == true
    end

    test "parses integer environment variables correctly" do
      System.put_env("EX_LLM_TEST_CACHE_MAX_ENTRIES", "5")
      config = TestCacheConfig.get_config()
      assert config.max_entries_per_cache == 5

      System.put_env("EX_LLM_TEST_CACHE_MAX_ENTRIES", "invalid")
      config = TestCacheConfig.get_config()
      # Falls back to default
      assert config.max_entries_per_cache == 10
    end

    test "parses duration environment variables correctly" do
      System.put_env("EX_LLM_TEST_CACHE_CLEANUP_OLDER_THAN", "7d")
      config = TestCacheConfig.get_config()
      # 7 days in ms
      assert config.cleanup_older_than == 7 * 24 * 60 * 60 * 1000

      System.put_env("EX_LLM_TEST_CACHE_CLEANUP_OLDER_THAN", "2h")
      config = TestCacheConfig.get_config()
      assert config.cleanup_older_than == :timer.hours(2)

      System.put_env("EX_LLM_TEST_CACHE_CLEANUP_OLDER_THAN", "30m")
      config = TestCacheConfig.get_config()
      assert config.cleanup_older_than == :timer.minutes(30)

      System.put_env("EX_LLM_TEST_CACHE_CLEANUP_OLDER_THAN", "60s")
      config = TestCacheConfig.get_config()
      assert config.cleanup_older_than == :timer.seconds(60)
    end
  end
end
