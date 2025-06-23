defmodule ExLLM.CacheTest do
  use ExUnit.Case, async: true

  alias ExLLM.Cache
  alias ExLLM.Infrastructure.Cache, as: ProdCache

  setup do
    # The Production cache strategy relies on this GenServer.
    # We need to ensure it's running for tests that fall back to it.
    start_supervised!(ProdCache)
    :ok
  end

  describe "with_cache/3" do
    test "with Test strategy, falls back to production strategy when test caching is disabled" do
      # This test verifies the core behavior of the Test strategy. When live API
      # test caching is not active, it should delegate to the Production strategy.
      # We confirm this by checking if the production ETS cache is being used.

      cache_key = "test_fallback_#{System.unique_integer()}"
      fun_was_called_flag = :fun_was_called

      # This function sends a message to the test process so we can track its execution.
      fun = fn ->
        send(self(), fun_was_called_flag)
        {:ok, "llm_response"}
      end

      # 1. First call: cache miss
      # The function should be executed, and the result should be cached by the production strategy.
      assert Cache.with_cache(cache_key, [cache: true], fun) == {:ok, "llm_response"}
      assert_receive ^fun_was_called_flag

      # Verify the item is in the production cache, proving the fallback worked.
      assert ProdCache.get(cache_key) == {:ok, "llm_response"}

      # 2. Second call: cache hit
      # The function should NOT be executed, and the result should come from the production cache.
      assert Cache.with_cache(cache_key, [cache: true], fun) == {:ok, "llm_response"}
      refute_receive ^fun_was_called_flag
    end
  end
end
