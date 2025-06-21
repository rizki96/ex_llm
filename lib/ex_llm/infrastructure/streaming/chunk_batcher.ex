defmodule ExLLM.Infrastructure.Streaming.ChunkBatcher do
  @moduledoc """
  Intelligent chunk batching for optimized streaming output.

  This GenServer batches small chunks together to reduce I/O operations
  and provide smoother output, especially for terminals and slow consumers.

  ## Features

  - Configurable batch size and timeout
  - Adaptive batching based on chunk characteristics
  - Min/max batch size constraints
  - Performance metrics tracking

  ## Example

      # Start a batcher
      {:ok, batcher} = ChunkBatcher.start_link(
        batch_size: 5,
        batch_timeout_ms: 25,
        min_batch_size: 3
      )

      # Add chunks
      :ok = ChunkBatcher.add_chunk(batcher, chunk1)
      {:batch_ready, chunks} = ChunkBatcher.add_chunk(batcher, chunk2)

      # Force flush
      chunks = ChunkBatcher.flush(batcher)
  """

  use GenServer

  alias ExLLM.Types

  defmodule State do
    @moduledoc false
    @enforce_keys [:config]
    defstruct [
      :config,
      :current_batch,
      :batch_timer,
      :metrics,
      :adaptive_config
    ]
  end

  defmodule Config do
    @moduledoc false
    defstruct batch_size: 5,
              batch_timeout_ms: 25,
              min_batch_size: 1,
              max_batch_size: 20,
              adaptive: true,
              on_batch_ready: nil
  end

  defmodule Metrics do
    @moduledoc false
    defstruct batches_created: 0,
              chunks_batched: 0,
              forced_flushes: 0,
              timeout_flushes: 0,
              average_batch_size: 0.0,
              min_batch_size: nil,
              max_batch_size: nil,
              total_bytes: 0,
              start_time: nil
  end

  # Client API

  @doc """
  Starts a chunk batcher.

  ## Options

  - `:batch_size` - Target batch size (default: 5)
  - `:batch_timeout_ms` - Max time to wait for batch (default: 25ms)
  - `:min_batch_size` - Minimum chunks before batching (default: 1)
  - `:max_batch_size` - Maximum chunks per batch (default: 20)
  - `:adaptive` - Enable adaptive batching (default: true)
  - `:on_batch_ready` - Optional callback when batch is ready
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Adds a chunk to the batcher.

  Returns:
  - `:ok` - Chunk added, batch not ready
  - `{:batch_ready, chunks}` - Batch is ready for processing
  """
  @spec add_chunk(GenServer.server(), Types.StreamChunk.t()) ::
          :ok | {:batch_ready, [Types.StreamChunk.t()]}
  def add_chunk(batcher, chunk) do
    GenServer.call(batcher, {:add_chunk, chunk})
  end

  @doc """
  Forces a flush of the current batch.

  Returns the list of chunks in the batch (may be empty).
  """
  @spec flush(GenServer.server()) :: [Types.StreamChunk.t()]
  def flush(batcher) do
    GenServer.call(batcher, :flush)
  end

  @doc """
  Gets current metrics from the batcher.
  """
  @spec get_metrics(GenServer.server()) :: map()
  def get_metrics(batcher) do
    GenServer.call(batcher, :get_metrics)
  end

  @doc """
  Stops the batcher, returning any remaining chunks.
  """
  @spec stop(GenServer.server()) :: [Types.StreamChunk.t()]
  def stop(batcher) do
    GenServer.call(batcher, :stop)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = struct(Config, opts)

    state = %State{
      config: config,
      current_batch: [],
      metrics: %Metrics{start_time: System.monotonic_time(:millisecond)},
      adaptive_config: %{
        recent_chunk_sizes: [],
        recent_intervals: [],
        last_chunk_time: nil
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_chunk, chunk}, _from, state) do
    # Update metrics
    state = update_chunk_metrics(state, chunk)

    # Update adaptive config
    state = update_adaptive_config(state, chunk)

    # Add to batch
    new_batch = [chunk | state.current_batch]
    state = %{state | current_batch: new_batch}

    # Check if batch is ready
    if should_flush_batch?(state) do
      {batch, new_state} = flush_batch(state, :size_reached)
      {:reply, {:batch_ready, batch}, new_state}
    else
      # Start timer if this is the first chunk
      state = maybe_start_timer(state, length(new_batch))
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {batch, new_state} = flush_batch(state, :forced)
    {:reply, batch, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = calculate_metrics(state)
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {batch, _} = flush_batch(state, :stop)
    {:stop, :normal, batch, state}
  end

  @impl true
  def handle_info(:batch_timeout, state) do
    {_batch, new_state} = flush_batch(state, :timeout)

    # Call the callback if configured
    if state.config.on_batch_ready && length(state.current_batch) > 0 do
      _result = state.config.on_batch_ready.(Enum.reverse(state.current_batch))
    end

    {:noreply, new_state}
  end

  # Private functions

  defp should_flush_batch?(state) do
    batch_size = length(state.current_batch)
    config = get_effective_config(state)

    cond do
      # Reached max size
      batch_size >= config.max_batch_size -> true
      # Reached target size
      batch_size >= config.batch_size -> true
      # Check for special cases (e.g., end of stream markers)
      has_stream_end_marker?(state.current_batch) -> true
      # Otherwise, not ready
      true -> false
    end
  end

  defp has_stream_end_marker?(batch) do
    Enum.any?(batch, fn chunk ->
      chunk.finish_reason in ["stop", "complete", "end"]
    end)
  end

  defp maybe_start_timer(state, batch_size) do
    if batch_size == 1 && state.batch_timer == nil do
      config = get_effective_config(state)
      timer = Process.send_after(self(), :batch_timeout, config.batch_timeout_ms)
      %{state | batch_timer: timer}
    else
      state
    end
  end

  defp flush_batch(state, reason) do
    # Cancel timer if exists
    if state.batch_timer do
      Process.cancel_timer(state.batch_timer)
    end

    batch = Enum.reverse(state.current_batch)

    # Update metrics
    state =
      case reason do
        :forced -> update_metrics(state, :forced_flushes, 1)
        :timeout -> update_metrics(state, :timeout_flushes, 1)
        _ -> state
      end

    state =
      if length(batch) > 0 do
        update_batch_metrics(state, batch)
      else
        state
      end

    new_state = %{state | current_batch: [], batch_timer: nil}

    {batch, new_state}
  end

  defp get_effective_config(state) do
    if state.config.adaptive do
      adapt_config(state.config, state.adaptive_config)
    else
      state.config
    end
  end

  defp adapt_config(config, adaptive_data) do
    # Simple adaptive logic - can be enhanced
    avg_chunk_size = calculate_average(adaptive_data.recent_chunk_sizes)
    avg_interval = calculate_average(adaptive_data.recent_intervals)

    # Adjust batch size based on chunk characteristics
    adjusted_batch_size =
      cond do
        avg_chunk_size > 1000 -> max(config.batch_size - 2, config.min_batch_size)
        avg_chunk_size < 100 -> min(config.batch_size + 2, config.max_batch_size)
        true -> config.batch_size
      end

    # Adjust timeout based on arrival rate
    adjusted_timeout =
      cond do
        avg_interval < 10 -> config.batch_timeout_ms + 10
        avg_interval > 100 -> max(config.batch_timeout_ms - 10, 10)
        true -> config.batch_timeout_ms
      end

    %{config | batch_size: adjusted_batch_size, batch_timeout_ms: adjusted_timeout}
  end

  defp update_adaptive_config(state, chunk) do
    now = System.monotonic_time(:millisecond)
    chunk_size = byte_size(chunk.content || "")

    # Update chunk sizes (keep last 20)
    recent_sizes =
      [chunk_size | state.adaptive_config.recent_chunk_sizes]
      |> Enum.take(20)

    # Update intervals if we have a previous time
    recent_intervals =
      if state.adaptive_config.last_chunk_time do
        interval = now - state.adaptive_config.last_chunk_time
        [interval | state.adaptive_config.recent_intervals] |> Enum.take(20)
      else
        state.adaptive_config.recent_intervals
      end

    adaptive_config = %{
      recent_chunk_sizes: recent_sizes,
      recent_intervals: recent_intervals,
      last_chunk_time: now
    }

    %{state | adaptive_config: adaptive_config}
  end

  defp calculate_average([]), do: 0

  defp calculate_average(list) do
    Enum.sum(list) / length(list)
  end

  defp update_chunk_metrics(state, chunk) do
    bytes = byte_size(chunk.content || "")

    metrics =
      state.metrics
      |> Map.update!(:chunks_batched, &(&1 + 1))
      |> Map.update!(:total_bytes, &(&1 + bytes))

    %{state | metrics: metrics}
  end

  defp update_batch_metrics(state, batch) do
    batch_size = length(batch)

    metrics =
      state.metrics
      |> Map.update!(:batches_created, &(&1 + 1))
      |> update_min_max_batch_size(batch_size)

    %{state | metrics: metrics}
  end

  defp update_min_max_batch_size(metrics, size) do
    metrics
    |> Map.update!(:min_batch_size, fn
      nil -> size
      min -> min(min, size)
    end)
    |> Map.update!(:max_batch_size, fn
      nil -> size
      max -> max(max, size)
    end)
  end

  defp update_metrics(state, key, increment) do
    metrics = Map.update!(state.metrics, key, &(&1 + increment))
    %{state | metrics: metrics}
  end

  defp calculate_metrics(state) do
    metrics = state.metrics
    now = System.monotonic_time(:millisecond)
    duration_ms = now - metrics.start_time

    avg_batch_size =
      if metrics.batches_created > 0 do
        metrics.chunks_batched / metrics.batches_created
      else
        0.0
      end

    %{
      batches_created: metrics.batches_created,
      chunks_batched: metrics.chunks_batched,
      forced_flushes: metrics.forced_flushes,
      timeout_flushes: metrics.timeout_flushes,
      average_batch_size: Float.round(avg_batch_size, 2),
      min_batch_size: metrics.min_batch_size,
      max_batch_size: metrics.max_batch_size,
      total_bytes: metrics.total_bytes,
      duration_ms: duration_ms,
      current_batch_size: length(state.current_batch),
      throughput_chunks_per_sec: calculate_throughput(metrics.chunks_batched, duration_ms)
    }
  end

  defp calculate_throughput(count, duration_ms) when duration_ms > 0 do
    Float.round(count * 1000 / duration_ms, 2)
  end

  defp calculate_throughput(_, _), do: 0.0
end
