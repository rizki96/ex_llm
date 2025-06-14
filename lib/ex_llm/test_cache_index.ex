defmodule ExLLM.TestCacheIndex do
  @moduledoc """
  Maintain index of timestamped cache entries with metadata.

  This module provides efficient indexing and querying of timestamp-based
  cache entries, including content deduplication tracking, usage statistics,
  and cleanup coordination for the test caching system.
  """

  alias ExLLM.TestCacheConfig
  alias ExLLM.TestCacheTimestamp

  @type cache_entry :: %{
          timestamp: DateTime.t(),
          filename: String.t(),
          status: :success | :error | :timeout,
          size: non_neg_integer(),
          content_hash: String.t(),
          response_time_ms: non_neg_integer(),
          api_version: String.t() | nil,
          cost: map() | nil
        }

  @type cache_index :: %{
          cache_key: String.t(),
          test_context: map() | nil,
          ttl: non_neg_integer() | :infinity,
          fallback_strategy: atom(),
          entries: [cache_entry()],
          total_requests: non_neg_integer(),
          cache_hits: non_neg_integer(),
          last_accessed: DateTime.t() | nil,
          access_count: non_neg_integer(),
          last_cleanup: DateTime.t() | nil,
          cleanup_before: DateTime.t() | nil
        }

  @doc """
  Load cache index from disk or create a new one.
  """
  @spec load_index(String.t()) :: cache_index()
  def load_index(cache_dir) do
    index_file = Path.join(cache_dir, "index.json")

    case File.read(index_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, index_data} -> parse_index_data(index_data, cache_dir)
          {:error, _} -> create_new_index(cache_dir)
        end

      {:error, _} ->
        create_new_index(cache_dir)
    end
  end

  @doc """
  Save cache index to disk.
  """
  @spec save_index(String.t(), cache_index()) :: :ok | {:error, term()}
  def save_index(cache_dir, index) do
    index_file = Path.join(cache_dir, "index.json")

    with :ok <- File.mkdir_p(cache_dir),
         {:ok, json} <- Jason.encode(serialize_index(index)),
         :ok <- File.write(index_file, json) do
      :ok
    else
      {:error, reason} -> {:error, "Failed to save cache index: #{inspect(reason)}"}
    end
  end

  @doc """
  Add a new cache entry to the index.
  """
  @spec add_entry(cache_index(), cache_entry()) :: cache_index()
  def add_entry(index, entry) do
    # Remove any existing entry with the same timestamp (should be rare)
    existing_entries = Enum.reject(index.entries, &(&1.timestamp == entry.timestamp))

    # Add new entry and sort by timestamp (newest first)
    new_entries =
      [entry | existing_entries]
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

    %{
      index
      | entries: new_entries,
        total_requests: index.total_requests + 1,
        last_accessed: DateTime.utc_now()
    }
  end

  @doc """
  Add a new cache entry to the index and save to disk.
  """
  @spec add_entry(cache_index(), cache_entry(), String.t()) :: cache_index()
  def add_entry(_index, entry, cache_dir) do
    # Always load the latest state from disk first
    current_index = load_index(cache_dir)
    updated_index = add_entry(current_index, entry)

    # Save the updated index
    case save_index(cache_dir, updated_index) do
      :ok -> updated_index
      # Return updated index even if save fails
      {:error, _} -> updated_index
    end
  end

  @doc """
  Add a new cache entry with options like max_entries limit.
  """
  @spec add_entry(cache_index(), cache_entry(), String.t(), keyword()) :: cache_index()
  def add_entry(_index, entry, cache_dir, opts) do
    max_entries = Keyword.get(opts, :max_entries)

    # Always load the latest state from disk first
    current_index = load_index(cache_dir)
    updated_index = add_entry(current_index, entry)

    # Apply max entries limit if specified
    final_index =
      if max_entries do
        limit_entries(updated_index, max_entries)
      else
        updated_index
      end

    # Save the updated index
    case save_index(cache_dir, final_index) do
      :ok -> final_index
      # Return updated index even if save fails
      {:error, _} -> final_index
    end
  end

  @doc """
  Remove cache entries older than the specified cutoff.
  """
  @spec remove_old_entries(cache_index(), DateTime.t()) :: cache_index()
  def remove_old_entries(index, cutoff_time) do
    valid_entries =
      Enum.filter(index.entries, &(DateTime.compare(&1.timestamp, cutoff_time) != :lt))

    %{
      index
      | entries: valid_entries,
        last_cleanup: DateTime.utc_now(),
        cleanup_before: cutoff_time
    }
  end

  @doc """
  Keep only the specified number of most recent entries.
  """
  @spec limit_entries(cache_index(), non_neg_integer()) :: cache_index()
  def limit_entries(index, max_entries) when max_entries > 0 do
    limited_entries =
      index.entries
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
      |> Enum.take(max_entries)

    %{index | entries: limited_entries}
  end

  def limit_entries(index, _max_entries), do: index

  @doc """
  Record a cache hit for statistics.
  """
  @spec record_hit(cache_index()) :: cache_index()
  def record_hit(index) do
    %{
      index
      | cache_hits: index.cache_hits + 1,
        access_count: index.access_count + 1,
        last_accessed: DateTime.utc_now()
    }
  end

  @doc """
  Record a cache access (hit or miss) for statistics.
  """
  @spec record_access(cache_index()) :: cache_index()
  def record_access(index) do
    %{index | access_count: index.access_count + 1, last_accessed: DateTime.utc_now()}
  end

  @doc """
  Get entries that match the specified status.
  """
  @spec get_entries_by_status(cache_index(), :success | :error | :timeout | :any) :: [
          cache_entry()
        ]
  def get_entries_by_status(index, :any) do
    # If index seems empty but we have a cache_key, try loading from disk
    if length(index.entries) == 0 and index.cache_key != nil do
      cache_dir = rebuild_cache_dir_from_key(index.cache_key)

      if File.exists?(Path.join(cache_dir, "index.json")) do
        current_index = load_index(cache_dir)
        current_index.entries
      else
        index.entries
      end
    else
      index.entries
    end
  end

  def get_entries_by_status(index, status) do
    all_entries = get_entries_by_status(index, :any)
    Enum.filter(all_entries, &(&1.status == status))
  end

  @doc """
  Get entries that match the specified status, with directory path for loading latest state.
  """
  @spec get_entries_by_status(cache_index(), :success | :error | :timeout | :any, String.t()) :: [
          cache_entry()
        ]
  def get_entries_by_status(_index, status, cache_dir) do
    # Always load the latest state from disk
    current_index = load_index(cache_dir)
    get_entries_by_status(current_index, status)
  end

  @doc """
  Get entries within the specified TTL.
  """
  @spec get_valid_entries(cache_index(), non_neg_integer() | :infinity) :: [cache_entry()]
  def get_valid_entries(index, :infinity), do: index.entries

  def get_valid_entries(index, ttl_ms) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -ttl_ms, :millisecond)
    Enum.filter(index.entries, &(DateTime.compare(&1.timestamp, cutoff_time) != :lt))
  end

  @doc """
  Find duplicate entries based on content hash.
  """
  @spec find_duplicates(cache_index()) :: %{String.t() => [cache_entry()]}
  def find_duplicates(index) do
    index.entries
    |> Enum.group_by(& &1.content_hash)
    |> Enum.filter(fn {_hash, entries} -> length(entries) > 1 end)
    |> Enum.into(%{})
  end

  @doc """
  Get cache statistics from the index.
  """
  @spec get_statistics(cache_index()) :: map()
  def get_statistics(index) do
    duplicates = find_duplicates(index)
    duplicate_count = duplicates |> Map.values() |> List.flatten() |> length()
    unique_hashes = index.entries |> Enum.map(& &1.content_hash) |> Enum.uniq() |> length()

    total_size = Enum.reduce(index.entries, 0, &(&1.size + &2))
    avg_size = if length(index.entries) > 0, do: div(total_size, length(index.entries)), else: 0

    success_entries = get_entries_by_status(index, :success)
    error_entries = get_entries_by_status(index, :error)

    hit_rate = if index.access_count > 0, do: index.cache_hits / index.access_count, else: 0.0

    %{
      cache_key: index.cache_key,
      total_entries: length(index.entries),
      success_entries: length(success_entries),
      error_entries: length(error_entries),
      unique_content_hashes: unique_hashes,
      duplicate_entries: duplicate_count,
      total_size_bytes: total_size,
      average_size_bytes: avg_size,
      total_requests: index.total_requests,
      cache_hits: index.cache_hits,
      hit_rate: hit_rate,
      access_count: index.access_count,
      last_accessed: index.last_accessed,
      last_cleanup: index.last_cleanup,
      oldest_entry: get_oldest_entry(index),
      newest_entry: get_newest_entry(index)
    }
  end

  @doc """
  Rebuild index from existing cache files.
  """
  @spec rebuild_index(String.t()) :: cache_index()
  def rebuild_index(cache_dir) do
    base_index = create_new_index(cache_dir)

    case File.ls(cache_dir) do
      {:ok, files} ->
        entries =
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.reject(&(&1 == "index.json"))
          |> Enum.map(&build_entry_from_file(cache_dir, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

        %{base_index | entries: entries}

      {:error, _} ->
        base_index
    end
  end

  @doc """
  Remove a specific entry by filename.
  """
  @spec remove_entry(cache_index(), String.t(), String.t()) :: cache_index()
  def remove_entry(index, filename, cache_dir) do
    updated_entries = Enum.reject(index.entries, &(&1.filename == filename))
    updated_index = %{index | entries: updated_entries}

    # Also delete the actual file
    file_path = Path.join(cache_dir, filename)
    File.rm(file_path)

    # Save the updated index
    case save_index(cache_dir, updated_index) do
      :ok -> updated_index
      # Return updated index even if save fails
      {:error, _} -> updated_index
    end
  end

  @doc """
  Calculate the hit rate for the index.
  """
  @spec calculate_hit_rate(cache_index()) :: float()
  def calculate_hit_rate(index) do
    if index.total_requests > 0 do
      index.cache_hits / index.total_requests
    else
      0.0
    end
  end

  @doc """
  Get entry by filename.
  """
  @spec get_entry_by_filename(cache_index(), String.t()) :: {:ok, cache_entry()} | :error
  def get_entry_by_filename(index, filename) do
    case Enum.find(index.entries, &(&1.filename == filename)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @doc """
  Clean up old entries by age.
  """
  @spec cleanup_old_entries(cache_index(), non_neg_integer(), String.t()) :: cache_index()
  def cleanup_old_entries(index, max_age_ms, cache_dir) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -max_age_ms, :millisecond)
    updated_index = remove_old_entries(index, cutoff_time)

    # Save the updated index
    case save_index(cache_dir, updated_index) do
      :ok -> updated_index
      {:error, _} -> updated_index
    end
  end

  @doc """
  Find duplicate content using content hashes.
  """
  @spec find_duplicate_content(cache_index()) :: %{String.t() => [cache_entry()]}
  def find_duplicate_content(index) do
    find_duplicates(index)
  end

  @doc """
  Update cache statistics.
  """
  @spec update_stats(cache_index(), :hit | :miss, String.t()) :: cache_index()
  def update_stats(_index, stat_type, cache_dir) do
    # Always load the latest state from disk first
    current_index = load_index(cache_dir)

    updated_index =
      case stat_type do
        :hit ->
          %{
            current_index
            | cache_hits: current_index.cache_hits + 1,
              total_requests: current_index.total_requests + 1,
              access_count: current_index.access_count + 1,
              last_accessed: DateTime.utc_now()
          }

        :miss ->
          %{
            current_index
            | total_requests: current_index.total_requests + 1,
              access_count: current_index.access_count + 1,
              last_accessed: DateTime.utc_now()
          }
      end

    # Save the updated index
    case save_index(cache_dir, updated_index) do
      :ok -> updated_index
      {:error, _} -> updated_index
    end
  end

  @doc """
  Clean up the index and apply retention policies.
  """
  @spec cleanup_index(String.t()) :: :ok | {:error, term()}
  def cleanup_index(cache_dir) do
    config = TestCacheConfig.get_config()
    index = load_index(cache_dir)

    updated_index =
      index
      |> apply_age_cleanup(config.cleanup_older_than)
      |> apply_count_limit(config.max_entries_per_cache)
      |> maybe_deduplicate(config.deduplicate_content)

    save_index(cache_dir, updated_index)
  end

  # Private functions

  defp create_new_index(cache_dir) do
    cache_key = extract_cache_key_from_path(cache_dir)

    %{
      cache_key: cache_key,
      test_context: nil,
      ttl: 7 * 24 * 60 * 60 * 1000,
      fallback_strategy: :latest_success,
      entries: [],
      total_requests: 0,
      cache_hits: 0,
      last_accessed: nil,
      access_count: 0,
      last_cleanup: nil,
      cleanup_before: nil
    }
  end

  defp parse_index_data(data, cache_dir) do
    entries =
      data
      |> Map.get("entries", [])
      |> Enum.map(&parse_entry_data/1)
      |> Enum.reject(&is_nil/1)

    %{
      cache_key: Map.get(data, "cache_key", extract_cache_key_from_path(cache_dir)),
      test_context: Map.get(data, "test_context"),
      ttl: parse_ttl(Map.get(data, "ttl", 7 * 24 * 60 * 60 * 1000)),
      fallback_strategy: parse_strategy(Map.get(data, "fallback_strategy", "latest_success")),
      entries: entries,
      total_requests: Map.get(data, "total_requests", 0),
      cache_hits: Map.get(data, "cache_hits", 0),
      last_accessed: parse_datetime(Map.get(data, "last_accessed")),
      access_count: Map.get(data, "access_count", 0),
      last_cleanup: parse_datetime(Map.get(data, "last_cleanup")),
      cleanup_before: parse_datetime(Map.get(data, "cleanup_before"))
    }
  end

  defp parse_entry_data(entry_data) do
    case parse_datetime(Map.get(entry_data, "timestamp")) do
      nil ->
        nil

      timestamp ->
        %{
          timestamp: timestamp,
          filename: Map.get(entry_data, "filename", ""),
          status: parse_status(Map.get(entry_data, "status", "success")),
          size: Map.get(entry_data, "size", 0),
          content_hash: Map.get(entry_data, "content_hash", ""),
          response_time_ms: Map.get(entry_data, "response_time_ms", 0),
          api_version: Map.get(entry_data, "api_version"),
          cost: Map.get(entry_data, "cost")
        }
    end
  end

  defp serialize_index(index) do
    %{
      "cache_key" => Map.get(index, :cache_key),
      "test_context" => Map.get(index, :test_context),
      "ttl" => serialize_ttl(Map.get(index, :ttl, 7 * 24 * 60 * 60 * 1000)),
      "fallback_strategy" => to_string(Map.get(index, :fallback_strategy, :latest_success)),
      "entries" => Enum.map(Map.get(index, :entries, []), &serialize_entry/1),
      "total_requests" => Map.get(index, :total_requests, 0),
      "cache_hits" => Map.get(index, :cache_hits, 0),
      "last_accessed" => serialize_datetime(Map.get(index, :last_accessed)),
      "access_count" => Map.get(index, :access_count, 0),
      "last_cleanup" => serialize_datetime(Map.get(index, :last_cleanup)),
      "cleanup_before" => serialize_datetime(Map.get(index, :cleanup_before))
    }
  end

  defp serialize_entry(entry) do
    %{
      "timestamp" => serialize_datetime(entry.timestamp),
      "filename" => entry.filename,
      "status" => to_string(entry.status),
      "size" => entry.size,
      "content_hash" => entry.content_hash,
      "response_time_ms" => entry.response_time_ms,
      "api_version" => entry.api_version,
      "cost" => entry.cost
    }
  end

  defp build_entry_from_file(cache_dir, filename) do
    file_path = Path.join(cache_dir, filename)

    with {:ok, timestamp} <- TestCacheTimestamp.parse_timestamp_from_filename(filename),
         {:ok, file_stat} <- File.stat(file_path) do
      content_hash = TestCacheTimestamp.get_content_hash(file_path)
      status = determine_file_status(file_path)

      %{
        timestamp: timestamp,
        filename: filename,
        status: status,
        size: file_stat.size,
        content_hash: content_hash,
        response_time_ms: extract_response_time(file_path),
        api_version: extract_api_version(file_path),
        cost: extract_cost_info(file_path)
      }
    else
      _ -> nil
    end
  end

  defp determine_file_status(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"response_data" => response_data}} ->
            cond do
              is_map(response_data) and Map.has_key?(response_data, "error") -> :error
              is_map(response_data) and Map.get(response_data, "status") == "error" -> :error
              true -> :success
            end

          {:error, _} ->
            :error
        end

      {:error, _} ->
        :error
    end
  end

  defp extract_response_time(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> Map.get(data, "response_time_ms", 0)
          {:error, _} -> 0
        end

      {:error, _} ->
        0
    end
  end

  defp extract_api_version(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> Map.get(data, "api_version")
          {:error, _} -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp extract_cost_info(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> Map.get(data, "cost")
          {:error, _} -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp apply_age_cleanup(index, max_age_ms) when max_age_ms > 0 do
    cutoff_time = DateTime.add(DateTime.utc_now(), -max_age_ms, :millisecond)
    remove_old_entries(index, cutoff_time)
  end

  defp apply_age_cleanup(index, _max_age_ms), do: index

  defp apply_count_limit(index, max_entries) when max_entries > 0 do
    limit_entries(index, max_entries)
  end

  defp apply_count_limit(index, _max_entries), do: index

  defp maybe_deduplicate(index, true) do
    # Mark duplicates in the index (actual file deduplication handled elsewhere)
    duplicates = find_duplicates(index)

    # Update entries to mark which ones are duplicates
    updated_entries =
      Enum.map(index.entries, fn entry ->
        is_duplicate =
          duplicates
          |> Map.get(entry.content_hash, [])
          |> Enum.count() > 1

        Map.put(entry, :is_duplicate, is_duplicate)
      end)

    %{index | entries: updated_entries}
  end

  defp maybe_deduplicate(index, false), do: index

  defp extract_cache_key_from_path(cache_dir) do
    try do
      config = TestCacheConfig.get_config()
      relative_path = Path.relative_to(cache_dir, config.cache_dir)

      # If the path couldn't be made relative (starts with "..")
      # or config.cache_dir doesn't exist, just use the basename
      if String.starts_with?(relative_path, "..") do
        Path.basename(cache_dir)
      else
        relative_path
      end
    rescue
      _ -> Path.basename(cache_dir)
    end
  end

  defp rebuild_cache_dir_from_key(cache_key) do
    try do
      config = TestCacheConfig.get_config()
      Path.join(config.cache_dir, cache_key)
    rescue
      # Fallback to the key itself as the path
      _ -> cache_key
    end
  end

  defp get_oldest_entry(index) do
    index.entries
    |> Enum.sort_by(& &1.timestamp, {:asc, DateTime})
    |> List.first()
    |> case do
      nil -> nil
      entry -> entry.timestamp
    end
  end

  defp get_newest_entry(index) do
    index.entries
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> List.first()
    |> case do
      nil -> nil
      entry -> entry.timestamp
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp serialize_datetime(nil), do: nil
  defp serialize_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp parse_ttl("infinity"), do: :infinity
  defp parse_ttl(ttl) when is_integer(ttl), do: ttl

  defp parse_ttl(ttl) when is_binary(ttl) do
    case Integer.parse(ttl) do
      {int, ""} -> int
      _ -> 7 * 24 * 60 * 60 * 1000
    end
  end

  defp parse_ttl(_), do: 7 * 24 * 60 * 60 * 1000

  defp serialize_ttl(:infinity), do: "infinity"
  defp serialize_ttl(ttl) when is_integer(ttl), do: ttl

  defp parse_strategy("latest_success"), do: :latest_success
  defp parse_strategy("latest_any"), do: :latest_any
  defp parse_strategy("best_match"), do: :best_match
  defp parse_strategy(_), do: :latest_success

  defp parse_status("success"), do: :success
  defp parse_status("error"), do: :error
  defp parse_status("timeout"), do: :timeout
  defp parse_status(_), do: :success
end
