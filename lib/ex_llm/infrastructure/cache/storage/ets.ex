defmodule ExLLM.Infrastructure.Cache.Storage.ETS do
  @moduledoc """
  ETS-based storage backend for ExLLM cache.

  Provides fast in-memory caching with automatic expiration.
  """

  @behaviour ExLLM.Infrastructure.Cache.Storage

  defmodule State do
    @moduledoc false
    defstruct [:table, :name]
  end

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, :ex_llm_cache_storage)

    table_opts = [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ]

    table = :ets.new(name, table_opts)
    state = %State{table: table, name: name}

    {:ok, state}
  end

  @impl true
  def get(key, %State{table: table} = state) do
    case :ets.lookup(table, key) do
      [{^key, value, expires_at}] ->
        now = System.system_time(:millisecond)

        if expires_at > now do
          {:ok, value, state}
        else
          # Expired, delete it
          :ets.delete(table, key)
          {:miss, state}
        end

      [] ->
        {:miss, state}
    end
  end

  @impl true
  def put(key, value, expires_at, %State{table: table} = state) do
    :ets.insert(table, {key, value, expires_at})
    {:ok, state}
  end

  @impl true
  def delete(key, %State{table: table} = state) do
    :ets.delete(table, key)
    {:ok, state}
  end

  @impl true
  def clear(%State{table: table} = state) do
    :ets.delete_all_objects(table)
    {:ok, state}
  end

  @impl true
  def list_keys(pattern, %State{table: table} = state) do
    # Simple pattern matching for ETS
    # Pattern can be "*" for all or "prefix*" for prefix matching
    keys =
      if pattern == "*" do
        :ets.select(table, [{{:"$1", :_, :_}, [], [:"$1"]}])
      else
        prefix = String.trim_trailing(pattern, "*")

        :ets.select(table, [
          {{:"$1", :_, :_}, [{:>=, :"$1", prefix}, {:<, :"$1", prefix <> "~"}], [:"$1"]}
        ])
      end

    {:ok, keys, state}
  end

  @impl true
  def info(%State{table: table} = state) do
    info = %{
      size: :ets.info(table, :size),
      memory: :ets.info(table, :memory),
      type: :ets
    }

    {:ok, info, state}
  end
end
