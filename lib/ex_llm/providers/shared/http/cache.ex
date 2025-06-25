defmodule ExLLM.Providers.Shared.HTTP.Cache do
  @moduledoc """
  Tesla middleware for HTTP response caching.

  This middleware provides intelligent caching of HTTP responses to improve
  performance and reduce API costs. It supports multiple cache backends,
  TTL-based expiration, and cache invalidation strategies.

  ## Features

  - Memory and disk-based caching
  - Configurable TTL (Time To Live)
  - Automatic cache key generation based on request
  - Support for cache headers (ETag, Last-Modified)
  - Test-friendly cache isolation

  ## Usage

      middleware = [
        {HTTP.Cache, ttl: 300_000, backend: :memory}
      ]
      
      client = Tesla.client(middleware)

  ## Cache Key Generation

  Cache keys are generated from:
  - HTTP method and URL
  - Request body (for POST/PUT)
  - Relevant headers
  - Provider context
  """

  @behaviour Tesla.Middleware

  alias ExLLM.Infrastructure.Logger

  # Default cache TTL (5 minutes)
  @default_ttl 300_000

  # Cache backends
  @memory_cache __MODULE__.Memory
  @disk_cache __MODULE__.Disk

  @impl Tesla.Middleware
  def call(env, next, opts) do
    if cache_enabled?(opts) do
      cache_key = generate_cache_key(env, opts)
      ttl = Keyword.get(opts, :ttl, @default_ttl)
      backend = get_cache_backend(opts)

      case get_cached_response(backend, cache_key, ttl) do
        {:hit, cached_response} ->
          Logger.debug("Cache hit for key: #{cache_key}")
          add_cache_headers(cached_response, :hit)

        :miss ->
          Logger.debug("Cache miss for key: #{cache_key}")

          env
          |> Tesla.run(next)
          |> handle_response(backend, cache_key, ttl, opts)
      end
    else
      Tesla.run(env, next)
    end
  end

  # Cache key generation

  defp generate_cache_key(env, opts) do
    key_components = [
      env.method,
      normalize_url(env.url),
      normalize_body(env.body),
      extract_relevant_headers(env.headers, opts),
      Keyword.get(opts, :key_prefix, "http")
    ]

    key_components
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_url(url) do
    # Remove query parameters that don't affect caching
    uri = URI.parse(url)

    %{uri | query: normalize_query(uri.query)}
    |> URI.to_string()
  end

  defp normalize_query(nil), do: nil

  defp normalize_query(query) do
    query
    |> URI.decode_query()
    |> Enum.reject(fn {key, _value} ->
      # Remove timestamp and nonce parameters
      key in ["timestamp", "nonce", "_t", "cache_bust"]
    end)
    |> Enum.sort()
    |> URI.encode_query()
  end

  defp normalize_body(nil), do: nil

  defp normalize_body(body) when is_binary(body) do
    # Try to parse JSON and normalize
    case Jason.decode(body) do
      {:ok, parsed} -> normalize_json_body(parsed)
      {:error, _} -> body
    end
  end

  defp normalize_body(body) when is_map(body) do
    normalize_json_body(body)
  end

  defp normalize_body(body), do: body

  defp normalize_json_body(body) when is_map(body) do
    body
    |> Enum.reject(fn {key, _value} ->
      # Remove non-deterministic fields
      key in ["timestamp", "request_id", "trace_id"]
    end)
    |> Enum.sort()
    |> Jason.encode!()
  end

  defp extract_relevant_headers(headers, opts) do
    # Only include headers that affect response content
    relevant_headers =
      Keyword.get(opts, :cache_headers, [
        "accept",
        "content-type",
        "authorization",
        "x-api-key",
        "anthropic-version"
      ])

    headers
    |> Enum.filter(fn {name, _value} ->
      String.downcase(name) in relevant_headers
    end)
    |> Enum.sort()
  end

  # Cache operations

  defp get_cached_response(backend, cache_key, ttl) do
    case backend.get(cache_key) do
      {:ok, {response, timestamp}} ->
        if cache_expired?(timestamp, ttl) do
          backend.delete(cache_key)
          :miss
        else
          {:hit, response}
        end

      :error ->
        :miss
    end
  end

  defp cache_expired?(timestamp, ttl) do
    System.monotonic_time(:millisecond) - timestamp > ttl
  end

  defp handle_response({:ok, response} = result, backend, cache_key, ttl, opts) do
    if cacheable_response?(response, opts) do
      store_response(backend, cache_key, response, ttl)
      add_cache_headers(response, :miss)
    else
      result
    end
  end

  defp handle_response({:error, _} = error, _backend, _cache_key, _ttl, _opts) do
    error
  end

  defp store_response(backend, cache_key, response, _ttl) do
    timestamp = System.monotonic_time(:millisecond)
    backend.put(cache_key, {response, timestamp})
  end

  defp cacheable_response?(response, opts) do
    # Default: cache successful responses
    success_codes = Keyword.get(opts, :cache_success_codes, [200, 201])
    error_codes = Keyword.get(opts, :cache_error_codes, [])

    response.status in success_codes or response.status in error_codes
  end

  defp add_cache_headers(response, cache_status) do
    cache_header =
      case cache_status do
        :hit -> "HIT"
        :miss -> "MISS"
      end

    headers = [{"x-cache", cache_header} | response.headers]
    %{response | headers: headers}
  end

  # Cache backend selection

  defp get_cache_backend(opts) do
    case Keyword.get(opts, :backend, :memory) do
      :memory -> @memory_cache
      :disk -> @disk_cache
      custom when is_atom(custom) -> custom
    end
  end

  defp cache_enabled?(opts) do
    Keyword.get(opts, :enabled, true)
  end

  # Cache invalidation

  @doc """
  Clear all cached responses.
  """
  @spec clear_cache(atom()) :: :ok
  def clear_cache(backend \\ :memory) do
    cache_backend =
      case backend do
        :memory -> @memory_cache
        :disk -> @disk_cache
        custom -> custom
      end

    cache_backend.clear()
  end

  @doc """
  Clear cached response for a specific key.
  """
  @spec invalidate(String.t(), atom()) :: :ok
  def invalidate(cache_key, backend \\ :memory) do
    cache_backend =
      case backend do
        :memory -> @memory_cache
        :disk -> @disk_cache
        custom -> custom
      end

    cache_backend.delete(cache_key)
  end

  @doc """
  Get cache statistics.
  """
  @spec stats(atom()) :: map()
  def stats(backend \\ :memory) do
    cache_backend =
      case backend do
        :memory -> @memory_cache
        :disk -> @disk_cache
        custom -> custom
      end

    if function_exported?(cache_backend, :stats, 0) do
      cache_backend.stats()
    else
      %{backend: backend, stats_available: false}
    end
  end
