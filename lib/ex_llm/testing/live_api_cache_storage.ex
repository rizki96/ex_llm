defmodule ExLLM.Testing.LiveApiCacheStorage do
  @moduledoc """
  Specialized storage backend for timestamp-based test response caching.

  This module provides hierarchical organization by provider/test module/scenario
  with timestamp-based file naming, rich metadata indexing, content deduplication,
  and smart fallback strategies for test response caching.
  """

  alias ExLLM.Testing.TestCacheConfig
  alias ExLLM.Testing.TestCacheDetector
  alias ExLLM.Testing.TestCacheIndex
  alias ExLLM.Testing.TestCacheTimestamp

  @type cache_key :: String.t()
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

  @type fallback_strategy :: :latest_success | :latest_any | :best_match

  @spec sanitize_response_data(any()) :: any()
  defp sanitize_response_data(%module{} = _struct) when module in [Req.Response.Async] do
    # For async responses, we can't cache the actual response
    # Instead, cache metadata about the response
    %{
      type: "async_response",
      module: to_string(module),
      timestamp: DateTime.utc_now(),
      cacheable: false
    }
  end

  defp sanitize_response_data(response_data) when is_list(response_data) do
    Enum.map(response_data, &sanitize_response_data/1)
  end

  defp sanitize_response_data(response_data) when is_map(response_data) do
    Map.new(response_data, fn {k, v} -> {k, sanitize_response_data(v)} end)
  end

  defp sanitize_response_data(response_data), do: response_data

  @doc """
  Store a test response with timestamp-based naming.
  """
  @spec store(cache_key(), any(), map()) :: :ok | {:ok, String.t()} | {:error, term()}
  def store(cache_key, response_data, metadata \\ %{}) do
    config = TestCacheConfig.get_config()

    if config.enabled do
      cache_dir = build_cache_dir(cache_key, config)
      timestamp_filename = TestCacheTimestamp.generate_timestamp_filename()
      file_path = Path.join(cache_dir, timestamp_filename)

      # Prepare cache entry data
      entry_data = %{
        request_metadata: sanitize_metadata(metadata),
        response_data: sanitize_response_data(response_data),
        cached_at: DateTime.utc_now(),
        cache_version: "1.0",
        test_context:
          case TestCacheDetector.get_current_test_context() do
            {:ok, ctx} ->
              %{
                module: to_string(ctx.module),
                test_name: ctx.test_name,
                tags: ctx.tags,
                pid: inspect(ctx.pid)
              }

            :error ->
              nil
          end,
        api_version: extract_api_version(metadata)
      }

      with :ok <- File.mkdir_p(cache_dir),
           :ok <- File.write(file_path, Jason.encode!(entry_data)),
           {:ok, file_stat} <- File.stat(file_path),
           content_hash <- TestCacheTimestamp.get_content_hash(file_path),
           :ok <-
             update_cache_index(
               cache_dir,
               timestamp_filename,
               file_stat.size,
               content_hash,
               metadata
             ) do
        # Run cleanup if enabled
        maybe_cleanup_old_entries(cache_dir, config)
        maybe_deduplicate_content(cache_dir, config)

        {:ok, file_path}
      else
        {:error, reason} -> {:error, "Failed to store cache entry: #{inspect(reason)}"}
      end
    else
      :ok
    end
  end

  @doc """
  Retrieve a cached response using TTL and fallback strategy.
  """
  @spec get(cache_key(), map()) :: {:ok, any()} | {:error, term()} | :miss
  def get(cache_key, options \\ %{}) do
    config = TestCacheConfig.get_config()

    if config.enabled do
      perform_cache_lookup(cache_key, config, options)
    else
      :miss
    end
  end

  defp perform_cache_lookup(cache_key, config, options) do
    cache_dir = build_cache_dir(cache_key, config)
    test_context = TestCacheDetector.get_current_test_context()

    # Get TTL and fallback strategy for this context
    test_tags = get_test_tags(test_context)
    provider = extract_provider(cache_key)
    ttl = TestCacheConfig.get_ttl(test_tags, provider)
    strategy = TestCacheConfig.get_fallback_strategy(test_tags)

    # Override with options if provided
    ttl = Map.get(options, :ttl, ttl)
    strategy = Map.get(options, :fallback_strategy, strategy)

    case select_best_cache_entry(cache_dir, ttl, strategy) do
      {:ok, filename} ->
        read_cache_file(cache_dir, filename)

      {:expired, latest_filename} ->
        handle_expired_cache(cache_dir, latest_filename, options)

      :none ->
        :miss
    end
  end

  defp read_cache_file(cache_dir, filename) do
    file_path = Path.join(cache_dir, filename)

    case File.read(file_path) do
      {:ok, content} ->
        parse_cache_content(content)

      {:error, reason} ->
        {:error, "Failed to read cached file: #{inspect(reason)}"}
    end
  end

  defp parse_cache_content(content) do
    case Jason.decode(content) do
      {:ok, entry_data} ->
        {:ok, entry_data["response_data"]}

      {:error, reason} ->
        {:error, "Failed to parse cached response: #{inspect(reason)}"}
    end
  end

  defp handle_expired_cache(cache_dir, latest_filename, options) do
    if Map.get(options, :allow_expired, false) do
      read_expired_cache_file(cache_dir, latest_filename)
    else
      :miss
    end
  end

  defp read_expired_cache_file(cache_dir, filename) do
    file_path = Path.join(cache_dir, filename)

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, entry_data} -> {:ok, entry_data["response_data"]}
          {:error, _} -> :miss
        end

      {:error, _} ->
        :miss
    end
  end

  @doc """
  Check if a cached response exists and is valid.
  """
  @spec exists?(cache_key()) :: boolean()
  def exists?(cache_key) do
    config = TestCacheConfig.get_config()

    if config.enabled do
      cache_dir = build_cache_dir(cache_key, config)
      test_context = TestCacheDetector.get_current_test_context()
      test_tags = get_test_tags(test_context)
      provider = extract_provider(cache_key)
      ttl = TestCacheConfig.get_ttl(test_tags, provider)
      strategy = TestCacheConfig.get_fallback_strategy(test_tags)

      case select_best_cache_entry(cache_dir, ttl, strategy) do
        {:ok, _filename} -> true
        _ -> false
      end
    else
      false
    end
  end

  @doc """
  Clear cache entries for a specific cache key or pattern.
  """
  @spec clear(cache_key() | :all) :: :ok | {:error, term()}
  def clear(:all) do
    config = TestCacheConfig.get_config()
    cache_base_dir = config.cache_dir

    case File.rm_rf(cache_base_dir) do
      {:ok, _} -> :ok
      {:error, reason, _file} -> {:error, "Failed to clear all cache: #{inspect(reason)}"}
    end
  end

  def clear(cache_key) do
    config = TestCacheConfig.get_config()
    cache_dir = build_cache_dir(cache_key, config)

    case File.rm_rf(cache_dir) do
      {:ok, _} ->
        :ok

      {:error, reason, _file} ->
        {:error, "Failed to clear cache for #{cache_key}: #{inspect(reason)}"}
    end
  end

  @doc """
  List all available cache keys.
  """
  @spec list_cache_keys() :: [cache_key()]
  def list_cache_keys do
    config = TestCacheConfig.get_config()
    cache_base_dir = config.cache_dir

    case File.exists?(cache_base_dir) do
      true -> walk_cache_directories(cache_base_dir, cache_base_dir)
      false -> []
    end
  end

  @doc """
  Get cache statistics for a specific key or all keys.
  """
  @spec get_stats(cache_key() | :all) :: map()
  def get_stats(:all) do
    cache_keys = list_cache_keys()

    Enum.reduce(
      cache_keys,
      %{total_keys: 0, total_entries: 0, total_size: 0, oldest_entry: nil, newest_entry: nil},
      fn key, acc ->
        key_stats = get_stats(key)

        %{
          total_keys: acc.total_keys + 1,
          total_entries: acc.total_entries + key_stats.total_entries,
          total_size: acc.total_size + key_stats.total_size,
          oldest_entry: earliest_datetime(acc.oldest_entry, key_stats.oldest_entry),
          newest_entry: latest_datetime(acc.newest_entry, key_stats.newest_entry)
        }
      end
    )
  end

  def get_stats(cache_key) do
    config = TestCacheConfig.get_config()
    cache_dir = build_cache_dir(cache_key, config)

    case File.exists?(cache_dir) do
      true ->
        timestamps = TestCacheTimestamp.list_cache_timestamps(cache_dir)
        entries = get_cache_entries(cache_dir)

        total_size = Enum.reduce(entries, 0, fn entry, acc -> acc + entry.size end)

        %{
          cache_key: cache_key,
          total_entries: length(entries),
          total_size: total_size,
          oldest_entry: List.last(timestamps),
          newest_entry: List.first(timestamps),
          entries: entries
        }

      false ->
        %{
          cache_key: cache_key,
          total_entries: 0,
          total_size: 0,
          oldest_entry: nil,
          newest_entry: nil,
          entries: []
        }
    end
  end

  # Private functions

  defp sanitize_metadata(metadata) do
    metadata
    |> Map.update(:headers, [], &sanitize_headers/1)
    |> Map.update("headers", [], &sanitize_headers/1)
  end

  defp sanitize_headers(headers) when is_list(headers) do
    headers
    |> Enum.map(fn
      {k, v} -> {to_string(k), to_string(v)}
      other -> other
    end)
    |> Map.new()
  end

  defp sanitize_headers(headers), do: headers

  defp build_cache_dir(cache_key, config) do
    Path.join(config.cache_dir, cache_key)
  end

  defp select_best_cache_entry(cache_dir, ttl, strategy) do
    case File.exists?(cache_dir) do
      true ->
        _timestamps = TestCacheTimestamp.list_cache_timestamps(cache_dir)
        entries = get_cache_entries(cache_dir)

        case strategy do
          :latest_success -> select_latest_success(entries, ttl)
          :latest_any -> select_latest_any(entries, ttl)
          :best_match -> select_best_match(entries, ttl)
        end

      false ->
        :none
    end
  end

  defp select_latest_success(entries, ttl) do
    case find_valid_entries(entries, ttl, :success) do
      [entry | _] ->
        {:ok, entry.filename}

      [] ->
        case find_latest_entry(entries, :success) do
          nil -> :none
          entry -> {:expired, entry.filename}
        end
    end
  end

  defp select_latest_any(entries, ttl) do
    case find_valid_entries(entries, ttl, :any) do
      [entry | _] ->
        {:ok, entry.filename}

      [] ->
        case find_latest_entry(entries, :any) do
          nil -> :none
          entry -> {:expired, entry.filename}
        end
    end
  end

  defp select_best_match(entries, ttl) do
    # For now, best_match is the same as latest_success
    # This can be enhanced with more sophisticated matching logic
    select_latest_success(entries, ttl)
  end

  defp find_valid_entries(entries, ttl, status_filter) do
    now = DateTime.utc_now()

    entries
    |> Enum.filter(fn entry ->
      status_match =
        case status_filter do
          :success -> entry.status == :success
          :any -> true
        end

      within_ttl =
        case ttl do
          :infinity ->
            true

          ttl_ms when is_integer(ttl_ms) ->
            age_ms = DateTime.diff(now, entry.timestamp, :millisecond)
            age_ms <= ttl_ms
        end

      status_match and within_ttl
    end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp find_latest_entry(entries, status_filter) do
    entries
    |> Enum.filter(fn entry ->
      case status_filter do
        :success -> entry.status == :success
        :any -> true
      end
    end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> List.first()
  end

  defp get_cache_entries(cache_dir) do
    case File.ls(cache_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.reject(&(&1 == "index.json"))
        |> Enum.map(fn filename ->
          file_path = Path.join(cache_dir, filename)

          case TestCacheTimestamp.parse_timestamp_from_filename(filename) do
            {:ok, timestamp} ->
              size = get_file_size(file_path)
              content_hash = TestCacheTimestamp.get_content_hash(file_path)
              status = determine_entry_status(file_path)

              %{
                timestamp: timestamp,
                filename: filename,
                status: status,
                size: size,
                content_hash: content_hash,
                # Could be extracted from file content
                response_time_ms: 0,
                # Could be extracted from file content
                api_version: nil,
                # Could be extracted from file content
                cost: nil
              }

            :error ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

      {:error, _} ->
        []
    end
  end

  # Helper function to get file size safely
  defp get_file_size(file_path) do
    case File.stat(file_path) do
      {:ok, %{size: size}} -> size
      {:error, _} -> 0
    end
  end

  defp determine_entry_status(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"response_data" => response_data}} ->
            # Check if response indicates an error
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

  defp update_cache_index(cache_dir, filename, size, content_hash, metadata) do
    # Extract timestamp from filename
    {:ok, timestamp} = TestCacheTimestamp.parse_timestamp_from_filename(filename)

    # Create new entry
    new_entry = %{
      timestamp: timestamp,
      filename: filename,
      status: determine_entry_status_from_metadata(metadata),
      size: size,
      content_hash: content_hash,
      response_time_ms: Map.get(metadata, :response_time_ms, 0),
      api_version: Map.get(metadata, :api_version),
      cost: Map.get(metadata, :cost)
    }

    # Add entry to index and save atomically
    TestCacheIndex.add_entry_atomic(cache_dir, new_entry)
  end

  defp determine_entry_status_from_metadata(metadata) do
    cond do
      Map.get(metadata, :error, false) -> :error
      Map.get(metadata, :timeout, false) -> :timeout
      true -> :success
    end
  end

  defp maybe_cleanup_old_entries(cache_dir, config) do
    if config.cleanup_older_than > 0 or config.max_entries_per_cache > 0 do
      TestCacheTimestamp.cleanup_old_entries(
        cache_dir,
        config.max_entries_per_cache,
        config.cleanup_older_than
      )
    end
  end

  defp maybe_deduplicate_content(cache_dir, config) do
    if config.deduplicate_content do
      TestCacheTimestamp.deduplicate_content(cache_dir)
    end
  end

  defp extract_api_version(metadata) do
    metadata
    |> Map.get("headers", [])
    |> Enum.find_value(fn
      {"api-version", version} -> version
      {"x-api-version", version} -> version
      {"anthropic-version", version} -> version
      _ -> nil
    end)
  end

  defp get_test_tags({:ok, context}), do: Map.get(context, :tags, [])
  defp get_test_tags(:error), do: []

  defp extract_provider(cache_key) do
    cache_key
    |> String.split("/")
    |> List.first()
    |> String.to_atom()
  end

  defp walk_cache_directories(current_path, base_path) do
    case File.ls(current_path) do
      {:ok, entries} ->
        entries
        |> Enum.flat_map(&process_directory_entry(&1, current_path, base_path))
        |> Enum.uniq()

      {:error, _} ->
        []
    end
  end

  defp process_directory_entry(entry, current_path, base_path) do
    entry_path = Path.join(current_path, entry)

    cond do
      should_recurse_directory?(entry_path, entry) ->
        walk_cache_directories(entry_path, base_path)

      is_valid_cache_file?(entry) ->
        get_relative_directory(current_path, base_path)

      true ->
        []
    end
  end

  defp should_recurse_directory?(entry_path, entry) do
    File.dir?(entry_path) and entry != "index.json"
  end

  defp is_valid_cache_file?(entry) do
    String.ends_with?(entry, ".json") and entry != "index.json"
  end

  defp get_relative_directory(current_path, base_path) do
    relative_dir = Path.relative_to(current_path, base_path)

    if relative_dir == "." do
      []
    else
      [relative_dir]
    end
  end

  defp earliest_datetime(nil, datetime), do: datetime
  defp earliest_datetime(datetime, nil), do: datetime

  defp earliest_datetime(dt1, dt2) do
    case DateTime.compare(dt1, dt2) do
      :lt -> dt1
      _ -> dt2
    end
  end

  defp latest_datetime(nil, datetime), do: datetime
  defp latest_datetime(datetime, nil), do: datetime

  defp latest_datetime(dt1, dt2) do
    case DateTime.compare(dt1, dt2) do
      :gt -> dt1
      _ -> dt2
    end
  end
end
