defmodule ExLLM.TestCacheTTL do
  @moduledoc false

  alias ExLLM.TestCacheConfig
  alias ExLLM.TestCacheIndex

  @type cache_selection_result ::
          {:ok, String.t()}
          | {:expired, String.t()}
          | {:fallback, String.t()}
          | :none

  @type fallback_strategy :: :latest_success | :latest_any | :best_match

  @doc """
  Select the best cache entry based on TTL and fallback strategy.
  """
  @spec select_cache_entry(String.t(), non_neg_integer() | :infinity, fallback_strategy()) ::
          cache_selection_result()
  def select_cache_entry(cache_dir, ttl, strategy) do
    case File.exists?(cache_dir) do
      true ->
        index = TestCacheIndex.load_index(cache_dir)
        select_from_index(index, ttl, strategy)

      false ->
        :none
    end
  end

  @doc """
  Check if a cache entry is expired based on TTL.
  """
  @spec cache_expired?(DateTime.t(), non_neg_integer() | :infinity) :: boolean()
  def cache_expired?(_timestamp, :infinity), do: false

  def cache_expired?(timestamp, ttl_ms) when is_integer(ttl_ms) do
    age_ms = DateTime.diff(DateTime.utc_now(), timestamp, :millisecond)
    age_ms > ttl_ms
  end

  @doc """
  Get the latest valid (non-expired) entry from cache directory.
  """
  @spec get_latest_valid_entry(String.t(), non_neg_integer() | :infinity) ::
          {:ok, String.t()} | :none
  def get_latest_valid_entry(cache_dir, ttl) do
    case File.exists?(cache_dir) do
      true ->
        index = TestCacheIndex.load_index(cache_dir)
        valid_entries = TestCacheIndex.get_valid_entries(index, ttl)

        case valid_entries do
          [entry | _] -> {:ok, entry.filename}
          [] -> :none
        end

      false ->
        :none
    end
  end

  @doc """
  Get the latest successful entry from cache directory within TTL.
  """
  @spec get_latest_successful_entry(String.t(), non_neg_integer() | :infinity) ::
          {:ok, String.t()} | :none
  def get_latest_successful_entry(cache_dir, ttl) do
    case File.exists?(cache_dir) do
      true ->
        index = TestCacheIndex.load_index(cache_dir)
        valid_entries = TestCacheIndex.get_valid_entries(index, ttl)

        success_entries =
          TestCacheIndex.get_entries_by_status(%{index | entries: valid_entries}, :success)

        case success_entries do
          [entry | _] -> {:ok, entry.filename}
          [] -> :none
        end

      false ->
        :none
    end
  end

  @doc """
  Check if a force refresh is required for the current test context.
  """
  @spec force_refresh_for_test?(map()) :: boolean()
  def force_refresh_for_test?(test_context) do
    case test_context do
      {:ok, context} ->
        force_refresh_patterns = get_force_refresh_patterns()
        module_name = to_string(context.module)
        test_name = Map.get(context, :test_name, "")

        Enum.any?(force_refresh_patterns, fn pattern ->
          String.contains?(module_name, pattern) or String.contains?(test_name, pattern)
        end)

      :error ->
        false
    end
  end

  @doc """
  Calculate TTL for specific test context and provider.
  """
  @spec calculate_ttl([atom()], atom()) :: non_neg_integer() | :infinity
  def calculate_ttl(test_tags, provider) do
    TestCacheConfig.get_ttl(test_tags, provider)
  end

  @doc """
  Get cache entry age in milliseconds.
  """
  @spec get_cache_age(DateTime.t()) :: non_neg_integer()
  def get_cache_age(timestamp) do
    DateTime.diff(DateTime.utc_now(), timestamp, :millisecond)
  end

  @doc """
  Check if cache should be warmed up based on upcoming expiration.
  """
  @spec should_warm_cache?(DateTime.t(), non_neg_integer() | :infinity) :: boolean()
  def should_warm_cache?(_timestamp, :infinity), do: false

  def should_warm_cache?(timestamp, ttl_ms) when is_integer(ttl_ms) do
    age_ms = get_cache_age(timestamp)
    # Warm up when 80% of TTL has passed
    warmup_threshold = ttl_ms * 0.8
    age_ms > warmup_threshold
  end

  @doc """
  Get entries that are near expiration and should be refreshed.
  """
  @spec get_entries_near_expiration(String.t(), non_neg_integer() | :infinity) :: [map()]
  def get_entries_near_expiration(_cache_dir, :infinity), do: []

  def get_entries_near_expiration(cache_dir, ttl_ms) when is_integer(ttl_ms) do
    case File.exists?(cache_dir) do
      true ->
        index = TestCacheIndex.load_index(cache_dir)
        warmup_threshold = ttl_ms * 0.8

        Enum.filter(index.entries, fn entry ->
          age_ms = get_cache_age(entry.timestamp)
          age_ms > warmup_threshold and age_ms <= ttl_ms
        end)

      false ->
        []
    end
  end

  @doc """
  Select fallback entry when primary cache is unavailable.
  """
  @spec select_fallback_entry(String.t(), fallback_strategy()) :: {:ok, String.t()} | :none
  def select_fallback_entry(cache_dir, strategy) do
    case File.exists?(cache_dir) do
      true ->
        index = TestCacheIndex.load_index(cache_dir)
        select_fallback_from_index(index, strategy)

      false ->
        :none
    end
  end

  @doc """
  Check if a cached response is still compatible with current API version.
  """
  @spec api_version_compatible?(map(), String.t() | nil) :: boolean()
  # No version requirement
  def api_version_compatible?(_entry, nil), do: true

  def api_version_compatible?(entry, required_version) do
    entry_version = Map.get(entry, :api_version)

    case entry_version do
      # Assume compatible if no version stored
      nil -> true
      ^required_version -> true
      _ -> version_compatible?(entry_version, required_version)
    end
  end

  @doc """
  Get cache refresh priority based on usage and expiration.
  """
  @spec get_refresh_priority(map(), non_neg_integer() | :infinity) :: :high | :medium | :low
  def get_refresh_priority(_entry, :infinity), do: :low

  def get_refresh_priority(entry, ttl_ms) when is_integer(ttl_ms) do
    age_ms = get_cache_age(entry.timestamp)
    age_ratio = age_ms / ttl_ms

    cond do
      # Expired
      age_ratio > 1.0 -> :high
      # Near expiration
      age_ratio > 0.8 -> :medium
      # Fresh
      true -> :low
    end
  end

  # Private functions

  defp select_from_index(index, ttl, strategy) do
    case strategy do
      :latest_success -> select_latest_success_from_index(index, ttl)
      :latest_any -> select_latest_any_from_index(index, ttl)
      :best_match -> select_best_match_from_index(index, ttl)
    end
  end

  defp select_latest_success_from_index(index, ttl) do
    success_entries = TestCacheIndex.get_entries_by_status(index, :success)
    valid_entries = filter_valid_entries(success_entries, ttl)

    case valid_entries do
      [entry | _] ->
        {:ok, entry.filename}

      [] ->
        # No valid successful entries, check for expired ones as fallback
        case success_entries do
          [entry | _] -> {:expired, entry.filename}
          [] -> :none
        end
    end
  end

  defp select_latest_any_from_index(index, ttl) do
    valid_entries = filter_valid_entries(index.entries, ttl)

    case valid_entries do
      [entry | _] ->
        {:ok, entry.filename}

      [] ->
        # No valid entries, check for expired ones as fallback
        case index.entries do
          [entry | _] -> {:expired, entry.filename}
          [] -> :none
        end
    end
  end

  defp select_best_match_from_index(index, ttl) do
    # For now, best_match uses the same logic as latest_success
    # This can be enhanced with more sophisticated matching in the future
    select_latest_success_from_index(index, ttl)
  end

  defp select_fallback_from_index(index, strategy) do
    case strategy do
      :latest_success ->
        success_entries = TestCacheIndex.get_entries_by_status(index, :success)

        case success_entries do
          [entry | _] -> {:ok, entry.filename}
          [] -> :none
        end

      :latest_any ->
        case index.entries do
          [entry | _] -> {:ok, entry.filename}
          [] -> :none
        end

      :best_match ->
        select_fallback_from_index(index, :latest_success)
    end
  end

  defp filter_valid_entries(entries, :infinity), do: entries

  defp filter_valid_entries(entries, ttl_ms) when is_integer(ttl_ms) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -ttl_ms, :millisecond)
    Enum.filter(entries, &(DateTime.compare(&1.timestamp, cutoff_time) != :lt))
  end

  defp get_force_refresh_patterns do
    [
      System.get_env("EX_LLM_TEST_CACHE_FORCE_REFRESH"),
      System.get_env("EX_LLM_TEST_CACHE_FORCE_MISS")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp version_compatible?(entry_version, required_version) do
    # Simple version compatibility check
    # This can be enhanced with more sophisticated version parsing
    case {parse_version(entry_version), parse_version(required_version)} do
      {{major1, minor1, _}, {major2, minor2, _}} ->
        major1 == major2 and minor1 >= minor2

      # Assume compatible if parsing fails
      _ ->
        true
    end
  end

  defp parse_version(version_string) when is_binary(version_string) do
    # Handle date-based API versions like "2023-06-01"
    case String.split(version_string, "-") do
      [year, month, day] ->
        with {y, ""} <- Integer.parse(year),
             {m, ""} <- Integer.parse(month),
             {d, ""} <- Integer.parse(day) do
          {y, m, d}
        else
          _ -> parse_semantic_version(version_string)
        end

      _ ->
        parse_semantic_version(version_string)
    end
  end

  defp parse_version(_), do: :error

  defp parse_semantic_version(version_string) do
    case String.split(version_string, ".") do
      [major, minor, patch] ->
        with {maj, ""} <- Integer.parse(major),
             {min, ""} <- Integer.parse(minor),
             {pat, ""} <- Integer.parse(patch) do
          {maj, min, pat}
        else
          _ -> :error
        end

      [major, minor] ->
        with {maj, ""} <- Integer.parse(major),
             {min, ""} <- Integer.parse(minor) do
          {maj, min, 0}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end
end