end

defmodule ExLLM.Providers.Shared.HTTP.Cache.Memory do
  @moduledoc """
  In-memory cache backend using ETS.
  """

  @table_name :ex_llm_http_cache

  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  rescue
    ArgumentError ->
      init_table()
      :error
  end

  def put(key, value) do
    init_table()
    :ets.insert(@table_name, {key, value})
    :ok
  end

  def delete(key) do
    init_table()
    :ets.delete(@table_name, key)
    :ok
  end

  def clear do
    init_table()
    :ets.delete_all_objects(@table_name)
    :ok
  end

  def stats do
    init_table()
    size = :ets.info(@table_name, :size)
    memory = :ets.info(@table_name, :memory)

    %{
      backend: :memory,
      size: size,
      memory_words: memory,
      memory_bytes: memory * :erlang.system_info(:wordsize)
    }
  end

  defp init_table do
    unless :ets.whereis(@table_name) != :undefined do
      :ets.new(@table_name, [:named_table, :public, :set, {:read_concurrency, true}])
    end
  end
end

defmodule ExLLM.Providers.Shared.HTTP.Cache.Disk do
  @moduledoc """
  Disk-based cache backend using file system.
  """

  @cache_dir Path.join([System.tmp_dir!(), "ex_llm_cache"])

  def get(key) do
    cache_file = cache_file_path(key)

    case File.read(cache_file) do
      {:ok, binary} ->
        try do
          {:ok, :erlang.binary_to_term(binary)}
        rescue
          ArgumentError -> :error
        end

      {:error, _} ->
        :error
    end
  end

  def put(key, value) do
    cache_file = cache_file_path(key)
    File.mkdir_p!(Path.dirname(cache_file))

    binary = :erlang.term_to_binary(value)
    File.write!(cache_file, binary)
    :ok
  end

  def delete(key) do
    cache_file = cache_file_path(key)
    File.rm(cache_file)
    :ok
  end

  def clear do
    if File.exists?(@cache_dir) do
      File.rm_rf!(@cache_dir)
    end

    :ok
  end

  def stats do
    if File.exists?(@cache_dir) do
      files =
        Path.wildcard(Path.join(@cache_dir, "**/*"))
        |> Enum.filter(&File.regular?/1)

      total_size =
        Enum.reduce(files, 0, fn file, acc ->
          acc + File.stat!(file).size
        end)

      %{
        backend: :disk,
        files: length(files),
        total_size_bytes: total_size,
        cache_dir: @cache_dir
      }
    else
      %{
        backend: :disk,
        files: 0,
        total_size_bytes: 0,
        cache_dir: @cache_dir
      }
    end
  end

  defp cache_file_path(key) do
    # Create subdirectories based on key prefix to avoid too many files in one dir
    prefix = String.slice(key, 0, 2)
    Path.join([@cache_dir, prefix, key])
  end
end
