defmodule ExLLM.Providers.Shared.Streaming.Middleware.MetricsPlug do
  @moduledoc """
  Tesla middleware for collecting and reporting streaming metrics.

  This middleware provides comprehensive metrics collection for streaming operations,
  separating metrics concerns from the core streaming logic. It tracks performance
  metrics, provides configurable callbacks, and can be enabled/disabled via options.

  ## Features

  - **Performance Metrics**: Tracks bytes, chunks, timing, and throughput
  - **Error Tracking**: Monitors streaming errors and recovery attempts
  - **Configurable Callbacks**: Invoke custom handlers with metrics data
  - **Periodic Reporting**: Optional interval-based metrics updates
  - **Zero Overhead**: Can be completely disabled with no performance impact
  - **Provider-Aware**: Tracks metrics per provider for comparison

  ## Usage

  The middleware is automatically included when metrics are enabled:

  ```elixir
  client = Streaming.Engine.client(
    provider: :openai,
    api_key: "sk-...",
    enable_metrics: true
  )
  ```

  ## Configuration

  Configure via Tesla client options:

  ```elixir
  Tesla.client([
    {MetricsPlug, [
      enabled: true,
      callback: &MyApp.handle_metrics/1,
      interval: 1000,  # Report every second
      include_raw_data: false
    ]}
  ])
  ```

  ## Metrics Structure

  The middleware reports metrics in the following structure:

  ```elixir
  %{
    # Identification
    stream_id: "stream_123",
    provider: :openai,
    
    # Timing
    start_time: 1234567890,
    current_time: 1234567900,
    duration_ms: 10000,
    
    # Data volume
    bytes_received: 45678,
    chunks_received: 123,
    
    # Throughput
    bytes_per_second: 4567.8,
    chunks_per_second: 12.3,
    avg_chunk_size: 371.4,
    
    # Errors
    error_count: 0,
    last_error: nil,
    
    # Status
    status: :streaming,  # :streaming | :completed | :error
    
    # Optional raw data
    raw_chunks: [...]  # If include_raw_data is true
  }
  ```

  ## Callbacks

  Metrics callbacks receive the metrics map and can perform any action:

  ```elixir
  def handle_metrics(metrics) do
    Logger.info("Stream \#{metrics.stream_id}: \#{metrics.chunks_received} chunks")
    Telemetry.execute([:streaming, :metrics], metrics)
  end
  ```
  """

  @behaviour Tesla.Middleware

  alias ExLLM.Infrastructure.Logger

  # Default configuration
  # 1 second
  @default_interval 1000
  @default_enabled true

  @impl Tesla.Middleware
  def call(%Tesla.Env{opts: opts} = env, next, middleware_opts) do
    # Check if metrics are enabled
    enabled = get_option(opts, middleware_opts, :enabled, @default_enabled)

    if enabled do
      call_with_metrics(env, next, middleware_opts)
    else
      # Metrics disabled, pass through without overhead
      Tesla.run(env, next)
    end
  end

  defp call_with_metrics(%Tesla.Env{opts: opts} = env, next, middleware_opts) do
    stream_context = Keyword.get(opts, :stream_context)

    if stream_context do
      # This is a streaming request, set up metrics collection
      setup_metrics_collection(env, next, stream_context, middleware_opts)
    else
      # Not a streaming request, pass through
      Tesla.run(env, next)
    end
  end

  defp setup_metrics_collection(env, next, stream_context, middleware_opts) do
    stream_id = stream_context.stream_id
    callback = get_option(env.opts, middleware_opts, :callback)
    interval = get_option(env.opts, middleware_opts, :interval, @default_interval)
    include_raw = get_option(env.opts, middleware_opts, :include_raw_data, false)

    # Initialize metrics state
    metrics_state = %{
      # Identification
      stream_id: stream_id,
      provider: stream_context[:provider] || :unknown,

      # Timing
      start_time: System.system_time(:millisecond),
      last_report_time: System.system_time(:millisecond),

      # Data volume
      bytes_received: 0,
      chunks_received: 0,

      # Errors
      error_count: 0,
      last_error: nil,

      # Status
      status: :streaming,

      # Configuration
      callback: callback,
      include_raw_data: include_raw,
      raw_chunks: if(include_raw, do: [], else: nil),

      # Internal
      # For calculating average
      chunk_sizes: []
    }

    # Store initial metrics state
    store_metrics_state(stream_id, metrics_state)

    # Start periodic reporter if callback and interval are configured
    reporter_pid =
      if callback && interval > 0 do
        start_metrics_reporter(stream_id, callback, interval)
      end

    # Wrap the original callback to intercept chunks
    wrapped_context = wrap_stream_context(stream_context, metrics_state)
    env_with_wrapped = %{env | opts: Keyword.put(env.opts, :stream_context, wrapped_context)}

    # Execute the request
    result = Tesla.run(env_with_wrapped, next)

    # Finalize metrics
    finalize_metrics(stream_id, result, callback, reporter_pid)

    result
  end

  defp wrap_stream_context(stream_context, metrics_state) do
    original_callback = stream_context.callback
    stream_id = stream_context.stream_id

    wrapped_callback = fn chunk ->
      # Update metrics for this chunk
      update_metrics_for_chunk(stream_id, chunk, metrics_state[:include_raw_data])

      # Call original callback
      original_callback.(chunk)
    end

    %{stream_context | callback: wrapped_callback}
  end

  @doc false
  def initialize_metrics_for_test(stream_id, provider, include_raw \\ false) do
    metrics_state = %{
      stream_id: stream_id,
      provider: provider,
      start_time: System.system_time(:millisecond),
      last_report_time: System.system_time(:millisecond),
      bytes_received: 0,
      chunks_received: 0,
      error_count: 0,
      last_error: nil,
      status: :streaming,
      chunk_sizes: [],
      raw_chunks: [],
      include_raw_data: include_raw
    }

    store_metrics_state(stream_id, metrics_state)
    :ok
  end

  # Made public for testing purposes
  @doc false
  def update_metrics_for_chunk(stream_id, chunk, include_raw) do
    case get_metrics_state(stream_id) do
      nil ->
        Logger.warning("Metrics state not found for stream #{stream_id}")
        :ok

      state ->
        # Calculate chunk size
        chunk_size = calculate_chunk_size(chunk)

        # Update metrics
        updated_state =
          state
          |> Map.update!(:chunks_received, &(&1 + 1))
          |> Map.update!(:bytes_received, &(&1 + chunk_size))
          # Keep last 100 for average
          |> Map.update!(:chunk_sizes, &([chunk_size | &1] |> Enum.take(100)))
          |> maybe_add_raw_chunk(chunk, include_raw)
          |> update_status_from_chunk(chunk)

        store_metrics_state(stream_id, updated_state)
        :ok
    end
  end

  defp calculate_chunk_size(%{content: content}) when is_binary(content) do
    byte_size(content)
  end

  defp calculate_chunk_size(%{content: nil}), do: 0
  defp calculate_chunk_size(_), do: 0

  defp maybe_add_raw_chunk(state, _chunk, false), do: state

  defp maybe_add_raw_chunk(%{raw_chunks: chunks} = state, chunk, true) when is_list(chunks) do
    %{state | raw_chunks: [chunk | chunks]}
  end

  defp maybe_add_raw_chunk(state, _chunk, _), do: state

  defp update_status_from_chunk(state, %{finish_reason: "stop"}) do
    %{state | status: :completed}
  end

  defp update_status_from_chunk(state, %{finish_reason: "error"}) do
    %{state | status: :error, error_count: state.error_count + 1}
  end

  defp update_status_from_chunk(state, _chunk), do: state

  # Made public for testing purposes
  @doc false
  def finalize_metrics(stream_id, result, callback, reporter_pid) do
    # Stop the reporter if running
    if reporter_pid do
      send(reporter_pid, :stop)
    end

    # Get final metrics state
    case get_metrics_state(stream_id) do
      nil ->
        :ok

      state ->
        # Update final status based on result
        final_state =
          case result do
            {:ok, _} ->
              if state.status == :streaming do
                %{state | status: :completed}
              else
                state
              end

            {:error, reason} ->
              %{state | status: :error, last_error: reason, error_count: state.error_count + 1}
          end

        # Send final metrics if callback provided
        if callback do
          metrics = build_metrics_report(final_state)
          callback.(metrics)
        end

        # Cleanup
        cleanup_metrics_state(stream_id)
    end

    :ok
  end

  defp start_metrics_reporter(stream_id, callback, interval) do
    spawn(fn ->
      metrics_reporter_loop(stream_id, callback, interval)
    end)
  end

  defp metrics_reporter_loop(stream_id, callback, interval) do
    receive do
      :stop ->
        :ok
    after
      interval ->
        case get_metrics_state(stream_id) do
          nil ->
            # Stream completed, stop reporter
            :ok

          state ->
            # Only report if streaming is active
            if state.status == :streaming do
              metrics = build_metrics_report(state)
              callback.(metrics)

              # Update last report time
              updated_state = %{state | last_report_time: System.system_time(:millisecond)}
              store_metrics_state(stream_id, updated_state)

              # Continue loop
              metrics_reporter_loop(stream_id, callback, interval)
            else
              # Stream completed, stop reporter
              :ok
            end
        end
    end
  end

  defp build_metrics_report(state) do
    current_time = System.system_time(:millisecond)
    duration_ms = current_time - state.start_time

    # Calculate averages and rates
    avg_chunk_size = calculate_average(state.chunk_sizes)
    bytes_per_second = calculate_rate(state.bytes_received, duration_ms)
    chunks_per_second = calculate_rate(state.chunks_received, duration_ms)

    base_metrics = %{
      # Identification
      stream_id: state.stream_id,
      provider: state.provider,

      # Timing
      start_time: state.start_time,
      current_time: current_time,
      duration_ms: duration_ms,

      # Data volume
      bytes_received: state.bytes_received,
      chunks_received: state.chunks_received,

      # Throughput
      bytes_per_second: bytes_per_second,
      chunks_per_second: chunks_per_second,
      avg_chunk_size: avg_chunk_size,

      # Errors
      error_count: state.error_count,
      last_error: state.last_error,

      # Status
      status: state.status
    }

    # Add raw chunks if configured
    if state.include_raw_data && state.raw_chunks do
      Map.put(base_metrics, :raw_chunks, Enum.reverse(state.raw_chunks))
    else
      base_metrics
    end
  end

  defp calculate_average([]), do: 0.0

  defp calculate_average(numbers) do
    sum = Enum.sum(numbers)
    count = length(numbers)
    Float.round(sum / count, 2)
  end

  defp calculate_rate(_count, duration_ms) when duration_ms <= 0, do: 0.0

  defp calculate_rate(count, duration_ms) do
    Float.round(count * 1000 / duration_ms, 2)
  end

  # Configuration helpers

  defp get_option(env_opts, middleware_opts, key, default \\ nil) do
    # First check env opts (runtime), then middleware opts (compile time), then default
    Keyword.get(env_opts, key, Keyword.get(middleware_opts, key, default))
  end

  # State management using persistent_term for performance

  defp store_metrics_state(stream_id, state) do
    :persistent_term.put({__MODULE__, :metrics, stream_id}, state)
  end

  defp get_metrics_state(stream_id) do
    try do
      :persistent_term.get({__MODULE__, :metrics, stream_id})
    rescue
      ArgumentError -> nil
    end
  end

  defp cleanup_metrics_state(stream_id) do
    try do
      :persistent_term.erase({__MODULE__, :metrics, stream_id})
    rescue
      ArgumentError -> :ok
    end
  end
end
