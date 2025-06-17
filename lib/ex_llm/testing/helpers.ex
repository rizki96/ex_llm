defmodule ExLLM.Testing.TestCacheHelpers do
  @moduledoc """
  Test helper functions for managing and working with the automatic test cache.

  This module provides convenient functions for test suites to interact with
  the caching system, including cache warming, clearing, and debugging.
  """

  alias ExLLM.Testing.TestCacheConfig
  alias ExLLM.Testing.TestCacheStrategy
  alias ExLLM.Testing.TestCacheStats
  alias ExLLM.Testing.TestCacheDetector
  alias ExLLM.Infrastructure.Cache.Storage.TestCache
  alias ExLLM.Testing.TestCacheIndex
  alias ExLLM.Testing.TestCacheTimestamp

  @doc """
  Run a test with specific cache configuration.

  ## Examples

      with_test_cache([ttl: :timer.hours(1)], fn ->
        # Your test code here
      end)
  """
  def with_test_cache(opts \\ [], func) when is_function(func) do
    original_config = TestCacheConfig.get_config()

    # Apply temporary config
    temp_config = Keyword.merge([enabled: true], opts)
    Application.put_env(:ex_llm, :test_cache, temp_config)

    try do
      func.()
    after
      # Restore original config
      Application.put_env(:ex_llm, :test_cache, original_config)
    end
  end

  @doc """
  Clear test cache with different scopes.

  ## Examples

      # Clear all cache
      clear_test_cache(:all)
      
      # Clear specific provider
      clear_test_cache("anthropic")
      
      # Clear specific test module
      clear_test_cache("AnthropicIntegrationTest")
  """
  def clear_test_cache(scope \\ :all) do
    TestCache.clear(scope)
  end

  @doc """
  Warm test cache for specific test modules or patterns.

  This pre-loads cache entries that might be expiring soon.
  """
  def warm_test_cache(test_module) when is_atom(test_module) do
    cache_pattern = "#{test_module}/*"
    TestCacheStrategy.warm_cache([cache_pattern])
  end

  def warm_test_cache(patterns) when is_list(patterns) do
    TestCacheStrategy.warm_cache(patterns)
  end

  @doc """
  Verify cache integrity and check for issues.
  """
  def verify_cache_integrity do
    cache_keys = TestCache.list_cache_keys()

    issues =
      Enum.flat_map(cache_keys, fn cache_key ->
        verify_cache_key_integrity(cache_key)
      end)

    case issues do
      [] ->
        IO.puts("✅ Cache integrity check passed!")
        :ok

      issues ->
        IO.puts("❌ Cache integrity issues found:")
        Enum.each(issues, &IO.puts("  - #{&1}"))
        {:error, issues}
    end
  end

  @doc """
  Force cache miss for specific patterns.

  Useful for testing real API calls without disabling cache entirely.
  """
  def force_cache_miss(pattern) do
    Process.put(:ex_llm_force_cache_miss, pattern)
    :ok
  end

  @doc """
  Force cache refresh for specific patterns.

  Ignores TTL and forces fresh API calls.
  """
  def force_cache_refresh(pattern) do
    Process.put(:ex_llm_force_cache_refresh, pattern)
    :ok
  end

  @doc """
  Set custom TTL for specific test patterns.
  """
  def set_test_ttl(test_pattern, ttl) do
    Process.put({:ex_llm_test_ttl, test_pattern}, ttl)
    :ok
  end

  @doc """
  List all cache timestamps for a pattern.

  ## Examples

      list_cache_timestamps("anthropic/chat_basic")
  """
  def list_cache_timestamps(cache_pattern) do
    config = TestCacheConfig.get_config()
    cache_dir = Path.join(config.cache_dir, cache_pattern)

    case File.exists?(cache_dir) do
      true ->
        timestamps = TestCacheTimestamp.list_cache_timestamps(cache_dir)

        IO.puts("\nCache timestamps for #{cache_pattern}:")

        Enum.each(timestamps, fn timestamp ->
          age_days = DateTime.diff(DateTime.utc_now(), timestamp, :day)
          IO.puts("  #{DateTime.to_iso8601(timestamp)} (#{age_days} days ago)")
        end)

        timestamps

      false ->
        IO.puts("No cache found for pattern: #{cache_pattern}")
        []
    end
  end

  @doc """
  Restore cache from a specific timestamp.

  Useful for debugging or testing with older responses.
  """
  def restore_cache_timestamp(cache_pattern, timestamp) do
    config = TestCacheConfig.get_config()
    cache_dir = Path.join(config.cache_dir, cache_pattern)

    filename =
      case timestamp do
        %DateTime{} = dt -> TestCacheTimestamp.generate_timestamp_filename(dt)
        str when is_binary(str) -> str
      end

    file_path = Path.join(cache_dir, filename)

    case File.exists?(file_path) do
      true ->
        IO.puts("✅ Restored cache from #{filename}")
        Process.put({:ex_llm_force_cache_file, cache_pattern}, filename)
        :ok

      false ->
        IO.puts("❌ Cache file not found: #{file_path}")
        {:error, :not_found}
    end
  end

  @doc """
  Clean up old cache timestamps.
  """
  def cleanup_old_timestamps(max_age \\ 30 * 24 * 60 * 60 * 1000) do
    config = TestCacheConfig.get_config()

    cleanup_report =
      TestCache.list_cache_keys()
      |> Enum.map(fn cache_key ->
        cache_dir = Path.join(config.cache_dir, cache_key)
        TestCacheTimestamp.cleanup_old_entries(cache_dir, 0, max_age)
      end)
      |> Enum.reduce(%{deleted_files: 0, freed_bytes: 0, errors: []}, fn report, acc ->
        %{
          deleted_files: acc.deleted_files + report.deleted_files,
          freed_bytes: acc.freed_bytes + report.freed_bytes,
          errors: acc.errors ++ report.errors
        }
      end)

    IO.puts("\nCache cleanup complete:")
    IO.puts("  Files deleted: #{cleanup_report.deleted_files}")
    IO.puts("  Space freed: #{format_bytes(cleanup_report.freed_bytes)}")

    if length(cleanup_report.errors) > 0 do
      IO.puts("  Errors: #{length(cleanup_report.errors)}")
    end

    cleanup_report
  end

  @doc """
  Deduplicate cache content to save space.
  """
  def deduplicate_cache_content(cache_pattern \\ :all) do
    cache_keys =
      case cache_pattern do
        :all -> TestCache.list_cache_keys()
        pattern -> [pattern]
      end

    config = TestCacheConfig.get_config()

    dedup_report =
      Enum.map(cache_keys, fn cache_key ->
        cache_dir = Path.join(config.cache_dir, cache_key)
        TestCacheTimestamp.deduplicate_content(cache_dir)
      end)
      |> Enum.reduce(
        %{duplicates_found: 0, space_saved: 0, symlinks_created: 0, errors: []},
        fn report, acc ->
          %{
            duplicates_found: acc.duplicates_found + report.duplicates_found,
            space_saved: acc.space_saved + report.space_saved,
            symlinks_created: acc.symlinks_created + report.symlinks_created,
            errors: acc.errors ++ report.errors
          }
        end
      )

    IO.puts("\nCache deduplication complete:")
    IO.puts("  Duplicates found: #{dedup_report.duplicates_found}")
    IO.puts("  Space saved: #{format_bytes(dedup_report.space_saved)}")
    IO.puts("  Symlinks created: #{dedup_report.symlinks_created}")

    dedup_report
  end

  @doc """
  Get cache statistics for specific test module.
  """
  def get_cache_stats(test_module \\ :all) do
    case test_module do
      :all -> TestCacheStats.get_global_stats()
      module -> TestCacheStats.get_cache_key_stats("#{module}")
    end
  end

  @doc """
  Set fallback strategy for specific test patterns.
  """
  def set_fallback_strategy(test_pattern, strategy)
      when strategy in [:latest_success, :latest_any, :best_match] do
    Process.put({:ex_llm_fallback_strategy, test_pattern}, strategy)
    :ok
  end

  @doc """
  Print cache statistics summary.
  """
  def print_cache_summary do
    TestCacheStats.print_cache_summary()
  end

  @doc """
  Print cache statistics by provider.
  """
  def print_provider_stats do
    TestCacheStats.print_provider_stats()
  end

  @doc """
  Enable debug logging for cache operations.
  """
  def enable_cache_debug do
    Application.put_env(:ex_llm, :debug_test_cache, true)
    IO.puts("Test cache debug logging enabled")
    :ok
  end

  @doc """
  Disable debug logging for cache operations.
  """
  def disable_cache_debug do
    Application.put_env(:ex_llm, :debug_test_cache, false)
    IO.puts("Test cache debug logging disabled")
    :ok
  end

  @doc """
  Setup hook for test modules to initialize caching.

  ## Usage in test module:

      setup do
        ExLLM.Testing.TestCacheHelpers.setup_test_cache()
      end
  """
  def setup_test_cache(context \\ %{}) do
    # Extract tags from context
    tags =
      context
      |> Map.drop([
        :async,
        :line,
        :module,
        :registered,
        :file,
        :test,
        :describe_line,
        :describe,
        :test_type,
        :test_pid
      ])
      |> Map.keys()

    # Set test context in process
    test_context = %{
      module: Map.get(context, :module, __MODULE__),
      tags: tags,
      test_name: Map.get(context, :test, "unknown") |> to_string(),
      pid: self()
    }

    TestCacheDetector.set_test_context(test_context)

    # Note: The calling test should use on_exit to clear context
    # on_exit(fn ->
    #   TestCacheDetector.clear_test_context()
    # end)

    :ok
  end

  # Private helpers

  defp verify_cache_key_integrity(cache_key) do
    config = TestCacheConfig.get_config()
    cache_dir = Path.join(config.cache_dir, cache_key)

    case File.exists?(cache_dir) do
      true ->
        index = TestCacheIndex.load_index(cache_dir)

        # Check each entry in index exists
        missing_files =
          Enum.filter(index.entries, fn entry ->
            file_path = Path.join(cache_dir, entry.filename)
            not File.exists?(file_path)
          end)

        case missing_files do
          [] -> []
          files -> ["#{cache_key}: #{length(files)} missing files"]
        end

      false ->
        []
    end
  end

  defp format_bytes(bytes) when is_number(bytes) do
    cond do
      bytes < 1024 ->
        "#{bytes}B"

      bytes < 1024 * 1024 ->
        "#{:erlang.float_to_binary(bytes / 1024, decimals: 1)}KB"

      bytes < 1024 * 1024 * 1024 ->
        "#{:erlang.float_to_binary(bytes / (1024 * 1024), decimals: 1)}MB"

      true ->
        "#{:erlang.float_to_binary(bytes / (1024 * 1024 * 1024), decimals: 1)}GB"
    end
  end

  defp format_bytes(_), do: "0B"
end
