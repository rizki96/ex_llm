defmodule ExLLM.Streaming.FlowController do
  @moduledoc """
  Advanced flow control for streaming LLM responses.

  This GenServer manages the flow of chunks between fast producers (LLM APIs)
  and potentially slow consumers (terminals, network connections). It provides
  backpressure, rate limiting, and graceful degradation under load.

  ## Features

  - Producer/consumer pattern with async processing
  - Automatic backpressure when consumers fall behind
  - Configurable buffer thresholds
  - Comprehensive metrics tracking
  - Graceful error handling

  ## Architecture

  The FlowController sits between the streaming source and the consumer:

      LLM API -> FlowController -> Consumer Callback
                     |
                     +-> Buffer (with backpressure)
                     +-> Metrics
                     +-> Rate Limiting

  ## Example

      # Start a flow controller
      {:ok, controller} = FlowController.start_link(
        consumer: callback_fn,
        buffer_capacity: 100,
        backpressure_threshold: 0.8
      )

      # Feed chunks
      FlowController.push_chunk(controller, chunk)

      # Get metrics
      metrics = FlowController.get_metrics(controller)
  """

  use GenServer
  require Logger

  alias ExLLM.Streaming.{StreamBuffer, ChunkBatcher}
  alias ExLLM.Types

  @default_buffer_capacity 100
  @default_backpressure_threshold 0.8
  @default_rate_limit_ms 1
  @metrics_report_interval 1_000

  defmodule State do
    @moduledoc false
    @enforce_keys [:consumer, :buffer]
    defstruct [
      :consumer,
      :buffer,
      :batcher,
      :config,
      :metrics,
      :status,
      :consumer_task,
      :last_push_time,
      :metrics_timer
    ]
  end

  defmodule Metrics do
    @moduledoc false
    defstruct chunks_received: 0,
              chunks_delivered: 0,
              chunks_dropped: 0,
              bytes_received: 0,
              bytes_delivered: 0,
              backpressure_events: 0,
              consumer_errors: 0,
              average_latency_ms: 0.0,
              current_buffer_size: 0,
              max_buffer_size: 0,
              start_time: nil,
              last_report_time: nil
  end

  # Client API

  @doc """
  Starts a flow controller.

  ## Options

  - `:consumer` - Consumer callback function (required)
  - `:buffer_capacity` - Maximum buffer size (default: 100)
  - `:backpressure_threshold` - Buffer fill ratio to trigger backpressure (default: 0.8)
  - `:rate_limit_ms` - Minimum time between chunks in ms (default: 1)
  - `:overflow_strategy` - Buffer overflow strategy (default: :drop)
  - `:batch_config` - Chunk batching configuration (optional)
  - `:on_metrics` - Callback for metrics reports (optional)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    # Validate consumer is provided before starting GenServer
    unless Keyword.has_key?(opts, :consumer) do
      raise KeyError, key: :consumer, term: opts
    end

    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Pushes a chunk to the flow controller.

  Returns `:ok` or `{:error, :backpressure}` if backpressure is active.
  """
  @spec push_chunk(GenServer.server(), Types.StreamChunk.t()) :: :ok | {:error, :backpressure}
  def push_chunk(controller, chunk) do
    GenServer.call(controller, {:push_chunk, chunk}, 5_000)
  end

  @doc """
  Signals that the stream is complete.
  """
  @spec complete_stream(GenServer.server()) :: :ok
  def complete_stream(controller) do
    GenServer.call(controller, :complete_stream, 10_000)
  end

  @doc """
  Gets current metrics from the flow controller.
  """
  @spec get_metrics(GenServer.server()) :: Metrics.t()
  def get_metrics(controller) do
    GenServer.call(controller, :get_metrics)
  end

  @doc """
  Gets the current status of the flow controller.
  """
  @spec get_status(GenServer.server()) :: map()
  def get_status(controller) do
    GenServer.call(controller, :get_status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    consumer = Keyword.fetch!(opts, :consumer)

    config = %{
      buffer_capacity: Keyword.get(opts, :buffer_capacity, @default_buffer_capacity),
      backpressure_threshold:
        Keyword.get(opts, :backpressure_threshold, @default_backpressure_threshold),
      rate_limit_ms: Keyword.get(opts, :rate_limit_ms, @default_rate_limit_ms),
      overflow_strategy: Keyword.get(opts, :overflow_strategy, :drop),
      batch_config: Keyword.get(opts, :batch_config),
      on_metrics: Keyword.get(opts, :on_metrics)
    }

    buffer = StreamBuffer.new(config.buffer_capacity, overflow_strategy: config.overflow_strategy)

    batcher =
      if config.batch_config do
        {:ok, batcher_pid} = ChunkBatcher.start_link(config.batch_config)
        batcher_pid
      else
        nil
      end

    metrics_timer =
      if config.on_metrics do
        Process.send_after(self(), :report_metrics, @metrics_report_interval)
      else
        nil
      end

    now = System.monotonic_time(:millisecond)

    state = %State{
      consumer: consumer,
      buffer: buffer,
      batcher: batcher,
      config: config,
      metrics: %Metrics{start_time: now},
      status: :running,
      last_push_time: now,
      metrics_timer: metrics_timer,
      consumer_task: nil
    }

    # Start consumer task for async processing (except when using batcher)
    state =
      if batcher do
        # Batcher handles async processing, so no consumer task needed
        state
      else
        # Start consumer task for backpressure support
        start_consumer_task(state)
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:push_chunk, chunk}, _from, state) do
    # Check rate limiting
    now = System.monotonic_time(:millisecond)
    time_since_last = now - state.last_push_time

    if time_since_last < state.config.rate_limit_ms do
      Process.sleep(state.config.rate_limit_ms - time_since_last)
    end

    # Check backpressure
    if should_apply_backpressure?(state) do
      state = update_metrics(state, :backpressure_events, 1)
      {:reply, {:error, :backpressure}, state}
    else
      # Add to buffer
      case StreamBuffer.push(state.buffer, chunk) do
        {:ok, new_buffer} ->
          state = %{state | buffer: new_buffer, last_push_time: now}
          state = update_chunk_metrics(state, chunk, :received)

          # When batcher is configured, process chunks immediately to ensure batches can complete
          # Otherwise, let the consumer task handle processing to enable backpressure
          state =
            if state.batcher do
              fill_ratio = StreamBuffer.fill_percentage(new_buffer) / 100.0

              if fill_ratio < state.config.backpressure_threshold do
                process_all_chunks(state)
              else
                state
              end
            else
              # Notify consumer task of new chunks
              if state.consumer_task do
                send(state.consumer_task, :chunks_available)
              end

              state
            end

          {:reply, :ok, state}

        {:overflow, new_buffer} ->
          state = %{state | buffer: new_buffer}
          state = update_metrics(state, :chunks_dropped, 1)
          {:reply, :ok, state}
      end
    end
  end

  @impl true
  def handle_call(:complete_stream, _from, state) do
    Logger.debug("Flow controller completing stream")

    # Mark as completing
    state = %{state | status: :completing}

    # Process any remaining chunks in buffer
    state = process_buffer_sync(state)

    # Stop batcher if present
    if state.batcher do
      ChunkBatcher.stop(state.batcher)
    end

    {:reply, :ok, %{state | status: :completed}}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = calculate_current_metrics(state)
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      status: state.status,
      buffer_size: StreamBuffer.size(state.buffer),
      buffer_fill_percentage: StreamBuffer.fill_percentage(state.buffer),
      # Consumer is always active in sync mode
      consumer_active: state.status == :running,
      metrics: calculate_current_metrics(state)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:pop_chunk, _from, state) do
    case StreamBuffer.pop(state.buffer) do
      {:ok, chunk, new_buffer} ->
        state = %{state | buffer: new_buffer}
        state = update_chunk_metrics(state, chunk, :delivered)
        {:reply, {:ok, chunk}, state}

      {:empty, _} ->
        {:reply, :empty, state}
    end
  end

  @impl true
  def handle_info({:pop_chunk_request, consumer_pid}, state) do
    case StreamBuffer.pop(state.buffer) do
      {:ok, chunk, new_buffer} ->
        state = %{state | buffer: new_buffer}
        state = update_chunk_metrics(state, chunk, :delivered)
        send(consumer_pid, {:pop_chunk_response, {:ok, chunk}})
        {:noreply, state}

      {:empty, _} ->
        send(consumer_pid, {:pop_chunk_response, :empty})
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:consumer_error, state) do
    # Consumer task reported an error
    state = update_metrics(state, :consumer_errors, 1)
    {:noreply, state}
  end

  @impl true
  def handle_info(:consumer_task_done, state) do
    # Consumer task finished
    {:noreply, %{state | consumer_task: nil}}
  end

  @impl true
  def handle_info(:report_metrics, state) do
    if state.config.on_metrics do
      metrics = calculate_current_metrics(state)
      state.config.on_metrics.(metrics)

      # Schedule next report
      timer = Process.send_after(self(), :report_metrics, @metrics_report_interval)
      {:noreply, %{state | metrics_timer: timer}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _, :process, pid, reason}, state) do
    if pid == state.consumer_task do
      Logger.warning("Consumer task died: #{inspect(reason)}")
      state = update_metrics(state, :consumer_errors, 1)

      # Restart if still running
      if state.status == :running do
        state = start_consumer_task(state)
        {:noreply, state}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp start_consumer_task(state) do
    parent = self()
    consumer = state.consumer
    batcher = state.batcher

    task =
      spawn_link(fn ->
        consumer_loop(parent, consumer, batcher)
      end)

    %{state | consumer_task: task}
  end

  defp consumer_loop(parent, consumer, batcher) do
    receive do
      :chunks_available ->
        process_available_chunks(parent, consumer, batcher)
        consumer_loop(parent, consumer, batcher)

      :stop ->
        # Final drain
        process_available_chunks(parent, consumer, batcher)
        send(parent, :consumer_task_done)
    after
      100 ->
        # Periodic check for chunks
        process_available_chunks(parent, consumer, batcher)
        consumer_loop(parent, consumer, batcher)
    end
  end

  defp process_available_chunks(parent, consumer, batcher) do
    # Process chunks in a loop to avoid stack overflow
    process_chunks_loop(parent, consumer, batcher)
  end

  defp process_chunks_loop(parent, consumer, batcher) do
    send(parent, {:pop_chunk_request, self()})

    receive do
      {:pop_chunk_response, {:ok, chunk}} ->
        case deliver_chunk(chunk, consumer, batcher) do
          :ok ->
            :ok

          {:error, _} ->
            send(parent, :consumer_error)
        end

        # Continue processing in tail-recursive manner
        process_chunks_loop(parent, consumer, batcher)

      {:pop_chunk_response, :empty} ->
        :ok
    after
      50 -> :ok
    end
  catch
    :exit, _ -> :ok
  end

  defp process_buffer_sync(state) do
    case StreamBuffer.pop(state.buffer) do
      {:ok, chunk, new_buffer} ->
        state = %{state | buffer: new_buffer}

        # Deliver chunk and handle errors
        error_count = deliver_chunk_sync(chunk, state.consumer, state.batcher)
        state = update_chunk_metrics(state, chunk, :delivered)
        state = update_metrics(state, :consumer_errors, error_count)

        # Continue processing remaining chunks
        process_buffer_sync(state)

      {:empty, _} ->
        state
    end
  end

  defp process_one_chunk(state) do
    case StreamBuffer.pop(state.buffer) do
      {:ok, chunk, new_buffer} ->
        state = %{state | buffer: new_buffer}

        # Deliver chunk and handle errors
        error_count = deliver_chunk_sync(chunk, state.consumer, state.batcher)
        state = update_chunk_metrics(state, chunk, :delivered)
        state = update_metrics(state, :consumer_errors, error_count)

        state

      {:empty, _} ->
        state
    end
  end

  defp process_all_chunks(state) do
    case StreamBuffer.pop(state.buffer) do
      {:ok, chunk, new_buffer} ->
        state = %{state | buffer: new_buffer}

        # Deliver chunk and handle errors
        error_count = deliver_chunk_sync(chunk, state.consumer, state.batcher)
        state = update_chunk_metrics(state, chunk, :delivered)
        state = update_metrics(state, :consumer_errors, error_count)

        # Continue processing remaining chunks
        process_all_chunks(state)

      {:empty, _} ->
        state
    end
  end

  defp deliver_chunk_sync(chunk, consumer, nil) do
    # Direct delivery
    try do
      consumer.(chunk)
      # No errors
      0
    catch
      kind, reason ->
        Logger.error("Consumer callback error: #{kind} #{inspect(reason)}")
        # One error
        1
    end
  end

  defp deliver_chunk_sync(chunk, consumer, batcher) do
    # Deliver through batcher
    case ChunkBatcher.add_chunk(batcher, chunk) do
      {:batch_ready, chunks} ->
        try do
          Enum.each(chunks, consumer)
          # No errors
          0
        catch
          kind, reason ->
            Logger.error("Consumer callback error: #{kind} #{inspect(reason)}")
            # One error
            1
        end

      :ok ->
        # No errors
        0
    end
  end

  defp deliver_chunk(chunk, consumer, nil) do
    # Direct delivery
    try do
      consumer.(chunk)
      :ok
    catch
      kind, reason ->
        Logger.error("Consumer callback error: #{kind} #{inspect(reason)}")
        {:error, {kind, reason}}
    end
  end

  defp deliver_chunk(chunk, consumer, batcher) do
    # Deliver through batcher
    case ChunkBatcher.add_chunk(batcher, chunk) do
      {:batch_ready, chunks} ->
        try do
          Enum.each(chunks, consumer)
          :ok
        catch
          kind, reason ->
            Logger.error("Consumer callback error: #{kind} #{inspect(reason)}")
            {:error, {kind, reason}}
        end

      :ok ->
        :ok
    end
  end

  defp should_apply_backpressure?(state) do
    fill_ratio = StreamBuffer.fill_percentage(state.buffer) / 100.0
    fill_ratio >= state.config.backpressure_threshold
  end

  defp drain_buffer(state, timeout \\ 10_000) do
    start_time = System.monotonic_time(:millisecond)

    drain_loop(state, start_time, timeout)
  end

  defp drain_loop(state, start_time, timeout) do
    if StreamBuffer.empty?(state.buffer) do
      state
    else
      now = System.monotonic_time(:millisecond)
      elapsed = now - start_time

      if elapsed > timeout do
        Logger.warning(
          "Buffer drain timeout, #{StreamBuffer.size(state.buffer)} chunks remaining"
        )

        state
      else
        Process.sleep(50)
        drain_loop(state, start_time, timeout)
      end
    end
  end

  defp update_metrics(state, key, increment) do
    metrics = Map.update!(state.metrics, key, &(&1 + increment))
    %{state | metrics: metrics}
  end

  defp update_chunk_metrics(state, chunk, :received) do
    bytes = byte_size(chunk.content || "")

    metrics =
      state.metrics
      |> Map.update!(:chunks_received, &(&1 + 1))
      |> Map.update!(:bytes_received, &(&1 + bytes))
      |> Map.put(:current_buffer_size, StreamBuffer.size(state.buffer))
      |> Map.update!(:max_buffer_size, &max(&1, StreamBuffer.size(state.buffer)))

    %{state | metrics: metrics}
  end

  defp update_chunk_metrics(state, chunk, :delivered) do
    bytes = byte_size(chunk.content || "")

    metrics =
      state.metrics
      |> Map.update!(:chunks_delivered, &(&1 + 1))
      |> Map.update!(:bytes_delivered, &(&1 + bytes))
      |> Map.put(:current_buffer_size, StreamBuffer.size(state.buffer))

    %{state | metrics: metrics}
  end

  defp calculate_current_metrics(state) do
    now = System.monotonic_time(:millisecond)
    duration_ms = now - state.metrics.start_time

    throughput =
      if duration_ms > 0 do
        state.metrics.chunks_delivered * 1000 / duration_ms
      else
        0.0
      end

    Map.merge(state.metrics, %{
      throughput_chunks_per_sec: Float.round(throughput, 2),
      duration_ms: duration_ms,
      buffer_stats: StreamBuffer.stats(state.buffer)
    })
  end
end
