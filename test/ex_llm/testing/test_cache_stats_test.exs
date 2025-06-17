defmodule ExLLM.TestCacheStatsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias ExLLM.Testing.TestCacheStats

  setup do
    # Reset stats before each test
    TestCacheStats.reset_stats()

    on_exit(fn ->
      TestCacheStats.reset_stats()
    end)

    :ok
  end

  describe "record_hit/1" do
    test "increments hit counter" do
      initial = TestCacheStats.get_stats()
      assert initial.cache_hits == 0
      assert initial.total_requests == 0

      TestCacheStats.record_hit(%{provider: "openai"})

      stats = TestCacheStats.get_stats()
      assert stats.cache_hits == 1
      assert stats.total_requests == 1
    end

    test "records provider-specific hits" do
      TestCacheStats.record_hit(%{provider: "openai"})
      TestCacheStats.record_hit(%{provider: "openai"})
      TestCacheStats.record_hit(%{provider: "anthropic"})

      stats = TestCacheStats.get_provider_stats("openai")
      assert stats.cache_hits == 2
      assert stats.total_requests == 2

      stats = TestCacheStats.get_provider_stats("anthropic")
      assert stats.cache_hits == 1
      assert stats.total_requests == 1
    end

    test "records time savings" do
      metadata = %{
        provider: "openai",
        cached_response_time_ms: 5,
        estimated_api_time_ms: 1000
      }

      TestCacheStats.record_hit(metadata)

      stats = TestCacheStats.get_stats()
      # 1000 - 5
      assert stats.time_savings_ms == 995
    end
  end

  describe "record_miss/1" do
    test "increments miss counter" do
      TestCacheStats.record_miss(%{provider: "openai"})

      stats = TestCacheStats.get_stats()
      assert stats.cache_misses == 1
      assert stats.total_requests == 1
      assert stats.cache_hits == 0
    end

    test "records provider-specific misses" do
      TestCacheStats.record_miss(%{provider: "openai"})
      TestCacheStats.record_miss(%{provider: "openai"})

      stats = TestCacheStats.get_provider_stats("openai")
      assert stats.cache_misses == 2
      assert stats.total_requests == 2
    end
  end

  describe "record_refresh/1" do
    test "increments refresh counter" do
      TestCacheStats.record_refresh(%{provider: "openai", reason: :ttl_expired})

      stats = TestCacheStats.get_stats()
      assert stats.ttl_refreshes == 1
      assert stats.total_requests == 1
    end

    test "tracks refresh reasons" do
      TestCacheStats.record_refresh(%{provider: "openai", reason: :ttl_expired})
      TestCacheStats.record_refresh(%{provider: "openai", reason: :force_refresh})
      TestCacheStats.record_refresh(%{provider: "anthropic", reason: :ttl_expired})

      stats = TestCacheStats.get_refresh_reasons()
      assert stats[:ttl_expired] == 2
      assert stats[:force_refresh] == 1
    end
  end

  describe "record_cost_savings/1" do
    test "accumulates cost savings" do
      TestCacheStats.record_cost_savings(%{
        provider: "openai",
        estimated_cost: 0.002
      })

      TestCacheStats.record_cost_savings(%{
        provider: "anthropic",
        estimated_cost: 0.003
      })

      stats = TestCacheStats.get_stats()
      assert_in_delta stats.estimated_cost_savings, 0.005, 0.0001
    end

    test "tracks provider-specific cost savings" do
      TestCacheStats.record_cost_savings(%{
        provider: "openai",
        estimated_cost: 0.002
      })

      stats = TestCacheStats.get_provider_stats("openai")
      assert_in_delta stats.cost_savings, 0.002, 0.0001
    end
  end

  describe "record_storage_usage/1" do
    test "tracks storage metrics" do
      TestCacheStats.record_storage_usage(%{
        # 1 MB
        total_size_bytes: 1024 * 1024,
        # 512 KB
        unique_size_bytes: 512 * 1024,
        # 512 KB
        duplicate_size_bytes: 512 * 1024,
        total_entries: 100,
        unique_entries: 60
      })

      stats = TestCacheStats.get_storage_stats()
      assert stats.total_size_mb == 1.0
      assert stats.unique_size_mb == 0.5
      assert stats.deduplication_ratio == 0.5
      assert stats.total_entries == 100
      assert stats.unique_entries == 60
    end
  end

  describe "get_stats/0" do
    test "returns comprehensive statistics" do
      # Record various events
      TestCacheStats.record_hit(%{provider: "openai"})
      TestCacheStats.record_hit(%{provider: "anthropic"})
      TestCacheStats.record_miss(%{provider: "openai"})
      TestCacheStats.record_refresh(%{provider: "gemini", reason: :ttl_expired})

      stats = TestCacheStats.get_stats()

      assert stats.total_requests == 4
      assert stats.cache_hits == 2
      assert stats.cache_misses == 1
      assert stats.ttl_refreshes == 1
      assert stats.hit_rate == 0.5
    end

    test "handles zero requests gracefully" do
      stats = TestCacheStats.get_stats()

      assert stats.total_requests == 0
      assert stats.hit_rate == 0.0
      assert stats.miss_rate == 0.0
    end
  end

  describe "get_global_stats/0" do
    test "returns same data as get_stats" do
      TestCacheStats.record_hit(%{provider: "openai"})
      TestCacheStats.record_miss(%{provider: "anthropic"})

      global_stats = TestCacheStats.get_global_stats()
      regular_stats = TestCacheStats.get_stats()

      assert global_stats.total_requests == regular_stats.total_requests
      assert global_stats.cache_hits == regular_stats.cache_hits
      assert global_stats.hit_rate == regular_stats.hit_rate
    end
  end

  describe "get_provider_stats/1" do
    test "returns provider-specific statistics" do
      # Record OpenAI events
      TestCacheStats.record_hit(%{provider: "openai"})
      TestCacheStats.record_hit(%{provider: "openai"})
      TestCacheStats.record_miss(%{provider: "openai"})

      # Record Anthropic events
      TestCacheStats.record_hit(%{provider: "anthropic"})

      openai_stats = TestCacheStats.get_provider_stats("openai")
      assert openai_stats.total_requests == 3
      assert openai_stats.cache_hits == 2
      assert openai_stats.cache_misses == 1
      assert_in_delta openai_stats.hit_rate, 0.667, 0.001

      anthropic_stats = TestCacheStats.get_provider_stats("anthropic")
      assert anthropic_stats.total_requests == 1
      assert anthropic_stats.cache_hits == 1
      assert anthropic_stats.hit_rate == 1.0
    end

    test "returns empty stats for unknown provider" do
      stats = TestCacheStats.get_provider_stats("unknown")

      assert stats.total_requests == 0
      assert stats.cache_hits == 0
      assert stats.hit_rate == 0.0
    end
  end

  describe "get_test_stats/1" do
    test "returns test-specific statistics" do
      # Record events for specific tests
      TestCacheStats.record_hit(%{
        provider: "openai",
        test_module: "ExLLM.OpenAIIntegrationTest",
        test_name: "test chat"
      })

      TestCacheStats.record_hit(%{
        provider: "openai",
        test_module: "ExLLM.OpenAIIntegrationTest",
        test_name: "test chat"
      })

      TestCacheStats.record_miss(%{
        provider: "openai",
        test_module: "ExLLM.OpenAIIntegrationTest",
        test_name: "test embeddings"
      })

      test_key = "ExLLM.OpenAIIntegrationTest:test chat"
      stats = TestCacheStats.get_test_stats(test_key)

      assert stats.total_requests == 2
      assert stats.cache_hits == 2
      assert stats.hit_rate == 1.0
    end
  end

  describe "print_cache_summary/0" do
    test "prints formatted summary" do
      # Set up some stats
      TestCacheStats.record_hit(%{
        provider: "openai",
        cached_response_time_ms: 5,
        estimated_api_time_ms: 1000
      })

      TestCacheStats.record_miss(%{provider: "anthropic"})

      TestCacheStats.record_cost_savings(%{
        provider: "openai",
        estimated_cost: 0.002
      })

      TestCacheStats.record_storage_usage(%{
        total_size_bytes: 15 * 1024 * 1024,
        unique_size_bytes: 8 * 1024 * 1024,
        duplicate_size_bytes: 7 * 1024 * 1024,
        total_entries: 234,
        unique_entries: 125
      })

      # Capture output
      output =
        capture_io(fn ->
          TestCacheStats.print_cache_summary()
        end)

      # Verify output contains expected information
      assert output =~ "Test Cache Summary"
      assert output =~ "Total Requests: 2"
      assert output =~ "Cache Hits: 1"
      assert output =~ "Cache Misses: 1"
      assert output =~ "Time Savings:"
      assert output =~ "Cost Savings:"
      assert output =~ "Storage Used:"
      assert output =~ "Deduplication Ratio:"
    end
  end

  describe "reset_stats/0" do
    test "clears all statistics" do
      # Record some events
      TestCacheStats.record_hit(%{provider: "openai"})
      TestCacheStats.record_miss(%{provider: "anthropic"})
      TestCacheStats.record_cost_savings(%{provider: "openai", estimated_cost: 0.01})

      # Verify stats exist
      stats = TestCacheStats.get_stats()
      assert stats.total_requests > 0

      # Reset
      TestCacheStats.reset_stats()

      # Verify all cleared
      stats = TestCacheStats.get_stats()
      assert stats.total_requests == 0
      assert stats.cache_hits == 0
      assert stats.cache_misses == 0
      assert stats.estimated_cost_savings == 0.0
    end
  end

  describe "format_duration/1" do
    test "formats milliseconds into human-readable duration" do
      assert TestCacheStats.format_duration(500) == "500ms"
      assert TestCacheStats.format_duration(1500) == "1.5s"
      assert TestCacheStats.format_duration(65_000) == "1m 5s"
      assert TestCacheStats.format_duration(3_665_000) == "1h 1m 5s"
    end
  end

  describe "format_percentage/1" do
    test "formats float as percentage" do
      assert TestCacheStats.format_percentage(0.0) == "0.0%"
      assert TestCacheStats.format_percentage(0.5) == "50.0%"
      assert TestCacheStats.format_percentage(0.867) == "86.7%"
      assert TestCacheStats.format_percentage(1.0) == "100.0%"
    end
  end

  describe "get_cache_age_stats/0" do
    test "returns cache age statistics" do
      # This would require integration with actual cache files
      # For unit test, we just verify the function exists and returns expected structure
      stats = TestCacheStats.get_cache_age_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :oldest_entry_days)
      assert Map.has_key?(stats, :newest_entry_days)
      assert Map.has_key?(stats, :average_age_days)
    end
  end

  describe "record_fallback/1" do
    test "tracks fallback usage" do
      TestCacheStats.record_fallback(%{
        provider: "openai",
        fallback_type: :older_timestamp,
        original_timestamp: ~U[2024-01-22 10:00:00Z],
        fallback_timestamp: ~U[2024-01-20 10:00:00Z]
      })

      stats = TestCacheStats.get_stats()
      assert stats.fallback_to_older == 1
    end
  end

  # Test private helper functions through public interface
  describe "integration scenarios" do
    test "comprehensive usage scenario" do
      # Simulate a test run with various outcomes

      # 10 cache hits
      for _ <- 1..10 do
        TestCacheStats.record_hit(%{
          provider: "openai",
          cached_response_time_ms: 5,
          estimated_api_time_ms: 1000
        })

        TestCacheStats.record_cost_savings(%{
          provider: "openai",
          estimated_cost: 0.001
        })
      end

      # 2 cache misses
      for _ <- 1..2 do
        TestCacheStats.record_miss(%{provider: "anthropic"})
      end

      # 1 TTL refresh
      TestCacheStats.record_refresh(%{
        provider: "gemini",
        reason: :ttl_expired
      })

      # Final stats
      stats = TestCacheStats.get_stats()
      assert stats.total_requests == 13
      assert stats.cache_hits == 10
      assert stats.cache_misses == 2
      assert stats.ttl_refreshes == 1
      assert_in_delta stats.hit_rate, 0.769, 0.001
      assert stats.time_savings_ms == 9950
      assert_in_delta stats.estimated_cost_savings, 0.01, 0.0001
    end
  end
end
