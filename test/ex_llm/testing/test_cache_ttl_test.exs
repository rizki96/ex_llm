defmodule ExLLM.TestCacheTTLTest do
  use ExUnit.Case, async: false
  alias ExLLM.Testing.TestCacheTTL
  alias ExLLM.Testing.TestCacheIndex
  alias ExLLM.Testing.TestCacheTimestamp

  setup do
    # Create a temporary test directory
    test_dir = "test/tmp/ttl_test_#{:rand.uniform(10000)}"
    File.mkdir_p!(test_dir)

    on_exit(fn -> File.rm_rf!(test_dir) end)

    {:ok, test_dir: test_dir}
  end

  describe "cache_expired?/2" do
    test "returns false for infinity TTL" do
      timestamp = DateTime.utc_now()
      assert TestCacheTTL.cache_expired?(timestamp, :infinity) == false

      # Even very old timestamps should not expire with infinity TTL
      old_timestamp = DateTime.add(timestamp, -365, :day)
      assert TestCacheTTL.cache_expired?(old_timestamp, :infinity) == false
    end

    test "returns true for expired cache with numeric TTL" do
      timestamp = DateTime.add(DateTime.utc_now(), -2, :hour)
      # 1 hour TTL
      ttl_ms = :timer.hours(1)

      assert TestCacheTTL.cache_expired?(timestamp, ttl_ms) == true
    end

    test "returns false for non-expired cache with numeric TTL" do
      timestamp = DateTime.add(DateTime.utc_now(), -30, :minute)
      # 1 hour TTL
      ttl_ms = :timer.hours(1)

      assert TestCacheTTL.cache_expired?(timestamp, ttl_ms) == false
    end
  end

  describe "get_cache_age/1" do
    test "calculates age in milliseconds" do
      timestamp = DateTime.add(DateTime.utc_now(), -5, :minute)
      age_ms = TestCacheTTL.get_cache_age(timestamp)

      # Should be approximately 5 minutes (300,000 ms)
      assert age_ms >= 299_000
      assert age_ms <= 301_000
    end

    test "returns small value for recent timestamp" do
      timestamp = DateTime.utc_now()
      age_ms = TestCacheTTL.get_cache_age(timestamp)

      assert age_ms >= 0
      # Less than 1 second
      assert age_ms < 1000
    end
  end

  describe "should_warm_cache?/2" do
    test "returns false for infinity TTL" do
      timestamp = DateTime.utc_now()
      assert TestCacheTTL.should_warm_cache?(timestamp, :infinity) == false
    end

    test "returns true when cache is near expiration (>80% of TTL)" do
      # Cache is 55 minutes old with 1 hour TTL (91.6% of TTL)
      timestamp = DateTime.add(DateTime.utc_now(), -55, :minute)
      ttl_ms = :timer.hours(1)

      assert TestCacheTTL.should_warm_cache?(timestamp, ttl_ms) == true
    end

    test "returns false when cache is fresh (<80% of TTL)" do
      # Cache is 30 minutes old with 1 hour TTL (50% of TTL)
      timestamp = DateTime.add(DateTime.utc_now(), -30, :minute)
      ttl_ms = :timer.hours(1)

      assert TestCacheTTL.should_warm_cache?(timestamp, ttl_ms) == false
    end
  end

  describe "select_cache_entry/3" do
    test "returns :none for non-existent directory", %{test_dir: test_dir} do
      non_existent = Path.join(test_dir, "does_not_exist")

      assert TestCacheTTL.select_cache_entry(non_existent, :timer.hours(1), :latest_success) ==
               :none
    end

    test "selects valid entry within TTL", %{test_dir: test_dir} do
      # Create index with entries
      now = DateTime.utc_now()

      recent_entry = %{
        timestamp: DateTime.add(now, -30, :minute),
        filename: "recent.json",
        status: :success,
        size: 1024,
        content_hash: "abc123",
        response_time_ms: 100,
        api_version: nil,
        cost: nil
      }

      index = %{
        cache_key: "test",
        entries: [recent_entry],
        total_requests: 1,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      TestCacheIndex.save_index(test_dir, index)

      # Should select the recent entry
      assert {:ok, "recent.json"} =
               TestCacheTTL.select_cache_entry(
                 test_dir,
                 :timer.hours(1),
                 :latest_success
               )
    end

    test "returns expired entry when all entries are expired", %{test_dir: test_dir} do
      # Create index with old entries
      now = DateTime.utc_now()

      old_entry = %{
        timestamp: DateTime.add(now, -2, :hour),
        filename: "old.json",
        status: :success,
        size: 1024,
        content_hash: "abc123",
        response_time_ms: 100,
        api_version: nil,
        cost: nil
      }

      index = %{
        cache_key: "test",
        entries: [old_entry],
        total_requests: 1,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      TestCacheIndex.save_index(test_dir, index)

      # Should return expired entry
      assert {:expired, "old.json"} =
               TestCacheTTL.select_cache_entry(
                 test_dir,
                 :timer.hours(1),
                 :latest_success
               )
    end
  end

  describe "get_latest_valid_entry/2" do
    test "returns latest non-expired entry", %{test_dir: test_dir} do
      now = DateTime.utc_now()

      entries = [
        %{
          timestamp: DateTime.add(now, -10, :minute),
          filename: "newest.json",
          status: :success,
          size: 1024,
          content_hash: "abc123",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        },
        %{
          timestamp: DateTime.add(now, -30, :minute),
          filename: "older.json",
          status: :success,
          size: 1024,
          content_hash: "def456",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        }
      ]

      index = %{
        cache_key: "test",
        entries: entries,
        total_requests: 2,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      TestCacheIndex.save_index(test_dir, index)

      assert {:ok, "newest.json"} =
               TestCacheTTL.get_latest_valid_entry(
                 test_dir,
                 :timer.hours(1)
               )
    end

    test "returns :none when all entries are expired", %{test_dir: test_dir} do
      now = DateTime.utc_now()

      old_entry = %{
        timestamp: DateTime.add(now, -2, :hour),
        filename: "old.json",
        status: :success,
        size: 1024,
        content_hash: "abc123",
        response_time_ms: 100,
        api_version: nil,
        cost: nil
      }

      index = %{
        cache_key: "test",
        entries: [old_entry],
        total_requests: 1,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      TestCacheIndex.save_index(test_dir, index)

      assert TestCacheTTL.get_latest_valid_entry(test_dir, :timer.hours(1)) == :none
    end
  end

  describe "get_latest_successful_entry/2" do
    test "returns latest successful entry within TTL", %{test_dir: test_dir} do
      now = DateTime.utc_now()

      entries = [
        %{
          timestamp: DateTime.add(now, -10, :minute),
          filename: "error.json",
          status: :error,
          size: 512,
          content_hash: "err123",
          response_time_ms: 50,
          api_version: nil,
          cost: nil
        },
        %{
          timestamp: DateTime.add(now, -20, :minute),
          filename: "success.json",
          status: :success,
          size: 1024,
          content_hash: "abc123",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        }
      ]

      index = %{
        cache_key: "test",
        entries: entries,
        total_requests: 2,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      TestCacheIndex.save_index(test_dir, index)

      # Should skip the error entry and return the successful one
      assert {:ok, "success.json"} =
               TestCacheTTL.get_latest_successful_entry(
                 test_dir,
                 :timer.hours(1)
               )
    end

    test "returns :none when no successful entries exist", %{test_dir: test_dir} do
      now = DateTime.utc_now()

      error_entry = %{
        timestamp: DateTime.add(now, -10, :minute),
        filename: "error.json",
        status: :error,
        size: 512,
        content_hash: "err123",
        response_time_ms: 50,
        api_version: nil,
        cost: nil
      }

      index = %{
        cache_key: "test",
        entries: [error_entry],
        total_requests: 1,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      TestCacheIndex.save_index(test_dir, index)

      assert TestCacheTTL.get_latest_successful_entry(test_dir, :timer.hours(1)) == :none
    end
  end

  describe "force_refresh_for_test?/1" do
    setup do
      on_exit(fn ->
        System.delete_env("EX_LLM_TEST_CACHE_FORCE_REFRESH")
        System.delete_env("EX_LLM_TEST_CACHE_FORCE_MISS")
      end)

      :ok
    end

    test "returns false when no force refresh patterns" do
      test_context =
        {:ok,
         %{
           module: ExLLM.SomeTest,
           test_name: "test something",
           tags: [],
           pid: self()
         }}

      assert TestCacheTTL.force_refresh_for_test?(test_context) == false
    end

    test "returns true when module matches force refresh pattern" do
      System.put_env("EX_LLM_TEST_CACHE_FORCE_REFRESH", "AnthropicTest")

      test_context =
        {:ok,
         %{
           module: ExLLM.AnthropicTest,
           test_name: "test chat",
           tags: [],
           pid: self()
         }}

      assert TestCacheTTL.force_refresh_for_test?(test_context) == true
    end

    test "returns true when test name matches force miss pattern" do
      System.put_env("EX_LLM_TEST_CACHE_FORCE_MISS", "oauth")

      test_context =
        {:ok,
         %{
           module: ExLLM.SomeTest,
           test_name: "test oauth authentication",
           tags: [],
           pid: self()
         }}

      assert TestCacheTTL.force_refresh_for_test?(test_context) == true
    end

    test "handles multiple patterns separated by commas" do
      System.put_env("EX_LLM_TEST_CACHE_FORCE_REFRESH", "Anthropic,OpenAI,Gemini")

      test_context =
        {:ok,
         %{
           module: ExLLM.OpenAIIntegrationTest,
           test_name: "test embeddings",
           tags: [],
           pid: self()
         }}

      assert TestCacheTTL.force_refresh_for_test?(test_context) == true
    end

    test "returns false for error context" do
      assert TestCacheTTL.force_refresh_for_test?(:error) == false
    end
  end

  describe "calculate_ttl/2" do
    test "delegates to TestCacheConfig.get_ttl" do
      # This is a simple delegation, so we just verify it works
      tags = [:integration, :oauth2]
      provider = :gemini

      ttl = TestCacheTTL.calculate_ttl(tags, provider)
      assert is_integer(ttl) or ttl == :infinity
    end
  end

  describe "get_entries_near_expiration/2" do
    test "returns empty list for infinity TTL", %{test_dir: test_dir} do
      assert TestCacheTTL.get_entries_near_expiration(test_dir, :infinity) == []
    end

    test "identifies entries near expiration", %{test_dir: test_dir} do
      now = DateTime.utc_now()
      ttl_ms = :timer.hours(1)

      entries = [
        %{
          # 91.6% of TTL
          timestamp: DateTime.add(now, -55, :minute),
          filename: "near_expiry.json",
          status: :success,
          size: 1024,
          content_hash: "abc123",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        },
        %{
          # 50% of TTL
          timestamp: DateTime.add(now, -30, :minute),
          filename: "fresh.json",
          status: :success,
          size: 1024,
          content_hash: "def456",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        },
        %{
          # Expired
          timestamp: DateTime.add(now, -65, :minute),
          filename: "expired.json",
          status: :success,
          size: 1024,
          content_hash: "ghi789",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        }
      ]

      index = %{
        cache_key: "test",
        entries: entries,
        total_requests: 3,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      TestCacheIndex.save_index(test_dir, index)

      near_expiry = TestCacheTTL.get_entries_near_expiration(test_dir, ttl_ms)

      # Should only include the entry that's >80% through TTL but not expired
      assert length(near_expiry) == 1
      assert hd(near_expiry).filename == "near_expiry.json"
    end
  end

  describe "api_version_compatible?/2" do
    test "returns true when no version requirement" do
      entry = %{api_version: "2023-06-01"}
      assert TestCacheTTL.api_version_compatible?(entry, nil) == true
    end

    test "returns true when versions match exactly" do
      entry = %{api_version: "2023-06-01"}
      assert TestCacheTTL.api_version_compatible?(entry, "2023-06-01") == true
    end

    test "returns true when entry has no version" do
      entry = %{api_version: nil}
      assert TestCacheTTL.api_version_compatible?(entry, "2023-06-01") == true
    end

    test "checks compatibility for different versions" do
      entry = %{api_version: "2023-06-01"}

      # Same major version, compatible
      assert TestCacheTTL.api_version_compatible?(entry, "2023-05-01") == true

      # Different major version, not compatible
      assert TestCacheTTL.api_version_compatible?(entry, "2024-01-01") == false
    end
  end

  describe "get_refresh_priority/2" do
    test "returns low priority for infinity TTL" do
      entry = %{timestamp: DateTime.utc_now()}
      assert TestCacheTTL.get_refresh_priority(entry, :infinity) == :low
    end

    test "returns high priority for expired entries" do
      entry = %{timestamp: DateTime.add(DateTime.utc_now(), -2, :hour)}
      ttl_ms = :timer.hours(1)

      assert TestCacheTTL.get_refresh_priority(entry, ttl_ms) == :high
    end

    test "returns medium priority for near-expiration entries" do
      entry = %{timestamp: DateTime.add(DateTime.utc_now(), -55, :minute)}
      ttl_ms = :timer.hours(1)

      assert TestCacheTTL.get_refresh_priority(entry, ttl_ms) == :medium
    end

    test "returns low priority for fresh entries" do
      entry = %{timestamp: DateTime.add(DateTime.utc_now(), -10, :minute)}
      ttl_ms = :timer.hours(1)

      assert TestCacheTTL.get_refresh_priority(entry, ttl_ms) == :low
    end
  end

  describe "select_fallback_entry/2" do
    test "selects latest successful entry for latest_success strategy", %{test_dir: test_dir} do
      now = DateTime.utc_now()

      entries = [
        %{
          timestamp: DateTime.add(now, -1, :hour),
          filename: "error.json",
          status: :error,
          size: 512,
          content_hash: "err123",
          response_time_ms: 50,
          api_version: nil,
          cost: nil
        },
        %{
          timestamp: DateTime.add(now, -2, :hour),
          filename: "success.json",
          status: :success,
          size: 1024,
          content_hash: "abc123",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        }
      ]

      index = %{
        cache_key: "test",
        entries: entries,
        total_requests: 2,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      TestCacheIndex.save_index(test_dir, index)

      assert {:ok, "success.json"} =
               TestCacheTTL.select_fallback_entry(
                 test_dir,
                 :latest_success
               )
    end

    test "selects latest entry regardless of status for latest_any strategy", %{
      test_dir: test_dir
    } do
      now = DateTime.utc_now()

      entries = [
        %{
          timestamp: DateTime.add(now, -1, :hour),
          filename: "error.json",
          status: :error,
          size: 512,
          content_hash: "err123",
          response_time_ms: 50,
          api_version: nil,
          cost: nil
        },
        %{
          timestamp: DateTime.add(now, -2, :hour),
          filename: "success.json",
          status: :success,
          size: 1024,
          content_hash: "abc123",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        }
      ]

      index = %{
        cache_key: "test",
        entries: entries,
        total_requests: 2,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      TestCacheIndex.save_index(test_dir, index)

      assert {:ok, "error.json"} =
               TestCacheTTL.select_fallback_entry(
                 test_dir,
                 :latest_any
               )
    end

    test "returns :none for empty cache", %{test_dir: test_dir} do
      index = %{
        cache_key: "test",
        entries: [],
        total_requests: 0,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      TestCacheIndex.save_index(test_dir, index)

      assert TestCacheTTL.select_fallback_entry(test_dir, :latest_success) == :none
    end
  end
end
