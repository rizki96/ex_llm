defmodule ExLLM.Testing.TestCacheStrategy do
  @moduledoc false

  # Functions used in code paths that may be unreachable due to caching issues
  @compile {:nowarn_unused_function, [
    record_cache_hit: 2,
    record_cache_miss: 2,
    sanitize_response_for_storage: 1,
    sanitize_metadata_for_storage: 1
  ]}

  alias ExLLM.Infrastructure.Cache.Storage.TestCache
  alias ExLLM.Testing.TestCacheConfig
  alias ExLLM.Testing.TestCacheDetector
  alias ExLLM.Testing.TestCacheIndex
  alias ExLLM.Testing.TestCacheMatcher
  alias ExLLM.Testing.TestCacheTTL

  @type strategy_result ::
          {:cached, any(), map()}
          | {:proceed, map()}
          | {:error, term()}

  @type fallback_options :: %{
          allow_expired: boolean(),
          allow_errors: boolean(),
          allow_older_timestamps: boolean(),
          max_age_fallback: non_neg_integer() | :infinity
        }

  @doc """
  Execute cache-first strategy for a request.

  Flow:
  1. Check if test caching is enabled
  2. Generate cache key from request and test context
  3. Load cache index for the cache key
  4. Select best timestamp entry based on strategy
  5. If valid timestamp found: return cached response
  6. If no valid cache or expired: return proceed signal
  7. If real request fails: fallback to older timestamps if available
  """
  @spec execute(map(), keyword()) :: strategy_result()
  def execute(request, options \\ []) do
    # Check for explicit skip_cache option first
    skip_cache = Keyword.get(options, :skip_cache, false)

    if not skip_cache and TestCacheDetector.should_cache_responses?() do
      cache_key = generate_cache_key(request)
      fallback_opts = build_fallback_options(options)

      if Application.get_env(:ex_llm, :debug_test_cache, false) do
        IO.puts("Cache lookup for key: #{cache_key}")
      end

      case get_cached_response_internal(cache_key, request, fallback_opts) do
        {:ok, response, metadata} ->
          record_cache_hit(cache_key, metadata)
          {:cached, response, metadata}

        {:expired, response, metadata} ->
          if fallback_opts.allow_expired do
            record_cache_hit(cache_key, Map.put(metadata, :expired, true))
            {:cached, response, metadata}
          else
            record_cache_miss(cache_key, :expired)
            metadata = build_request_metadata(cache_key, request)
            {:proceed, Map.put(metadata, :cache_expired, true)}
          end

        {:fallback, response, metadata} ->
          record_cache_hit(cache_key, Map.put(metadata, :fallback, true))
          {:cached, response, metadata}

        :miss ->
          record_cache_miss(cache_key, :miss)
          metadata = build_request_metadata(cache_key, request)
          # Check if this is a miss due to expiry
          config = TestCacheConfig.get_config()
          cache_dir = Path.join(config.cache_dir, cache_key)
          # If cache dir exists but we got :miss, it's likely expired
          cache_expired = File.exists?(cache_dir)
          {:proceed, Map.put(metadata, :cache_expired, cache_expired)}

        {:error, reason} ->
          record_cache_miss(cache_key, {:error, reason})
          {:proceed, build_request_metadata(cache_key, request)}
      end
    else
      {:proceed, %{cache_key: nil}}
    end
  end

  @doc """
  Handle fallback when real request fails.
  """
  @spec handle_request_failure(map(), term(), keyword()) :: strategy_result()
  def handle_request_failure(request_metadata, failure_reason, options \\ []) do
    cache_key = Map.get(request_metadata, :cache_key)

    if cache_key do
      fallback_opts = %{
        allow_expired: true,
        allow_errors: Keyword.get(options, :allow_error_fallback, false),
        allow_older_timestamps: true,
        max_age_fallback: Keyword.get(options, :max_age_fallback, 30 * 24 * 60 * 60 * 1000)
      }

      case get_cached_response_internal(cache_key, request_metadata, fallback_opts) do
        {:ok, response, metadata} ->
          record_fallback_usage(cache_key, failure_reason, metadata)
          {:cached, response, Map.put(metadata, :fallback_reason, failure_reason)}

        {:expired, response, metadata} ->
          record_fallback_usage(cache_key, failure_reason, metadata)
          {:cached, response, Map.put(metadata, :fallback_reason, failure_reason)}

        {:fallback, response, metadata} ->
          record_fallback_usage(cache_key, failure_reason, metadata)
          {:cached, response, Map.put(metadata, :fallback_reason, failure_reason)}

        _ ->
          {:error, failure_reason}
      end
    else
      {:error, failure_reason}
    end
  end

  @doc """
  Warm cache for upcoming test scenarios.
  """
  @spec warm_cache([String.t()]) :: :ok | {:error, term()}
  def warm_cache(cache_patterns) do
    if TestCacheDetector.should_cache_responses?() do
      Enum.each(cache_patterns, &warm_cache_pattern/1)
      :ok
    else
      {:error, :caching_disabled}
    end
  end

  @doc """
  Get cache statistics for monitoring.
  """
  @spec get_cache_performance_stats() :: map()
  def get_cache_performance_stats do
    cache_keys = TestCache.list_cache_keys()

    total_stats =
      Enum.reduce(
        cache_keys,
        %{
          total_requests: 0,
          cache_hits: 0,
          cache_misses: 0,
          fallback_hits: 0,
          error_count: 0
        },
        fn cache_key, acc ->
          key_stats = TestCache.get_stats(cache_key)

          %{
            total_requests: acc.total_requests + get_stat(key_stats, :total_requests, 0),
            cache_hits: acc.cache_hits + get_stat(key_stats, :cache_hits, 0),
            cache_misses: acc.cache_misses + get_stat(key_stats, :cache_misses, 0),
            fallback_hits: acc.fallback_hits + get_stat(key_stats, :fallback_hits, 0),
            error_count: acc.error_count + get_stat(key_stats, :error_count, 0)
          }
        end
      )

    hit_rate =
      if total_stats.total_requests > 0 do
        total_stats.cache_hits / total_stats.total_requests
      else
        0.0
      end

    Map.put(total_stats, :hit_rate, hit_rate)
  end

  @doc """
  Check if cache warming is recommended for a test scenario.
  """
  @spec should_warm_cache?(String.t()) :: boolean()
  def should_warm_cache?(cache_pattern) do
    config = TestCacheConfig.get_config()

    if config.enabled do
      # Check if we have recent entries that might be expiring soon
      case TestCache.get_stats(cache_pattern) do
        %{newest_entry: newest} when not is_nil(newest) ->
          TestCacheTTL.should_warm_cache?(newest, config.ttl)

        # No cache entries, warming would be beneficial
        _ ->
          true
      end
    else
      false
    end
  end

  @doc """
  Invalidate cache entries matching a pattern.
  """
  @spec invalidate_cache(String.t() | :all) :: :ok | {:error, term()}
  def invalidate_cache(pattern) do
    TestCache.clear(pattern)
  end

  # Private functions

  defp get_cached_response_internal(cache_key, request, fallback_opts) do
    config = TestCacheConfig.get_config()
    cache_dir = Path.join(config.cache_dir, cache_key)

    if Application.get_env(:ex_llm, :debug_test_cache, false) do
      IO.puts("Checking cache dir: #{cache_dir}")
      IO.puts("Cache dir exists: #{File.exists?(cache_dir)}")
    end

    case File.exists?(cache_dir) do
      true ->
        # Load cache index and find best match
        index = TestCacheIndex.load_index(cache_dir)

        if Application.get_env(:ex_llm, :debug_test_cache, false) do
          IO.puts("Loaded index with #{length(index.entries)} entries")
        end

        # Get current test context for strategy
        test_context = TestCacheDetector.get_current_test_context()
        test_tags = get_test_tags(test_context)
        provider = extract_provider_from_cache_key(cache_key)

        # Calculate TTL and strategy
        ttl = TestCacheConfig.get_ttl(test_tags, provider)
        strategy = TestCacheConfig.get_fallback_strategy(test_tags)

        if Application.get_env(:ex_llm, :debug_test_cache, false) do
          IO.puts("TTL: #{ttl}, Strategy: #{strategy}")
        end

        # Try to find a match
        case select_best_cache_entry(cache_dir, index, request, ttl, strategy, fallback_opts) do
          {:ok, filename} ->
            load_cached_response(cache_dir, filename, :ok)

          {:expired, filename} ->
            load_cached_response(cache_dir, filename, :expired)

          {:fallback, filename} ->
            load_cached_response(cache_dir, filename, :fallback)

          :none ->
            :miss
        end

      false ->
        :miss
    end
  end

  defp select_best_cache_entry(cache_dir, index, request, ttl, strategy, fallback_opts) do
    # First try to select valid entries within TTL
    if Application.get_env(:ex_llm, :debug_test_cache, false) do
      IO.puts("Selecting cache entry from #{length(index.entries)} entries")
    end

    result = TestCacheTTL.select_cache_entry(cache_dir, ttl, strategy)

    if Application.get_env(:ex_llm, :debug_test_cache, false) do
      IO.puts("TestCacheTTL.select_cache_entry returned: #{inspect(result)}")
    end

    case result do
      {:ok, filename} ->
        {:ok, filename}

      {:expired, latest_filename} ->
        if fallback_opts.allow_expired do
          {:expired, latest_filename}
        else
          try_fallback_selection(index, request, fallback_opts)
        end

      :none ->
        try_fallback_selection(index, request, fallback_opts)
    end
  end

  defp try_fallback_selection(index, request, fallback_opts) do
    if fallback_opts.allow_older_timestamps do
      # Try to find any usable cached response
      cached_requests = build_cached_requests_from_index(index)

      case TestCacheMatcher.find_best_match(request, cached_requests, :comprehensive) do
        {:ok, cached_request} -> {:fallback, cached_request.filename}
        :miss -> :none
      end
    else
      :none
    end
  end

  defp load_cached_response(cache_dir, filename, status) do
    file_path = Path.join(cache_dir, filename)

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, entry_data} ->
            response_data = Map.get(entry_data, "response_data")
            metadata = build_response_metadata(entry_data, status)
            {status, response_data, metadata}

          {:error, reason} ->
            {:error, "Failed to parse cached response: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read cached file: #{inspect(reason)}"}
    end
  end

  defp build_response_metadata(entry_data, status) do
    %{
      cached_at: parse_datetime(Map.get(entry_data, "cached_at")),
      cache_version: Map.get(entry_data, "cache_version"),
      api_version: Map.get(entry_data, "api_version"),
      response_time_ms: get_in(entry_data, ["request_metadata", "response_time_ms"]) || 0,
      status: status,
      from_cache: true
    }
  end

  @doc """
  Generate cache key for a request.
  """
  @spec generate_cache_key(map()) :: String.t()
  def generate_cache_key(request) do
    url = Map.get(request, :url, "")
    _body = Map.get(request, :body, %{})
    _headers = Map.get(request, :headers, [])

    provider = extract_provider_from_url(url)
    endpoint = extract_endpoint_from_url(url)

    # Generate base cache key using test context
    base_key = TestCacheDetector.generate_cache_key(String.to_atom(provider), endpoint)

    # Add request signature for uniqueness
    request_signature = TestCacheMatcher.generate_request_signature(request)
    body_hash = hash_map(request_signature)

    "#{base_key}/#{body_hash}"
  end

  @doc """
  Build request metadata for tracking.
  """
  @spec build_request_metadata(String.t(), map()) :: map()
  def build_request_metadata(cache_key, request) do
    url = Map.get(request, :url, "")
    provider = extract_provider(url)
    endpoint = extract_endpoint_from_url(url)

    request_hash =
      hash_map(%{
        url: url,
        body: Map.get(request, :body, %{}),
        headers: normalize_headers_for_hash(Map.get(request, :headers, []))
      })

    %{
      cache_key: cache_key,
      url: url,
      body: Map.get(request, :body),
      headers: Map.get(request, :headers),
      method: Map.get(request, :method, "POST"),
      provider: provider,
      endpoint:
        case String.starts_with?(url, "https://") do
          true ->
            uri = URI.parse(url)
            uri.path || "/unknown"

          false ->
            "/" <> endpoint
        end,
      request_hash: request_hash,
      cache_expired: false,
      requested_at: DateTime.utc_now(),
      test_context:
        case TestCacheDetector.get_current_test_context() do
          {:ok, ctx} -> ctx
          :error -> nil
        end,
      should_save: true
    }
  end

  @doc """
  Save response to cache.
  """
  @spec save_response(map(), any(), map()) :: :ok | {:error, term()}
  def save_response(request, response, metadata) do
    cache_key = generate_cache_key(request)
    # Sanitize both response and metadata to avoid JSON encoding issues
    sanitized_response = sanitize_response_for_storage(response)
    sanitized_metadata = sanitize_metadata_for_storage(metadata)

    case TestCache.store(cache_key, sanitized_response, sanitized_metadata) do
      :ok -> :ok
      error -> error
    end
  end

  @doc """
  Get cached response if available.
  """
  @spec get_cached_response(String.t(), map(), keyword()) ::
          {:ok, any(), map()} | :miss | {:error, term()}
  def get_cached_response(cache_key, request, options \\ []) do
    fallback_opts = build_fallback_options(options)
    get_cached_response_internal(cache_key, request, fallback_opts)
  end

  @doc """
  Check if cache should be used for given options.
  """
  @spec should_use_cache?(keyword()) :: boolean()
  def should_use_cache?(options \\ []) do
    config = TestCacheConfig.get_config()

    config.enabled and TestCacheDetector.should_cache_responses?() and
      not Keyword.get(options, :skip_cache, false) and
      not Keyword.get(options, :force_refresh, false) and
      not (Keyword.get(options, :cache, true) == false) and
      not Keyword.get(options, :stream, false)
  end

  @doc """
  Normalize request for cache key generation.
  """
  @spec normalize_request_for_cache(map()) :: map()
  def normalize_request_for_cache(request) do
    normalized_headers =
      request
      |> Map.get(:headers, [])
      |> Enum.reject(fn {key, _} ->
        key_lower = String.downcase(key)
        key_lower in ["authorization", "x-api-key", "api-key", "user"]
      end)
      |> Enum.into(%{})

    normalized_body =
      request
      |> Map.get(:body, %{})
      |> Map.delete("user")

    request
    |> Map.put(:headers, normalized_headers)
    |> Map.put(:body, normalized_body)
  end

  defp build_fallback_options(options) do
    %{
      allow_expired: Keyword.get(options, :allow_expired, false),
      allow_errors: Keyword.get(options, :allow_errors, false),
      allow_older_timestamps: Keyword.get(options, :allow_older_timestamps, true),
      max_age_fallback: Keyword.get(options, :max_age_fallback, 30 * 24 * 60 * 60 * 1000)
    }
  end

  defp warm_cache_pattern(cache_pattern) do
    # This would implement cache warming logic
    # For now, we'll just check if the cache directory exists
    config = TestCacheConfig.get_config()
    cache_dir = Path.join(config.cache_dir, cache_pattern)

    if File.exists?(cache_dir) do
      # Could implement pre-loading or validation here
      :ok
    else
      # Pattern doesn't exist yet, nothing to warm
      :ok
    end
  end

  defp record_cache_hit(cache_key, metadata) do
    if Application.get_env(:ex_llm, :debug_test_cache, false) do
      status_info =
        case Map.get(metadata, :status) do
          :expired -> " (EXPIRED)"
          :fallback -> " (FALLBACK)"
          _ -> ""
        end

      IO.puts("Test cache HIT#{status_info}: #{cache_key}")
    end

    # Could update cache statistics here
    :ok
  end

  defp record_cache_miss(cache_key, reason) do
    if Application.get_env(:ex_llm, :debug_test_cache, false) do
      reason_str =
        case reason do
          :miss -> "no cache"
          :expired -> "expired"
          {:error, err} -> "error: #{inspect(err)}"
        end

      IO.puts("Test cache MISS (#{reason_str}): #{cache_key}")
    end

    # Could update cache statistics here
    :ok
  end

  defp record_fallback_usage(cache_key, failure_reason, _metadata) do
    if Application.get_env(:ex_llm, :debug_test_cache, false) do
      IO.puts("Test cache FALLBACK (request failed: #{inspect(failure_reason)}): #{cache_key}")
    end

    # Could update cache statistics here
    :ok
  end

  defp build_cached_requests_from_index(_index) do
    # This would build the cached request structures from index entries
    # For now, return empty list
    []
  end

  defp extract_provider_from_url(url) do
    cond do
      String.contains?(url, "api.anthropic.com") -> "anthropic"
      String.contains?(url, "api.openai.com") -> "openai"
      String.contains?(url, "generativelanguage.googleapis.com") -> "gemini"
      String.contains?(url, "api.groq.com") -> "groq"
      String.contains?(url, "openrouter.ai") -> "openrouter"
      String.contains?(url, "localhost") or String.contains?(url, "127.0.0.1") -> "ollama"
      true -> "unknown"
    end
  end

  defp extract_endpoint_from_url(url) do
    uri = URI.parse(url)

    case uri.path do
      nil ->
        "unknown"

      path ->
        path
        |> String.trim_leading("/")
        |> String.replace("/", "_")
        |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
        |> String.replace(~r/_+/, "_")
        |> String.trim("_")
    end
  end

  @doc """
  Extract provider from cache key or URL.
  """
  @spec extract_provider(String.t()) :: String.t()
  def extract_provider(url_or_cache_key) do
    if String.contains?(url_or_cache_key, "http") do
      extract_provider_from_url(url_or_cache_key) |> to_string()
    else
      url_or_cache_key
      |> String.split("/")
      |> List.first()
    end
  end

  defp extract_provider_from_cache_key(cache_key) do
    cache_key
    |> String.split("/")
    |> List.first()
    |> String.to_atom()
  end

  defp get_test_tags({:ok, context}), do: Map.get(context, :tags, [])
  defp get_test_tags(:error), do: []

  defp hash_map(data) when is_map(data) do
    case Jason.encode(data) do
      {:ok, json} ->
        :crypto.hash(:sha256, json)
        |> Base.encode16(case: :lower)
        |> String.slice(0..11)

      {:error, _} ->
        "unknown"
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

  defp get_stat(stats, key, default) do
    Map.get(stats, key, default)
  end

  defp sanitize_response_for_storage(response) when is_map(response) do
    response
    |> Enum.map(fn
      {key, headers} when key == :headers or key == "headers" ->
        sanitized_headers =
          headers
          |> Enum.map(fn
            {k, v} when is_tuple({k, v}) -> %{"name" => k, "value" => v}
            header -> header
          end)

        {key, sanitized_headers}

      {key, value} when is_pid(value) ->
        {key, inspect(value)}

      {key, value} when is_tuple(value) ->
        {key, Tuple.to_list(value)}

      {key, value} ->
        {key, value}
    end)
    |> Enum.into(%{})
  end

  defp sanitize_response_for_storage(response), do: response

  defp sanitize_metadata_for_storage(metadata) do
    deep_sanitize(metadata)
  end

  defp deep_sanitize(value) when is_pid(value), do: inspect(value)
  defp deep_sanitize(value) when is_tuple(value), do: Tuple.to_list(value) |> deep_sanitize()

  defp deep_sanitize(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {k, deep_sanitize(v)} end)
    |> Enum.into(%{})
  end

  defp deep_sanitize(value) when is_list(value) do
    Enum.map(value, &deep_sanitize/1)
  end

  defp deep_sanitize(value), do: value

  defp normalize_headers_for_hash(headers) when is_list(headers) do
    headers
    |> Enum.reject(fn {key, _} ->
      key_lower = String.downcase(key)
      key_lower in ["authorization", "x-api-key", "api-key", "user-agent"]
    end)
    |> Enum.into(%{})
  end

  defp normalize_headers_for_hash(headers), do: headers
end
