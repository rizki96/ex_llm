defmodule ExLLM.Tesla.ClientCache do
  @moduledoc """
  Caches Tesla clients to avoid reconstructing middleware on every request.

  This module provides an ETS-based cache for Tesla clients, keyed by provider
  and configuration. This significantly improves performance by reusing existing
  clients instead of rebuilding the middleware stack for each request.

  ## Architecture

  The cache uses ETS for fast concurrent reads with minimal contention. Clients
  are cached based on a composite key of provider and relevant configuration options
  that affect the middleware stack.

  ## Usage

      # Get or create a cached client
      client = ClientCache.get_or_create(:openai, config, fn ->
        # Client creation function - only called if not cached
        build_tesla_client(config)
      end)

  ## Cache Invalidation

  Clients are cached indefinitely within the application lifecycle. If configuration
  changes require new clients, the application should be restarted or the cache
  cleared manually.
  """

  use GenServer
  require Logger

  @table_name :ex_llm_tesla_client_cache
  @lock_table_name :ex_llm_tesla_client_cache_locks
  @server_name __MODULE__

  # Client API

  @doc """
  Starts the client cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @server_name)
  end

  @doc """
  Gets a cached client or creates one using the provided function.

  ## Parameters
  - `provider` - The provider atom (e.g., :openai, :anthropic)
  - `config` - Configuration map that affects middleware
  - `create_fn` - Function to create the client if not cached

  ## Returns
  The Tesla client, either from cache or newly created.
  """
  @spec get_or_create(atom(), map(), function()) :: Tesla.Client.t()
  def get_or_create(provider, config, create_fn) when is_function(create_fn, 0) do
    key = build_cache_key(provider, config)

    case :ets.lookup(@table_name, key) do
      [{^key, client}] ->
        Logger.debug("ClientCache: Cache hit for #{provider}")
        client

      [] ->
        # Use a lock to ensure only one process creates the client
        lock_key = {:lock, key}
        
        case :ets.insert_new(@lock_table_name, {lock_key, self()}) do
          true ->
            # We got the lock, create the client
            Logger.debug("ClientCache: Cache miss for #{provider}, creating new client")
            client = create_fn.()
            
            # Insert into cache and remove lock
            :ets.insert(@table_name, {key, client})
            :ets.delete(@lock_table_name, lock_key)
            client
            
          false ->
            # Another process has the lock, wait for them to finish
            # Small delay to let the other process complete
            Process.sleep(1)
            
            # Try to get from cache again
            case :ets.lookup(@table_name, key) do
              [{^key, client}] ->
                Logger.debug("ClientCache: Found client after waiting")
                client
              [] ->
                # Still not there, recursively try again
                get_or_create(provider, config, create_fn)
            end
        end
    end
  end

  @doc """
  Clears all cached clients.
  """
  def clear_cache do
    GenServer.call(@server_name, :clear_cache)
  end

  @doc """
  Gets cache statistics.
  """
  def stats do
    GenServer.call(@server_name, :stats)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS table with read concurrency for performance
    table = :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    # Create lock table for concurrent access control
    lock_table = :ets.new(@lock_table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{table: table, lock_table: lock_table}}
  end

  @impl true
  def handle_call(:clear_cache, _from, state) do
    :ets.delete_all_objects(@table_name)
    :ets.delete_all_objects(@lock_table_name)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      size: :ets.info(@table_name, :size),
      memory: :ets.info(@table_name, :memory)
    }
    {:reply, stats, state}
  end

  # Private functions

  @doc false
  # Builds a cache key from provider and relevant config options.
  # Only includes config that affects middleware construction.
  defp build_cache_key(provider, config) do
    # Extract only the config keys that affect middleware
    relevant_config = %{
      api_key: config[:api_key],
      base_url: config[:base_url],
      organization: config[:organization],
      project: config[:project],
      anthropic_version: config[:anthropic_version],
      site_url: config[:site_url],
      app_name: config[:app_name],
      
      # Middleware-affecting options
      is_streaming: config[:is_streaming] || config[:stream] || config[:streaming],
      timeout: config[:timeout],
      retry_delay: config[:retry_delay],
      retry_attempts: config[:retry_attempts],
      max_retry_delay: config[:max_retry_delay],
      circuit_breaker_timeout: config[:circuit_breaker_timeout],
      debug: config[:debug],
      compression: config[:compression],
      
      # OAuth token for Gemini
      oauth_token: config[:oauth_token]
    }
    
    # Remove nil values to ensure consistent hashing
    relevant_config = 
      relevant_config
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    # Create a stable hash of the configuration
    config_hash = :erlang.phash2(relevant_config)
    
    {provider, config_hash}
  end
end