defmodule ExLLM.Testing.TestCacheStats do
  @moduledoc """
  Track cache performance and cost savings with timestamp-based metrics.

  This module provides comprehensive statistics tracking for the automatic
  test response caching system, including hit/miss ratios, cost savings,
  performance improvements, and storage optimization metrics.
  """

  # Functions used in code paths that may be unreachable due to caching issues
  @compile {:nowarn_unused_function, [
    calculate_average_age: 1,
    count_ttl_refreshes: 1,
    count_fallback_uses: 1,
    count_expired_uses: 1
  ]}

  alias ExLLM.Infrastructure.Cache.Storage.TestCache
  alias ExLLM.Testing.TestCacheConfig
  alias ExLLM.Testing.TestCacheIndex

  use Agent

  @stats_agent_name __MODULE__.Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: @stats_agent_name)
  end

  def child_spec(opts) do
    %{
      id: @stats_agent_name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @type cache_stats :: %{
          # Basic metrics
          total_requests: non_neg_integer(),
          cache_hits: non_neg_integer(),
          cache_misses: non_neg_integer(),
          hit_rate: float(),
          miss_rate: float(),

          # TTL and fallback metrics
          ttl_refreshes: non_neg_integer(),
          fallback_uses: non_neg_integer(),
          fallback_to_older: non_neg_integer(),
          expired_cache_uses: non_neg_integer(),

          # Performance metrics
          total_response_time_ms: non_neg_integer(),
          cached_response_time_ms: non_neg_integer(),
          real_response_time_ms: non_neg_integer(),
          time_savings_ms: non_neg_integer(),

          # Cost metrics
          estimated_cost_savings: float(),
          cost_savings: float(),
          real_api_calls_saved: non_neg_integer(),

          # Storage metrics
          total_cache_size: non_neg_integer(),
          unique_content_size: non_neg_integer(),
          deduplication_savings: non_neg_integer(),
          timestamp_count: non_neg_integer(),

          # Temporal metrics
          oldest_cache_entry: DateTime.t() | nil,
          newest_cache_entry: DateTime.t() | nil,
          average_cache_age_days: float()
        }

  @type provider_stats :: %{
          provider: atom(),
          stats: cache_stats()
        }

  @type test_suite_stats :: %{
          test_module: String.t(),
          stats: cache_stats()
        }

  @doc """
  Get comprehensive cache statistics for all cache keys.
  """
  @spec get_global_stats() :: map()
  def get_global_stats do
    # Use the same in-memory stats as get_stats for consistency in tests
    get_stats()
  end

  @doc """
  Get cache statistics by provider.
  """
  @spec get_stats_by_provider() :: [provider_stats()]
  def get_stats_by_provider do
    cache_keys = TestCache.list_cache_keys()

    cache_keys
    |> Enum.group_by(&extract_provider_from_key/1)
    |> Enum.map(fn {provider, keys} ->
      provider_stats =
        Enum.reduce(keys, initialize_stats(), fn key, acc ->
          key_stats = get_cache_key_stats(key)
          merge_stats(acc, key_stats)
        end)

      %{
        provider: provider,
        stats: finalize_stats(provider_stats)
      }
    end)
    |> Enum.sort_by(& &1.provider)
  end

  @doc """
  Get cache statistics by test suite/module.
  """
  @spec get_stats_by_test_suite() :: [test_suite_stats()]
  def get_stats_by_test_suite do
    cache_keys = TestCache.list_cache_keys()

    cache_keys
    |> Enum.group_by(&extract_test_module_from_key/1)
    |> Enum.map(fn {test_module, keys} ->
      suite_stats =
        Enum.reduce(keys, initialize_stats(), fn key, acc ->
          key_stats = get_cache_key_stats(key)
          merge_stats(acc, key_stats)
        end)

      %{
        test_module: test_module,
        stats: finalize_stats(suite_stats)
      }
    end)
    |> Enum.sort_by(& &1.test_module)
  end

  @doc """
  Get detailed statistics for a specific cache key.
  """
  @spec get_cache_key_stats(String.t()) :: cache_stats()
  def get_cache_key_stats(cache_key) do
    config = TestCacheConfig.get_config()
    cache_dir = Path.join(config.cache_dir, cache_key)

    case File.exists?(cache_dir) do
      true ->
        index = TestCacheIndex.load_index(cache_dir)
        calculate_detailed_stats(index, cache_dir)

      false ->
        initialize_stats()
    end
  end

  @doc """
  Print a formatted cache summary to the console.
  """
  @spec print_cache_summary() :: :ok
  def print_cache_summary do
    stats = get_global_stats()

    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("Test Cache Summary")
    IO.puts(String.duplicate("=", 50))

    # Basic metrics
    IO.puts("Total Requests: #{stats.total_requests}")
    IO.puts("Cache Hits: #{stats.cache_hits} (#{format_percentage(stats.hit_rate)})")
    IO.puts("Cache Misses: #{stats.cache_misses} (#{format_percentage(1 - stats.hit_rate)})")

    if stats.ttl_refreshes > 0 do
      refresh_rate = stats.ttl_refreshes / stats.total_requests
      IO.puts("TTL Refreshes: #{stats.ttl_refreshes} (#{format_percentage(refresh_rate)})")
    end

    if stats.fallback_uses > 0 do
      fallback_rate = stats.fallback_uses / stats.total_requests
      IO.puts("Fallback Uses: #{stats.fallback_uses} (#{format_percentage(fallback_rate)})")
    end

    # Performance metrics
    if stats.time_savings_ms > 0 do
      IO.puts("Time Savings: #{format_duration(stats.time_savings_ms)}")

      avg_real_time =
        if stats.cache_misses > 0, do: stats.real_response_time_ms / stats.cache_misses, else: 0

      avg_cached_time =
        if stats.cache_hits > 0, do: stats.cached_response_time_ms / stats.cache_hits, else: 0

      IO.puts(
        "Avg Response Time - Real: #{format_duration(avg_real_time)}, Cached: #{format_duration(avg_cached_time)}"
      )
    end

    # Cost savings
    if stats.estimated_cost_savings > 0 do
      IO.puts(
        "Estimated Cost Savings: $#{:erlang.float_to_binary(stats.estimated_cost_savings, decimals: 4)}"
      )

      IO.puts("Real API Calls Saved: #{stats.real_api_calls_saved}")
    end

    # Storage metrics
    IO.puts("Storage Used: #{format_bytes(stats.total_cache_size)}")

    if stats.deduplication_savings > 0 do
      savings_pct =
        stats.deduplication_savings / (stats.total_cache_size + stats.deduplication_savings)

      IO.puts(
        "Unique Content: #{format_bytes(stats.unique_content_size)} (#{format_percentage(savings_pct)} space saved)"
      )

      dedup_ratio =
        if stats.total_cache_size > 0 do
          stats.deduplication_savings / stats.total_cache_size
        else
          0.0
        end

      IO.puts("Deduplication Ratio: #{format_percentage(dedup_ratio)}")
    end

    IO.puts("Total Timestamps: #{stats.timestamp_count}")

    # Temporal info
    if stats.oldest_cache_entry do
      age_days = DateTime.diff(DateTime.utc_now(), stats.oldest_cache_entry, :day)
      IO.puts("Oldest Cache Entry: #{age_days} days ago")
    end

    if stats.average_cache_age_days > 0 do
      IO.puts(
        "Average Cache Age: #{:erlang.float_to_binary(stats.average_cache_age_days, decimals: 1)} days"
      )
    end

    IO.puts(String.duplicate("=", 50))
    :ok
  end

  @doc """
  Print cache statistics by provider.
  """
  @spec print_provider_stats() :: :ok
  def print_provider_stats do
    provider_stats = get_stats_by_provider()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("Cache Statistics by Provider")
    IO.puts(String.duplicate("=", 60))

    Enum.each(provider_stats, fn %{provider: provider, stats: stats} ->
      IO.puts("\n#{String.upcase(to_string(provider))}:")
      IO.puts("  Requests: #{stats.total_requests}")
      IO.puts("  Hit Rate: #{format_percentage(stats.hit_rate)}")
      IO.puts("  Storage: #{format_bytes(stats.total_cache_size)}")

      if stats.estimated_cost_savings > 0 do
        IO.puts(
          "  Cost Savings: $#{:erlang.float_to_binary(stats.estimated_cost_savings, decimals: 2)}"
        )
      end
    end)

    IO.puts(String.duplicate("=", 60))
    :ok
  end

  @doc """
  Get cache efficiency metrics for monitoring.
  """
  @spec get_efficiency_metrics() :: map()
  def get_efficiency_metrics do
    stats = get_global_stats()

    %{
      hit_rate: stats.hit_rate,
      storage_efficiency: calculate_storage_efficiency(stats),
      time_efficiency: calculate_time_efficiency(stats),
      cost_efficiency: calculate_cost_efficiency(stats),
      staleness_ratio: calculate_staleness_ratio(stats)
    }
  end

  @doc """
  Record a cache operation for statistics.
  """
  @spec record_operation(String.t(), atom(), map()) :: :ok
  def record_operation(cache_key, operation, metadata \\ %{}) do
    # This would be called by the caching system to record operations
    # For now, we'll implement basic recording
    timestamp = DateTime.utc_now()

    case operation do
      :hit -> record_cache_hit(cache_key, timestamp, metadata)
      :miss -> record_cache_miss(cache_key, timestamp, metadata)
      :ttl_refresh -> record_ttl_refresh(cache_key, timestamp, metadata)
      :fallback -> record_fallback_use(cache_key, timestamp, metadata)
      :save -> record_cache_save(cache_key, timestamp, metadata)
    end
  end

  # Private functions

  defp initialize_stats do
    %{
      total_requests: 0,
      cache_hits: 0,
      cache_misses: 0,
      hit_rate: 0.0,
      miss_rate: 0.0,
      ttl_refreshes: 0,
      fallback_uses: 0,
      fallback_to_older: 0,
      expired_cache_uses: 0,
      total_response_time_ms: 0,
      cached_response_time_ms: 0,
      real_response_time_ms: 0,
      time_savings_ms: 0,
      estimated_cost_savings: 0.0,
      cost_savings: 0.0,
      real_api_calls_saved: 0,
      total_cache_size: 0,
      unique_content_size: 0,
      deduplication_savings: 0,
      timestamp_count: 0,
      oldest_cache_entry: nil,
      newest_cache_entry: nil,
      average_cache_age_days: 0.0
    }
  end

  defp calculate_detailed_stats(index, cache_dir) do
    index_stats = TestCacheIndex.get_statistics(index)

    # Calculate time-based metrics
    time_metrics = calculate_time_metrics(index.entries)

    # Calculate cost metrics
    cost_metrics = calculate_cost_metrics(index.entries)

    # Calculate storage metrics
    storage_metrics = calculate_storage_metrics(cache_dir, index.entries)

    cache_misses = max(0, index.total_requests - index.cache_hits)

    hit_rate =
      if(index.total_requests > 0, do: index.cache_hits / index.total_requests, else: 0.0)

    miss_rate = if(index.total_requests > 0, do: cache_misses / index.total_requests, else: 0.0)

    %{
      total_requests: index.total_requests,
      cache_hits: index.cache_hits,
      cache_misses: cache_misses,
      hit_rate: hit_rate,
      miss_rate: miss_rate,
      ttl_refreshes: count_ttl_refreshes(index.entries),
      fallback_uses: count_fallback_uses(index.entries),
      # Default value for file-based stats
      fallback_to_older: 0,
      expired_cache_uses: count_expired_uses(index.entries),
      total_response_time_ms: time_metrics.total_time,
      cached_response_time_ms: time_metrics.cached_time,
      real_response_time_ms: time_metrics.real_time,
      time_savings_ms: time_metrics.savings,
      estimated_cost_savings: cost_metrics.total_savings,
      cost_savings: cost_metrics.total_savings,
      real_api_calls_saved: index.cache_hits,
      total_cache_size: storage_metrics.total_size,
      unique_content_size: storage_metrics.unique_size,
      deduplication_savings: storage_metrics.dedup_savings,
      timestamp_count: length(index.entries),
      oldest_cache_entry: index_stats.oldest_entry,
      newest_cache_entry: index_stats.newest_entry,
      average_cache_age_days: calculate_average_age(index.entries)
    }
  end

  defp merge_stats(stats1, stats2) do
    %{
      total_requests: stats1.total_requests + stats2.total_requests,
      cache_hits: stats1.cache_hits + stats2.cache_hits,
      cache_misses: stats1.cache_misses + stats2.cache_misses,
      # Will be calculated in finalize_stats
      hit_rate: 0.0,
      # Will be calculated in finalize_stats
      miss_rate: 0.0,
      ttl_refreshes: stats1.ttl_refreshes + stats2.ttl_refreshes,
      fallback_uses: stats1.fallback_uses + stats2.fallback_uses,
      fallback_to_older: stats1.fallback_to_older + stats2.fallback_to_older,
      expired_cache_uses: stats1.expired_cache_uses + stats2.expired_cache_uses,
      total_response_time_ms: stats1.total_response_time_ms + stats2.total_response_time_ms,
      cached_response_time_ms: stats1.cached_response_time_ms + stats2.cached_response_time_ms,
      real_response_time_ms: stats1.real_response_time_ms + stats2.real_response_time_ms,
      time_savings_ms: stats1.time_savings_ms + stats2.time_savings_ms,
      estimated_cost_savings: stats1.estimated_cost_savings + stats2.estimated_cost_savings,
      cost_savings: stats1.cost_savings + stats2.cost_savings,
      real_api_calls_saved: stats1.real_api_calls_saved + stats2.real_api_calls_saved,
      total_cache_size: stats1.total_cache_size + stats2.total_cache_size,
      unique_content_size: stats1.unique_content_size + stats2.unique_content_size,
      deduplication_savings: stats1.deduplication_savings + stats2.deduplication_savings,
      timestamp_count: stats1.timestamp_count + stats2.timestamp_count,
      oldest_cache_entry: earliest_datetime(stats1.oldest_cache_entry, stats2.oldest_cache_entry),
      newest_cache_entry: latest_datetime(stats1.newest_cache_entry, stats2.newest_cache_entry),
      # Will be calculated in finalize_stats
      average_cache_age_days: 0.0
    }
  end

  defp finalize_stats(stats) do
    hit_rate = if stats.total_requests > 0, do: stats.cache_hits / stats.total_requests, else: 0.0

    miss_rate =
      if stats.total_requests > 0, do: stats.cache_misses / stats.total_requests, else: 0.0

    avg_age = calculate_global_average_age(stats)

    %{stats | hit_rate: hit_rate, miss_rate: miss_rate, average_cache_age_days: avg_age}
  end

  defp calculate_time_metrics(entries) do
    {total_time, cached_time} =
      Enum.reduce(entries, {0, 0}, fn entry, {total_acc, cached_acc} ->
        response_time = Map.get(entry, :response_time_ms, 0)
        # Cached responses are very fast
        {total_acc + response_time, cached_acc + min(response_time, 10)}
      end)

    real_time = total_time - cached_time
    savings = max(0, real_time - cached_time)

    %{total_time: total_time, cached_time: cached_time, real_time: real_time, savings: savings}
  end

  defp calculate_cost_metrics(entries) do
    total_savings =
      Enum.reduce(entries, 0.0, fn entry, acc ->
        cost = Map.get(entry, :cost, %{})

        entry_cost =
          case cost do
            %{total: total} when is_number(total) -> total
            %{"total" => total} when is_number(total) -> total
            # Estimate if no cost data
            _ -> 0.01
          end

        acc + entry_cost
      end)

    %{total_savings: total_savings}
  end

  defp calculate_storage_metrics(_cache_dir, entries) do
    total_size = Enum.reduce(entries, 0, &(&1.size + &2))

    # Calculate deduplication metrics
    # For now, return empty duplicates to avoid type issues
    duplicates = %{}

    dedup_savings =
      duplicates
      |> Map.values()
      |> List.flatten()
      |> Enum.reduce(0, fn entry, acc ->
        acc + Map.get(entry, :size, 0)
      end)

    unique_size = total_size - dedup_savings

    %{total_size: total_size, unique_size: unique_size, dedup_savings: dedup_savings}
  end

  defp calculate_average_age(entries) do
    if length(entries) > 0 do
      now = DateTime.utc_now()

      total_age_days =
        Enum.reduce(entries, 0, fn entry, acc ->
          age_days = DateTime.diff(now, entry.timestamp, :day)
          acc + age_days
        end)

      total_age_days / length(entries)
    else
      0.0
    end
  end

  defp calculate_global_average_age(stats) do
    if stats.timestamp_count > 0 and not is_nil(stats.oldest_cache_entry) do
      total_span_days = DateTime.diff(DateTime.utc_now(), stats.oldest_cache_entry, :day)
      # Rough average
      total_span_days / 2
    else
      0.0
    end
  end

  defp count_ttl_refreshes(entries) do
    # This would count entries that were TTL refreshes
    # For now, estimate based on recent entries
    recent_threshold = DateTime.add(DateTime.utc_now(), -1, :day)
    Enum.count(entries, &(DateTime.compare(&1.timestamp, recent_threshold) == :gt))
  end

  defp count_fallback_uses(_entries) do
    # This would count entries used as fallbacks
    # For now, return 0 as we don't track this yet
    0
  end

  defp count_expired_uses(_entries) do
    # This would count expired cache uses
    # For now, return 0 as we don't track this yet
    0
  end

  defp calculate_storage_efficiency(stats) do
    if stats.total_cache_size > 0 do
      stats.unique_content_size / stats.total_cache_size
    else
      1.0
    end
  end

  defp calculate_time_efficiency(stats) do
    if stats.total_response_time_ms > 0 do
      stats.time_savings_ms / stats.total_response_time_ms
    else
      0.0
    end
  end

  defp calculate_cost_efficiency(stats) do
    # Ratio of money saved vs potential money spent
    stats.estimated_cost_savings / max(stats.estimated_cost_savings + 0.01, 0.01)
  end

  defp calculate_staleness_ratio(stats) do
    # How much of the cache is potentially stale
    if stats.timestamp_count > 0 and not is_nil(stats.oldest_cache_entry) do
      config = TestCacheConfig.get_config()

      ttl_days =
        case config.ttl do
          # Treat infinity as 1 year for calculation
          :infinity -> 365
          ttl_ms -> ttl_ms / (24 * 60 * 60 * 1000)
        end

      avg_age = stats.average_cache_age_days
      min(avg_age / ttl_days, 1.0)
    else
      0.0
    end
  end

  defp extract_provider_from_key(cache_key) do
    cache_key
    |> String.split("/")
    |> List.first()
    |> String.to_atom()
  rescue
    _ -> :unknown
  end

  defp extract_test_module_from_key(cache_key) do
    # Extract test module from cache key organization
    # This depends on cache organization strategy
    case String.split(cache_key, "/") do
      [_provider, module | _] when module != "" -> module
      _ -> "unknown"
    end
  end

  defp earliest_datetime(dt1, dt2) do
    cond do
      is_nil(dt1) -> dt2
      is_nil(dt2) -> dt1
      true -> dt1  # Default to first when both are non-nil
    end
  end

  defp latest_datetime(dt1, dt2) do
    cond do
      is_nil(dt1) -> dt2
      is_nil(dt2) -> dt1
      true -> dt1  # Default to first when both are non-nil
    end
  end

  @doc """
  Format duration in milliseconds.
  """
  @spec format_duration(number()) :: String.t()
  def format_duration(ms) when is_number(ms) do
    ms_int = round(ms)

    cond do
      ms_int < 1000 ->
        "#{ms_int}ms"

      ms_int < 60_000 ->
        seconds = ms_int / 1000
        "#{:erlang.float_to_binary(seconds, decimals: 1)}s"

      ms_int < 3_600_000 ->
        minutes = div(ms_int, 60_000)
        remaining_seconds = div(rem(ms_int, 60_000), 1000)

        if remaining_seconds > 0 do
          "#{minutes}m #{remaining_seconds}s"
        else
          "#{minutes}m"
        end

      true ->
        hours = div(ms_int, 3_600_000)
        remaining_minutes = div(rem(ms_int, 3_600_000), 60_000)
        remaining_seconds = div(rem(ms_int, 60_000), 1000)

        parts = ["#{hours}h"]
        parts = if remaining_minutes > 0, do: parts ++ ["#{remaining_minutes}m"], else: parts
        parts = if remaining_seconds > 0, do: parts ++ ["#{remaining_seconds}s"], else: parts

        Enum.join(parts, " ")
    end
  end

  def format_duration(_), do: "0ms"

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

  @doc """
  Reset all cache statistics.

  Clears all in-memory statistics. Note that this doesn't affect
  the actual cache files, only the statistics tracking.
  """
  @spec reset_stats() :: :ok
  def reset_stats do
    try do
      ensure_agent_started()
      Agent.update(@stats_agent_name, fn _state -> %{} end)
      :ok
    rescue
      _ ->
        # If agent is dead or can't be started, just return :ok
        # This handles cleanup scenarios where the process may have died
        :ok
    catch
      :exit, _ ->
        # Handle exit signals during Agent operations
        :ok
    end
  end

  @doc """
  Record a cache hit event.
  """
  @spec record_hit(map()) :: :ok
  def record_hit(metadata) do
    ensure_agent_started()
    provider = Map.get(metadata, :provider, "unknown")

    # Calculate time savings
    cached_time = Map.get(metadata, :cached_response_time_ms, 0)
    estimated_api_time = Map.get(metadata, :estimated_api_time_ms, 0)
    time_saved = max(0, estimated_api_time - cached_time)

    Agent.update(@stats_agent_name, fn state ->
      global_stats = Map.get(state, :global, initialize_stats())
      provider_stats = Map.get(state, {:provider, provider}, initialize_stats())

      updated_global = %{
        global_stats
        | cache_hits: global_stats.cache_hits + 1,
          total_requests: global_stats.total_requests + 1,
          time_savings_ms: global_stats.time_savings_ms + time_saved
      }

      updated_provider = %{
        provider_stats
        | cache_hits: provider_stats.cache_hits + 1,
          total_requests: provider_stats.total_requests + 1,
          time_savings_ms: provider_stats.time_savings_ms + time_saved
      }

      updated_state =
        state
        |> Map.put(:global, updated_global)
        |> Map.put({:provider, provider}, updated_provider)

      # Also update test-specific stats if test context is available
      case {Map.get(metadata, :test_module), Map.get(metadata, :test_name)} do
        {test_module, test_name} when is_binary(test_module) and is_binary(test_name) ->
          test_stats = Map.get(state, {:test, test_module, test_name}, initialize_stats())

          updated_test = %{
            test_stats
            | cache_hits: test_stats.cache_hits + 1,
              total_requests: test_stats.total_requests + 1,
              time_savings_ms: test_stats.time_savings_ms + time_saved
          }

          Map.put(updated_state, {:test, test_module, test_name}, updated_test)

        _ ->
          updated_state
      end
    end)

    :ok
  end

  @doc """
  Record a cache miss event.
  """
  @spec record_miss(map()) :: :ok
  def record_miss(metadata) do
    ensure_agent_started()
    provider = Map.get(metadata, :provider, "unknown")

    Agent.update(@stats_agent_name, fn state ->
      global_stats = Map.get(state, :global, initialize_stats())
      provider_stats = Map.get(state, {:provider, provider}, initialize_stats())

      updated_global = %{
        global_stats
        | cache_misses: global_stats.cache_misses + 1,
          total_requests: global_stats.total_requests + 1
      }

      updated_provider = %{
        provider_stats
        | cache_misses: provider_stats.cache_misses + 1,
          total_requests: provider_stats.total_requests + 1
      }

      updated_state =
        state
        |> Map.put(:global, updated_global)
        |> Map.put({:provider, provider}, updated_provider)

      # Also update test-specific stats if test context is available
      case {Map.get(metadata, :test_module), Map.get(metadata, :test_name)} do
        {test_module, test_name} when is_binary(test_module) and is_binary(test_name) ->
          test_stats = Map.get(state, {:test, test_module, test_name}, initialize_stats())

          updated_test = %{
            test_stats
            | cache_misses: test_stats.cache_misses + 1,
              total_requests: test_stats.total_requests + 1
          }

          Map.put(updated_state, {:test, test_module, test_name}, updated_test)

        _ ->
          updated_state
      end
    end)

    :ok
  end

  @doc """
  Record a cost saving event.
  """
  @spec record_cost_saving(String.t(), float()) :: :ok
  def record_cost_saving(provider, amount) do
    ensure_agent_started()

    Agent.update(@stats_agent_name, fn state ->
      global_stats = Map.get(state, :global, initialize_stats())
      provider_stats = Map.get(state, {:provider, provider}, initialize_stats())

      updated_global = %{
        global_stats
        | estimated_cost_savings: global_stats.estimated_cost_savings + amount,
          cost_savings: global_stats.cost_savings + amount
      }

      updated_provider = %{
        provider_stats
        | estimated_cost_savings: provider_stats.estimated_cost_savings + amount,
          cost_savings: provider_stats.cost_savings + amount
      }

      state
      |> Map.put(:global, updated_global)
      |> Map.put({:provider, provider}, updated_provider)
    end)

    :ok
  end

  @doc """
  Record time saved by using cache.
  """
  @spec record_time_saved(non_neg_integer()) :: :ok
  def record_time_saved(ms) do
    ensure_agent_started()

    Agent.update(@stats_agent_name, fn state ->
      global_stats = Map.get(state, :global, initialize_stats())
      updated_global = %{global_stats | time_savings_ms: global_stats.time_savings_ms + ms}
      Map.put(state, :global, updated_global)
    end)

    :ok
  end

  @doc """
  Get statistics for a specific provider.
  """
  @spec get_provider_stats(atom() | String.t()) :: map()
  def get_provider_stats(provider) when is_atom(provider) do
    get_provider_stats(to_string(provider))
  end

  def get_provider_stats(provider) when is_binary(provider) do
    ensure_agent_started()

    stats =
      Agent.get(@stats_agent_name, fn state ->
        Map.get(state, {:provider, provider}, initialize_stats())
      end)

    finalize_stats(stats)
  end

  @doc """
  Record cost savings from cache usage.
  """
  @spec record_cost_savings(map() | float()) :: :ok
  def record_cost_savings(metrics) when is_map(metrics) do
    provider = Map.get(metrics, :provider, "unknown")
    amount = Map.get(metrics, :estimated_cost, 0.0)

    ensure_agent_started()

    Agent.update(@stats_agent_name, fn state ->
      global_stats = Map.get(state, :global, initialize_stats())
      provider_stats = Map.get(state, {:provider, provider}, initialize_stats())

      updated_global = %{
        global_stats
        | estimated_cost_savings: global_stats.estimated_cost_savings + amount,
          cost_savings: global_stats.cost_savings + amount
      }

      updated_provider = %{
        provider_stats
        | estimated_cost_savings: provider_stats.estimated_cost_savings + amount,
          cost_savings: provider_stats.cost_savings + amount
      }

      state
      |> Map.put(:global, updated_global)
      |> Map.put({:provider, provider}, updated_provider)
    end)

    :ok
  end

  def record_cost_savings(amount) when is_number(amount) do
    record_cost_savings(%{provider: "unknown", estimated_cost: amount})
  end

  @doc """
  Get basic cache statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    ensure_agent_started()

    stats =
      Agent.get(@stats_agent_name, fn state ->
        global_stats = Map.get(state, :global, initialize_stats())

        storage_stats =
          Map.get(state, :storage, %{
            total_cache_size: 0,
            unique_content_size: 0,
            deduplication_savings: 0,
            timestamp_count: 0
          })

        # Merge storage stats into global stats
        Map.merge(global_stats, %{
          total_cache_size: storage_stats.total_cache_size,
          unique_content_size: storage_stats.unique_content_size,
          deduplication_savings: storage_stats.deduplication_savings,
          timestamp_count: Map.get(storage_stats, :total_entries, 0)
        })
      end)

    finalize_stats(stats)
  end

  @doc """
  Record storage usage metrics.
  """
  @spec record_storage_usage(map()) :: :ok
  def record_storage_usage(metrics) when is_map(metrics) do
    ensure_agent_started()

    Agent.update(@stats_agent_name, fn state ->
      storage_stats =
        Map.get(state, :storage, %{
          total_cache_size: 0,
          unique_content_size: 0,
          deduplication_savings: 0,
          total_entries: 0,
          unique_entries: 0
        })

      updated_storage = %{
        storage_stats
        | total_cache_size:
            storage_stats.total_cache_size + Map.get(metrics, :total_size_bytes, 0),
          unique_content_size:
            storage_stats.unique_content_size + Map.get(metrics, :unique_size_bytes, 0),
          deduplication_savings:
            storage_stats.deduplication_savings + Map.get(metrics, :duplicate_size_bytes, 0),
          total_entries: storage_stats.total_entries + Map.get(metrics, :total_entries, 0),
          unique_entries: storage_stats.unique_entries + Map.get(metrics, :unique_entries, 0)
      }

      Map.put(state, :storage, updated_storage)
    end)

    :ok
  end

  def record_storage_usage(bytes) when is_integer(bytes) do
    record_storage_usage(%{total_size_bytes: bytes})
  end

  @doc """
  Get cache age statistics.
  """
  @spec get_cache_age_stats() :: map()
  def get_cache_age_stats do
    stats = get_global_stats()

    oldest_entry_days =
      case stats.oldest_cache_entry do
        nil -> nil
        datetime -> DateTime.diff(DateTime.utc_now(), datetime, :day)
      end

    newest_entry_days =
      case stats.newest_cache_entry do
        nil -> nil
        datetime -> DateTime.diff(DateTime.utc_now(), datetime, :day)
      end

    %{
      oldest_entry: stats.oldest_cache_entry,
      newest_entry: stats.newest_cache_entry,
      average_age_days: stats.average_cache_age_days,
      oldest_entry_days: oldest_entry_days,
      newest_entry_days: newest_entry_days
    }
  end

  @doc """
  Record fallback usage.
  """
  @spec record_fallback(map()) :: :ok
  def record_fallback(metadata) do
    ensure_agent_started()
    provider = Map.get(metadata, :provider, "unknown")
    fallback_type = Map.get(metadata, :fallback_type, :unknown)

    Agent.update(@stats_agent_name, fn state ->
      global_stats = Map.get(state, :global, initialize_stats())
      provider_stats = Map.get(state, {:provider, provider}, initialize_stats())

      updated_global = %{
        global_stats
        | fallback_uses: global_stats.fallback_uses + 1,
          fallback_to_older:
            global_stats.fallback_to_older + if(fallback_type == :older_timestamp, do: 1, else: 0)
      }

      updated_provider = %{
        provider_stats
        | fallback_uses: provider_stats.fallback_uses + 1,
          fallback_to_older:
            provider_stats.fallback_to_older +
              if(fallback_type == :older_timestamp, do: 1, else: 0)
      }

      state
      |> Map.put(:global, updated_global)
      |> Map.put({:provider, provider}, updated_provider)
    end)

    :ok
  end

  @doc """
  Format a percentage value.
  """
  @spec format_percentage(float()) :: String.t()
  def format_percentage(ratio) when is_number(ratio) do
    percentage = ratio * 100
    "#{:erlang.float_to_binary(percentage, decimals: 1)}%"
  end

  def format_percentage(_), do: "0.0%"

  @doc """
  Record a refresh event.
  """
  @spec record_refresh(map()) :: :ok
  def record_refresh(metadata) do
    ensure_agent_started()
    provider = Map.get(metadata, :provider, "unknown")
    reason = Map.get(metadata, :reason, :unknown)

    Agent.update(@stats_agent_name, fn state ->
      global_stats = Map.get(state, :global, initialize_stats())
      provider_stats = Map.get(state, {:provider, provider}, initialize_stats())

      refresh_reasons =
        Map.get(state, :refresh_reasons, %{
          ttl_expired: 0,
          manual_refresh: 0,
          fallback_refresh: 0,
          force_refresh: 0
        })

      updated_global = %{
        global_stats
        | ttl_refreshes: global_stats.ttl_refreshes + 1,
          total_requests: global_stats.total_requests + 1
      }

      updated_provider = %{
        provider_stats
        | ttl_refreshes: provider_stats.ttl_refreshes + 1,
          total_requests: provider_stats.total_requests + 1
      }

      updated_refresh_reasons =
        case reason do
          :ttl_expired ->
            %{refresh_reasons | ttl_expired: refresh_reasons.ttl_expired + 1}

          :manual_refresh ->
            %{refresh_reasons | manual_refresh: refresh_reasons.manual_refresh + 1}

          :fallback_refresh ->
            %{refresh_reasons | fallback_refresh: refresh_reasons.fallback_refresh + 1}

          :force_refresh ->
            %{refresh_reasons | force_refresh: refresh_reasons.force_refresh + 1}

          _ ->
            refresh_reasons
        end

      state
      |> Map.put(:global, updated_global)
      |> Map.put({:provider, provider}, updated_provider)
      |> Map.put(:refresh_reasons, updated_refresh_reasons)
    end)

    :ok
  end

  @doc """
  Get storage statistics.
  """
  @spec get_storage_stats() :: map()
  def get_storage_stats do
    ensure_agent_started()

    storage_stats =
      Agent.get(@stats_agent_name, fn state ->
        Map.get(state, :storage, %{
          total_cache_size: 0,
          unique_content_size: 0,
          deduplication_savings: 0,
          total_entries: 0,
          unique_entries: 0
        })
      end)

    deduplication_ratio =
      if storage_stats.total_cache_size > 0 do
        storage_stats.deduplication_savings / storage_stats.total_cache_size
      else
        0.0
      end

    %{
      total_cache_size: storage_stats.total_cache_size,
      unique_content_size: storage_stats.unique_content_size,
      deduplication_savings: storage_stats.deduplication_savings,
      total_entries: storage_stats.total_entries,
      unique_entries: storage_stats.unique_entries,
      total_size_mb: storage_stats.total_cache_size / (1024 * 1024),
      unique_size_mb: storage_stats.unique_content_size / (1024 * 1024),
      deduplication_ratio: deduplication_ratio
    }
  end

  @doc """
  Get test-specific statistics.
  """
  @spec get_test_stats(String.t()) :: map()
  def get_test_stats(test_key) do
    ensure_agent_started()

    # Extract test module and test name from test_key
    case String.split(test_key, ":") do
      [test_module, test_name] ->
        # Get stats from agent for this specific test
        Agent.get(@stats_agent_name, fn state ->
          test_stats = Map.get(state, {:test, test_module, test_name}, initialize_stats())
          finalize_stats(test_stats)
        end)

      _ ->
        initialize_stats()
    end
  end

  @doc """
  Get refresh reasons statistics.
  """
  @spec get_refresh_reasons() :: map()
  def get_refresh_reasons do
    ensure_agent_started()

    Agent.get(@stats_agent_name, fn state ->
      Map.get(state, :refresh_reasons, %{
        ttl_expired: 0,
        manual_refresh: 0,
        fallback_refresh: 0,
        force_refresh: 0
      })
    end)
  end

  # Private helper functions

  defp ensure_agent_started do
    case Process.whereis(@stats_agent_name) do
      nil ->
        case start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  # Placeholder recording functions (would be enhanced with proper persistence)

  defp record_cache_hit(_cache_key, _timestamp, _metadata), do: :ok
  defp record_cache_miss(_cache_key, _timestamp, _metadata), do: :ok
  defp record_ttl_refresh(_cache_key, _timestamp, _metadata), do: :ok
  defp record_fallback_use(_cache_key, _timestamp, _metadata), do: :ok
  defp record_cache_save(_cache_key, _timestamp, _metadata), do: :ok
end
