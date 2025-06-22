defmodule ExLLM.Cache.Strategies.Test do
  @moduledoc """
  Test-aware caching strategy with intelligent context detection.

  This strategy provides specialized caching behavior for test environments,
  enabling the powerful test cache system for integration tests while falling
  back to production caching for unit tests. It's a key component in achieving
  25x faster integration test runs.

  ## When This Strategy is Used

  - **Test environments** when configured in `config/test.exs`
  - **Integration tests** with `:live_api` tag
  - **Development** when capturing API responses for tests

  ## How It Works

  The strategy uses intelligent detection to determine the appropriate caching behavior:

  1. **Integration Tests** (`:live_api` tag + cache enabled):
     - Bypasses ETS cache entirely
     - Allows HTTP client-level caching
     - Stores responses on disk for reuse
     - Enables cross-test response sharing

  2. **Unit Tests** (no special tags):
     - Falls back to production strategy
     - Uses normal ETS caching
     - No disk persistence

  ## Configuration

  ### Basic Setup

      # config/test.exs
      config :ex_llm,
        cache_strategy: ExLLM.Cache.Strategies.Test

  ### Enabling Test Cache

      # For integration tests
      export EX_LLM_TEST_CACHE_ENABLED=true
      mix test --only live_api

      # Or in test setup
      System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")

  ## Features

  - **Smart Detection**: Automatically determines when to use test caching
  - **Fallback Support**: Seamlessly uses production cache for unit tests
  - **Zero Configuration**: Works out of the box with proper test tags
  - **Performance**: 25x faster integration test runs with cache hits

  ## Integration with Test System

  This strategy works in conjunction with:
  - `ExLLM.Testing.TestCacheDetector` - Detects test context
  - `ExLLM.Testing.TestResponseInterceptor` - HTTP-level caching
  - `ExLLM.Testing.LiveApiCacheStorage` - Disk persistence

  ## Example Usage

      defmodule MyIntegrationTest do
        use ExUnit.Case
        
        @tag :live_api
        test "calls real API (cached after first run)" do
          # First run: Makes real API call, saves to disk
          # Subsequent runs: Loads from disk cache
          {:ok, response} = ExLLM.chat(:openai, messages)
        end
      end

  ## Telemetry

  When test caching is active, emits:
  - `[:ex_llm, :test_cache, :hit]`
  - `[:ex_llm, :test_cache, :miss]`
  - `[:ex_llm, :test_cache, :save]`

  ## See Also

  - `ExLLM.Cache.Strategies.Production` - The fallback strategy
  - `ExLLM.Testing.TestCacheDetector` - Test context detection
  - [Caching Architecture Guide](docs/caching_architecture.md)
  """

  @behaviour ExLLM.Cache.Strategy

  alias ExLLM.Cache.Strategies.Production

  @impl ExLLM.Cache.Strategy
  def with_cache(cache_key, opts, fun) do
    if test_caching_enabled?() do
      # Defer to test cache system by just executing the function.
      # The test cache system will handle caching at the HTTP client level.
      fun.()
    else
      # Fallback to production strategy if test caching is not active for this context.
      Production.with_cache(cache_key, opts, fun)
    end
  end

  defp test_caching_enabled?() do
    # Check if test cache detector is available and test caching should be used.
    # This check is now properly isolated within the test strategy.
    if Code.ensure_loaded?(ExLLM.Testing.TestCacheDetector) do
      ExLLM.Testing.TestCacheDetector.should_cache_responses?()
    else
      false
    end
  end
end
