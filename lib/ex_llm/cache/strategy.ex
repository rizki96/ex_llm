defmodule ExLLM.Cache.Strategy do
  @moduledoc """
  Behavior defining the caching strategy interface for ExLLM.

  This behavior is the cornerstone of ExLLM's dual-cache architecture, enabling
  clean separation between production and test caching concerns through the
  strategy pattern. It eliminates architectural layering violations by allowing
  production code to remain unaware of test-specific implementations.

  For a complete understanding of the caching architecture, see the
  [Caching Architecture Guide](docs/caching_architecture.md).

  ## Purpose

  The strategy pattern serves several critical purposes:

  1. **Separation of Concerns**: Production code doesn't need to know about test caching
  2. **Flexibility**: Easy to add new caching strategies without modifying core code
  3. **Testability**: Test environments can use specialized caching behavior
  4. **Clean Architecture**: Eliminates circular dependencies between layers

  ## Built-in Strategies

  ExLLM provides two strategies out of the box:

  - `ExLLM.Cache.Strategies.Production` - ETS-based runtime caching
  - `ExLLM.Cache.Strategies.Test` - Test-aware caching with file persistence

  ## Implementing Custom Strategies

  To implement a custom caching strategy:

      defmodule MyApp.RedisCacheStrategy do
        @behaviour ExLLM.Cache.Strategy

        @impl true
        def with_cache(cache_key, opts, fun) do
          case Redis.get(cache_key) do
            {:ok, nil} ->
              # Cache miss - execute function
              result = fun.()
              ttl = Keyword.get(opts, :ttl, 3600)
              Redis.setex(cache_key, ttl, serialize(result))
              result

            {:ok, cached} ->
              # Cache hit
              deserialize(cached)
          end
        end
      end

  Then configure it:

      config :ex_llm,
        cache_strategy: MyApp.RedisCacheStrategy

  ## Strategy Interface

  The `with_cache/3` callback receives:

  - `cache_key` - A unique key for this cache entry
  - `opts` - Options including TTL, cache flags, etc.
  - `fun` - The function to execute if cache misses

  The strategy must decide whether to:
  1. Return a cached value
  2. Execute the function and cache the result
  3. Bypass caching entirely

  ## Configuration

  Set the cache strategy in your config:

      # config/prod.exs
      config :ex_llm,
        cache_strategy: ExLLM.Cache.Strategies.Production

      # config/test.exs  
      config :ex_llm,
        cache_strategy: ExLLM.Cache.Strategies.Test
  """

  @doc """
  Wraps a function execution with a caching layer.

  The strategy implementation decides whether to serve from cache or execute
  the function, and how to store results.

  ## Parameters

  - `cache_key` - Unique identifier for this cache entry
  - `opts` - Keyword list of options that may include:
    - `:ttl` - Time to live in milliseconds
    - `:cache` - Boolean indicating if caching is requested
    - Additional provider or request-specific options
  - `fun` - Zero-arity function to execute on cache miss

  ## Returns

  The result of either the cached value or the function execution.

  ## Examples

      def with_cache(cache_key, opts, fun) do
        if should_use_cache?(opts) do
          check_cache_and_execute(cache_key, opts, fun)
        else
          fun.()
        end
      end
  """
  @callback with_cache(cache_key :: String.t(), opts :: keyword(), fun :: (-> any())) :: any()
end
