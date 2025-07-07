defmodule ExLLM.Cache.StrategyTest do
  use ExUnit.Case, async: false

  alias ExLLM.Cache.Strategies.{Production, Test}
  alias ExLLM.Infrastructure.Cache

  setup do
    # Ensure cache is started for tests
    case GenServer.whereis(Cache) do
      nil ->
        # Start the cache if not already running
        {:ok, _pid} = Cache.start_link([])
        :ok

      _pid ->
        # Cache already running
        :ok
    end
  end

  describe "cache strategy pattern" do
    test "production strategy uses ETS cache when caching is enabled" do
      # Clear cache to ensure clean test state
      Cache.clear()

      cache_key = "test_key_#{System.unique_integer()}"

      # Function that returns a unique value each time
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:ok, %{value: :counters.get(counter, 1)}}
      end

      # First call should execute function
      result1 = Production.with_cache(cache_key, [cache: true], fun)
      assert {:ok, %{value: 1}} = result1

      # Second call should return cached value
      result2 = Production.with_cache(cache_key, [cache: true], fun)
      # Same value, function not called again
      assert {:ok, %{value: 1}} = result2

      # Cleanup
      Cache.delete(cache_key)
    end

    test "production strategy bypasses cache when caching is disabled" do
      cache_key = "test_key_#{System.unique_integer()}"

      # Function that returns a unique value each time
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:ok, %{value: :counters.get(counter, 1)}}
      end

      # Both calls should execute function
      result1 = Production.with_cache(cache_key, [cache: false], fun)
      assert {:ok, %{value: 1}} = result1

      result2 = Production.with_cache(cache_key, [cache: false], fun)
      # Different value, function called again
      assert {:ok, %{value: 2}} = result2
    end

    test "test strategy falls back to production when test caching is not enabled" do
      # Since we're not in a :live_api test, test caching should be disabled
      cache_key = "test_key_#{System.unique_integer()}"

      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:ok, %{value: :counters.get(counter, 1)}}
      end

      # Should behave like production strategy
      result1 = Test.with_cache(cache_key, [cache: true], fun)
      assert {:ok, %{value: 1}} = result1

      # Small delay to ensure async cache put completes
      Process.sleep(10)

      result2 = Test.with_cache(cache_key, [cache: true], fun)
      # Cached value
      assert {:ok, %{value: 1}} = result2

      # Cleanup
      Cache.delete(cache_key)
    end

    test "cache strategy can be configured" do
      # Get the current strategy
      current_strategy = Application.get_env(:ex_llm, :cache_strategy, Production)

      # The strategy should be configurable (either Test or Production is valid)
      assert current_strategy in [ExLLM.Cache.Strategies.Test, ExLLM.Cache.Strategies.Production]

      # Temporarily set to Test strategy
      Application.put_env(:ex_llm, :cache_strategy, ExLLM.Cache.Strategies.Test)
      assert Application.get_env(:ex_llm, :cache_strategy) == ExLLM.Cache.Strategies.Test

      # Restore original
      Application.put_env(:ex_llm, :cache_strategy, current_strategy)
    end

    test "strategy pattern eliminates layering violation" do
      # Production code (Infrastructure.Cache) should not directly reference test code
      # This is now handled through the strategy pattern

      # Get the source of Infrastructure.Cache
      {:ok, source} = File.read("lib/ex_llm/infrastructure/cache.ex")

      # Should not contain direct references to test modules
      refute source =~ "TestCacheDetector"
      refute source =~ "Testing.TestCacheDetector"

      # Should use strategy pattern instead
      assert source =~ "cache_strategy"
      assert source =~ "strategy.with_cache"
    end
  end
end
