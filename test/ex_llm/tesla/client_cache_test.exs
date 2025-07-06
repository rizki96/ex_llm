defmodule ExLLM.Tesla.ClientCacheTest do
  use ExUnit.Case, async: false
  alias ExLLM.Tesla.ClientCache

  setup do
    # Clear cache before each test
    ClientCache.clear_cache()
    :ok
  end

  describe "get_or_create/3" do
    test "creates new client on cache miss" do
      create_count = :counters.new(1, [])

      create_fn = fn ->
        :counters.add(create_count, 1, 1)
        Tesla.client([], Tesla.Mock)
      end

      # First call should create
      client1 = ClientCache.get_or_create(:openai, %{api_key: "test"}, create_fn)
      assert :counters.get(create_count, 1) == 1

      # Second call with same config should use cache
      client2 = ClientCache.get_or_create(:openai, %{api_key: "test"}, create_fn)
      assert :counters.get(create_count, 1) == 1

      # Clients should be the same
      assert client1 == client2
    end

    test "creates different clients for different providers" do
      create_count = :counters.new(1, [])

      _client1 =
        ClientCache.get_or_create(:openai, %{api_key: "test"}, fn ->
          :counters.add(create_count, 1, 1)
          Tesla.client([], Tesla.Mock)
        end)

      _client2 =
        ClientCache.get_or_create(:anthropic, %{api_key: "test"}, fn ->
          :counters.add(create_count, 1, 1)
          Tesla.client([], Tesla.Mock)
        end)

      # Different providers should create new clients
      assert :counters.get(create_count, 1) == 2
    end

    test "creates different clients for different configs" do
      create_count = :counters.new(1, [])

      _client1 =
        ClientCache.get_or_create(:openai, %{api_key: "test1"}, fn ->
          :counters.add(create_count, 1, 1)
          Tesla.client([], Tesla.Mock)
        end)

      _client2 =
        ClientCache.get_or_create(:openai, %{api_key: "test2"}, fn ->
          :counters.add(create_count, 1, 1)
          Tesla.client([], Tesla.Mock)
        end)

      # Different configs should create new clients
      assert :counters.get(create_count, 1) == 2
    end

    test "caches based on relevant config only" do
      create_count = :counters.new(1, [])

      create_fn = fn ->
        :counters.add(create_count, 1, 1)
        Tesla.client([], Tesla.Mock)
      end

      # These should use the same cached client
      config1 = %{api_key: "test", irrelevant_key: "value1"}
      config2 = %{api_key: "test", irrelevant_key: "value2", another_irrelevant: true}

      ClientCache.get_or_create(:openai, config1, create_fn)
      ClientCache.get_or_create(:openai, config2, create_fn)

      # Should only create once since irrelevant keys don't affect cache
      assert :counters.get(create_count, 1) == 1
    end

    test "handles streaming flag in cache key" do
      create_count = :counters.new(1, [])

      create_fn = fn ->
        :counters.add(create_count, 1, 1)
        Tesla.client([], Tesla.Mock)
      end

      ClientCache.get_or_create(:openai, %{api_key: "test", is_streaming: true}, create_fn)
      ClientCache.get_or_create(:openai, %{api_key: "test", is_streaming: false}, create_fn)

      # Different streaming settings should create new clients
      assert :counters.get(create_count, 1) == 2
    end
  end

  describe "clear_cache/0" do
    test "removes all cached clients" do
      create_fn = fn -> Tesla.client([], Tesla.Mock) end

      # Create some cached clients
      ClientCache.get_or_create(:openai, %{api_key: "test1"}, create_fn)
      ClientCache.get_or_create(:anthropic, %{api_key: "test2"}, create_fn)

      # Verify cache has entries
      stats = ClientCache.stats()
      assert stats.size > 0

      # Clear cache
      ClientCache.clear_cache()

      # Verify cache is empty
      stats = ClientCache.stats()
      assert stats.size == 0
    end
  end

  describe "stats/0" do
    test "returns cache statistics" do
      stats = ClientCache.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :memory)
      assert is_integer(stats.size)
      assert is_integer(stats.memory)
    end

    test "size increases with cached clients" do
      create_fn = fn -> Tesla.client([], Tesla.Mock) end

      initial_stats = ClientCache.stats()
      initial_size = initial_stats.size

      ClientCache.get_or_create(:openai, %{api_key: "test"}, create_fn)

      new_stats = ClientCache.stats()
      assert new_stats.size == initial_size + 1
    end
  end

  describe "concurrent access" do
    test "handles concurrent cache access safely" do
      create_count = :counters.new(1, [])

      create_fn = fn ->
        # Add small delay to increase chance of race condition
        Process.sleep(10)
        :counters.add(create_count, 1, 1)
        Tesla.client([], Tesla.Mock)
      end

      # Spawn multiple processes trying to get the same client
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            ClientCache.get_or_create(:openai, %{api_key: "concurrent"}, create_fn)
          end)
        end

      # Wait for all tasks
      clients = Enum.map(tasks, &Task.await/1)

      # Should only create once despite concurrent access
      assert :counters.get(create_count, 1) == 1

      # All clients should be the same
      first_client = hd(clients)
      assert Enum.all?(clients, &(&1 == first_client))
    end
  end
end
