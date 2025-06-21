defmodule ExLLM.Providers.Shared.EnhancedStreamingCoordinator do
  @moduledoc """
  Enhanced streaming coordinator with advanced flow control, intelligent batching, 
  and sophisticated buffering strategies.

  This module extends the basic StreamingCoordinator with our advanced streaming
  infrastructure while maintaining backward compatibility. It provides:

  - Advanced flow control with backpressure (FlowController)
  - Intelligent chunk batching with adaptive sizing (ChunkBatcher)
  - Circular buffering with overflow strategies (StreamBuffer)
  - Real-time metrics and performance monitoring
  - Error recovery and graceful degradation

  ## Enhanced Features

  - **Backpressure Control**: Automatically handles slow consumers by applying
    backpressure when buffers fill up, preventing memory exhaustion
  - **Adaptive Batching**: Intelligent chunk batching that adapts to chunk size
    and arrival rate for optimal performance
  - **Multiple Overflow Strategies**: Choose between drop, overwrite, or block
    strategies when buffers are full
  - **Real-time Metrics**: Comprehensive metrics tracking including throughput,
    latency, buffer utilization, and error rates
  - **Advanced Error Recovery**: Graceful handling of consumer errors with
    automatic retry and recovery mechanisms

  ## Usage

  ```elixir
  # Basic enhanced streaming (same as original)
  {:ok, stream_id} = EnhancedStreamingCoordinator.start_stream(
    url, request, headers, callback,
    parse_chunk_fn: &parse_chunk/1
  )

  # Advanced streaming with flow control
  {:ok, stream_id} = EnhancedStreamingCoordinator.start_stream(
    url, request, headers, callback,
    parse_chunk_fn: &parse_chunk/1,
    enable_flow_control: true,
    buffer_capacity: 100,
    backpressure_threshold: 0.8,
    overflow_strategy: :drop
  )

  # Intelligent batching
  {:ok, stream_id} = EnhancedStreamingCoordinator.start_stream(
    url, request, headers, callback,
    parse_chunk_fn: &parse_chunk/1,
    enable_batching: true,
    batch_size: 5,
    batch_timeout_ms: 25,
    adaptive_batching: true
  )

  # Combined advanced features
  {:ok, stream_id} = EnhancedStreamingCoordinator.start_stream(
    url, request, headers, callback,
    parse_chunk_fn: &parse_chunk/1,
    enable_flow_control: true,
    enable_batching: true,
    buffer_capacity: 50,
    backpressure_threshold: 0.9,
    batch_size: 3,
    adaptive_batching: true,
    on_metrics: &handle_metrics/1
  )
  ```

  ## Configuration Options

  ### Flow Control Options
  - `:enable_flow_control` - Enable advanced flow control (default: false)
  - `:buffer_capacity` - Buffer capacity in chunks (default: 100)
  - `:backpressure_threshold` - Buffer fill ratio to trigger backpressure (default: 0.8)
  - `:overflow_strategy` - Strategy when buffer overflows: `:drop`, `:overwrite`, `:block` (default: `:drop`)
  - `:rate_limit_ms` - Minimum time between chunks in ms (default: 1)

  ### Batching Options
  - `:enable_batching` - Enable intelligent chunk batching (default: false)
  - `:batch_size` - Target batch size (default: 5)
  - `:batch_timeout_ms` - Max time to wait for batch (default: 25)
  - `:adaptive_batching` - Enable adaptive batch sizing (default: true)
  - `:min_batch_size` - Minimum chunks before batching (default: 1)
  - `:max_batch_size` - Maximum chunks per batch (default: 20)

  ### Monitoring Options
  - `:track_detailed_metrics` - Enable detailed metrics tracking (default: false)
  - `:on_metrics` - Callback for real-time metrics reports
  - `:metrics_interval_ms` - Metrics reporting interval (default: 1000)

  ## Backward Compatibility

  This module is fully backward compatible with the original StreamingCoordinator.
  When advanced features are not explicitly enabled, it behaves identically to the
  original implementation.
  """

  alias ExLLM.Infrastructure.Streaming.FlowController
  alias ExLLM.Providers.Shared.{HTTPClient, StreamingCoordinator}
  alias ExLLM.Types

  alias ExLLM.Infrastructure.Logger

  @default_timeout :timer.minutes(5)
  @default_metrics_interval 1000

  @doc """
  Start an enhanced streaming request with optional advanced features.

  This function provides the same interface as the original StreamingCoordinator
  but with additional options for enabling advanced streaming features.

  ## Enhanced Options

  In addition to all original options, supports:
  - Flow control options (see module documentation)
  - Batching options (see module documentation)  
  - Monitoring options (see module documentation)

  ## Examples

  ```elixir
  # Basic usage (identical to original StreamingCoordinator)
  {:ok, stream_id} = start_stream(url, request, headers, callback,
    parse_chunk_fn: &parse_chunk/1
  )

  # With advanced flow control
  {:ok, stream_id} = start_stream(url, request, headers, callback,
    parse_chunk_fn: &parse_chunk/1,
    enable_flow_control: true,
    buffer_capacity: 50,
    backpressure_threshold: 0.9
  )

  # With intelligent batching
  {:ok, stream_id} = start_stream(url, request, headers, callback,
    parse_chunk_fn: &parse_chunk/1,
    enable_batching: true,
    batch_size: 3,
    adaptive_batching: true
  )
  ```
  """
  @spec start_stream(String.t(), map(), list(), function(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def start_stream(url, request, headers, callback, options \\ []) do
    parse_chunk_fn = Keyword.fetch!(options, :parse_chunk_fn)
    recovery_id = Keyword.get(options, :recovery_id, generate_stream_id())

    # Check if advanced features are enabled
    use_advanced_features =
      Keyword.get(options, :enable_flow_control, false) or
        Keyword.get(options, :enable_batching, false)

    if use_advanced_features do
      start_enhanced_stream(url, request, headers, callback, parse_chunk_fn, recovery_id, options)
    else
      # Delegate to original StreamingCoordinator for backward compatibility
      StreamingCoordinator.start_stream(url, request, headers, callback, options)
    end
  end

  @doc """
  Execute enhanced streaming with advanced infrastructure.
  """
  def execute_enhanced_stream(
        url,
        request,
        headers,
        callback,
        parse_chunk_fn,
        stream_context,
        options
      ) do
    recovery_id = stream_context.recovery_id

    Logger.debug("Starting enhanced stream #{recovery_id} with advanced features")

    # Save stream state for potential recovery
    if Keyword.get(options, :stream_recovery, false) do
      save_stream_state(recovery_id, url, request, headers, options)
    end

    # Setup flow controller if enabled
    {flow_controller, enhanced_callback} =
      if Keyword.get(options, :enable_flow_control, false) do
        setup_flow_controller(callback, stream_context, options)
      else
        {nil, callback}
      end

    # Setup metrics tracking
    metrics_pid =
      if Keyword.get(options, :track_detailed_metrics, false) do
        start_enhanced_metrics_tracker(stream_context, flow_controller, options)
      end

    # Create enhanced stream collector
    stream_opts = [
      headers: headers,
      receive_timeout: Keyword.get(options, :timeout, @default_timeout),
      into:
        create_enhanced_stream_collector(
          enhanced_callback,
          parse_chunk_fn,
          stream_context,
          flow_controller,
          options
        )
    ]

    result =
      case HTTPClient.post_stream(url, request, stream_opts) do
        {:ok, _response} ->
          Logger.debug("Enhanced stream #{recovery_id} completed successfully")

          # Complete flow controller if present
          if flow_controller do
            FlowController.complete_stream(flow_controller)
          end

          # Send completion chunk
          enhanced_callback.(%ExLLM.Types.StreamChunk{
            content: "",
            finish_reason: "stop"
          })

          # Report final metrics
          report_final_enhanced_metrics(stream_context, flow_controller, metrics_pid, options)

          # Clean up
          if flow_controller, do: GenServer.stop(flow_controller)
          cleanup_stream_state(recovery_id)
          :ok

        {:error, reason} ->
          Logger.error("Enhanced stream #{recovery_id} error: #{inspect(reason)}")

          # Handle error with flow controller
          if flow_controller do
            GenServer.stop(flow_controller)
          end

          # Handle error with optional recovery
          handle_enhanced_stream_error(reason, enhanced_callback, stream_context, options)
      end

    # Stop metrics tracker if running
    if metrics_pid, do: Process.exit(metrics_pid, :normal)

    result
  end

  @doc """
  Create an enhanced stream collector with optional flow control and batching.
  """
  def create_enhanced_stream_collector(
        callback,
        parse_chunk_fn,
        stream_context,
        flow_controller,
        options
      ) do
    # For flow controller mode, we don't need internal buffering
    # as the FlowController handles all buffering and flow control
    if flow_controller do
      create_flow_controlled_collector(
        callback,
        parse_chunk_fn,
        stream_context,
        flow_controller,
        options
      )
    else
      # Fall back to original collector for backward compatibility
      StreamingCoordinator.create_stream_collector(
        callback,
        parse_chunk_fn,
        stream_context,
        options
      )
    end
  end

  # Private functions

  defp start_enhanced_stream(
         url,
         request,
         headers,
         callback,
         parse_chunk_fn,
         recovery_id,
         options
       ) do
    # Initialize enhanced stream context
    stream_context = %{
      recovery_id: recovery_id,
      start_time: System.monotonic_time(:millisecond),
      chunk_count: 0,
      byte_count: 0,
      error_count: 0,
      provider: Keyword.get(options, :provider, :unknown),
      enhanced_features: %{
        flow_control: Keyword.get(options, :enable_flow_control, false),
        batching: Keyword.get(options, :enable_batching, false),
        detailed_metrics: Keyword.get(options, :track_detailed_metrics, false)
      }
    }

    Task.async(fn ->
      execute_enhanced_stream(
        url,
        request,
        headers,
        callback,
        parse_chunk_fn,
        stream_context,
        options
      )
    end)

    {:ok, recovery_id}
  end

  defp setup_flow_controller(callback, stream_context, options) do
    Logger.debug("Setting up FlowController for stream #{stream_context.recovery_id}")

    # Configure flow controller options
    flow_opts = [
      consumer: callback,
      buffer_capacity: Keyword.get(options, :buffer_capacity, 100),
      backpressure_threshold: Keyword.get(options, :backpressure_threshold, 0.8),
      rate_limit_ms: Keyword.get(options, :rate_limit_ms, 1),
      overflow_strategy: Keyword.get(options, :overflow_strategy, :drop)
    ]

    # Add batching configuration if enabled
    flow_opts =
      if Keyword.get(options, :enable_batching, false) do
        batch_config = [
          batch_size: Keyword.get(options, :batch_size, 5),
          batch_timeout_ms: Keyword.get(options, :batch_timeout_ms, 25),
          adaptive: Keyword.get(options, :adaptive_batching, true),
          min_batch_size: Keyword.get(options, :min_batch_size, 1),
          max_batch_size: Keyword.get(options, :max_batch_size, 20)
        ]

        Keyword.put(flow_opts, :batch_config, batch_config)
      else
        flow_opts
      end

    # Add metrics callback if configured
    flow_opts =
      if on_metrics = Keyword.get(options, :on_metrics) do
        metrics_callback = fn metrics ->
          # Enhance metrics with stream context
          enhanced_metrics =
            Map.merge(metrics, %{
              stream_id: stream_context.recovery_id,
              provider: stream_context.provider
            })

          on_metrics.(enhanced_metrics)
        end

        Keyword.put(flow_opts, :on_metrics, metrics_callback)
      else
        flow_opts
      end

    case FlowController.start_link(flow_opts) do
      {:ok, flow_controller} ->
        Logger.debug("FlowController started for stream #{stream_context.recovery_id}")

        # Create flow-controlled callback
        flow_callback = fn chunk ->
          case FlowController.push_chunk(flow_controller, chunk) do
            :ok ->
              :ok

            {:error, :backpressure} ->
              Logger.warning("Backpressure applied in stream #{stream_context.recovery_id}")
              # Continue processing, FlowController handles the backpressure
              :ok
          end
        end

        {flow_controller, flow_callback}

      {:error, reason} ->
        Logger.error("Failed to start FlowController: #{inspect(reason)}")
        {nil, callback}
    end
  end

  defp create_flow_controlled_collector(
         callback,
         parse_chunk_fn,
         stream_context,
         flow_controller,
         options
       ) do
    recovery_id = stream_context.recovery_id

    fn
      {:data, data}, acc ->
        # Initialize accumulator if needed
        {text_buffer, stats} =
          case acc do
            {_, _} = state -> state
            _ -> {"", stream_context}
          end

        {new_text_buffer, new_stats} =
          process_flow_controlled_data(
            data,
            text_buffer,
            callback,
            parse_chunk_fn,
            flow_controller,
            stats,
            options
          )

        {:cont, {new_text_buffer, new_stats}}

      {:error, reason}, {_, stats} ->
        Logger.error("Flow controlled collector error in #{recovery_id}: #{inspect(reason)}")
        _new_stats = update_stream_stats(stats, :error_count, 1)
        {:halt, {:error, reason}}
    end
  end

  defp process_flow_controlled_data(
         data,
         text_buffer,
         _callback,
         parse_chunk_fn,
         flow_controller,
         stats,
         options
       ) do
    full_data = text_buffer <> data
    recovery_id = stats.recovery_id

    # Update byte count
    stats = update_stream_stats(stats, :byte_count, byte_size(data))

    # Split by newlines for SSE processing
    lines = String.split(full_data, "\n")
    {complete_lines, [last_line]} = Enum.split(lines, -1)

    # Process lines and send to flow controller
    new_stats =
      Enum.reduce(complete_lines, stats, fn line, st ->
        process_flow_line(line, st, parse_chunk_fn, recovery_id, options, flow_controller)
      end)

    {last_line, new_stats}
  end

  defp process_flow_line(line, st, parse_chunk_fn, recovery_id, options, flow_controller) do
    case StreamingCoordinator.parse_sse_line(line) do
      {:data, event_data} ->
        process_flow_event_data(
          event_data,
          st,
          parse_chunk_fn,
          recovery_id,
          options,
          flow_controller
        )

      :done ->
        Logger.debug(
          "Flow controlled stream #{recovery_id} completed after #{st.chunk_count} chunks"
        )

        st

      :skip ->
        st
    end
  end

  defp process_flow_event_data(
         event_data,
         st,
         parse_chunk_fn,
         recovery_id,
         options,
         flow_controller
       ) do
    case handle_event_data(event_data, parse_chunk_fn, recovery_id, st, options) do
      {:ok, chunk} ->
        send_chunk_to_flow_controller(chunk, st, flow_controller, recovery_id)

      :skip ->
        st
    end
  end

  defp send_chunk_to_flow_controller(chunk, st, flow_controller, recovery_id) do
    case FlowController.push_chunk(flow_controller, chunk) do
      :ok ->
        update_stream_stats(st, :chunk_count, 1)

      {:error, :backpressure} ->
        Logger.debug("Backpressure applied for chunk in stream #{recovery_id}")
        update_stream_stats(st, :chunk_count, 1)
    end
  end

  defp handle_event_data(data, parse_chunk_fn, recovery_id, stats, options) do
    # Delegate to original implementation for consistency
    case parse_chunk_fn.(data) do
      {:ok, :done} ->
        Logger.debug("Stream #{recovery_id} signaled done")
        :skip

      {:ok, chunk} when is_struct(chunk, Types.StreamChunk) ->
        validate_and_save_chunk(chunk, recovery_id, stats.chunk_count, options)

      %ExLLM.Types.StreamChunk{} = chunk ->
        validate_and_save_chunk(chunk, recovery_id, stats.chunk_count, options)

      nil ->
        :skip

      {:error, reason} ->
        Logger.debug(
          "Failed to parse chunk in enhanced stream #{recovery_id}: #{inspect(reason)}"
        )

        :skip
    end
  end

  defp validate_and_save_chunk(chunk, recovery_id, chunk_count, options) do
    # Validate chunk if validator provided
    if validator = Keyword.get(options, :validate_chunk) do
      case validator.(chunk) do
        :ok ->
          save_chunk_if_recovery_enabled(recovery_id, chunk, chunk_count, options)
          {:ok, chunk}

        {:error, reason} ->
          Logger.warning("Invalid chunk rejected in enhanced stream: #{inspect(reason)}")
          :skip
      end
    else
      save_chunk_if_recovery_enabled(recovery_id, chunk, chunk_count, options)
      {:ok, chunk}
    end
  end

  defp save_chunk_if_recovery_enabled(recovery_id, chunk, chunk_count, options) do
    if Keyword.get(options, :stream_recovery, false) do
      # Use StreamingCoordinator's recovery functionality
      if stream_recovery_enabled?() do
        # record_chunk uses GenServer.cast and always returns :ok
        ExLLM.Core.Streaming.Recovery.record_chunk(recovery_id, chunk)
        Logger.debug("Saved enhanced chunk #{chunk_count} for stream #{recovery_id}")
      end
    end
  end

  defp handle_enhanced_stream_error(reason, callback, stream_context, options) do
    # Delegate to original implementation for consistency
    recovery_id = stream_context.recovery_id

    # Create an error chunk
    error_chunk = %ExLLM.Types.StreamChunk{
      content: "Error: #{inspect(reason)}",
      finish_reason: "error"
    }

    # Check if error is recoverable
    if Keyword.get(options, :stream_recovery, false) && is_recoverable_error?(reason) do
      mark_stream_recoverable(recovery_id, reason)
    else
      cleanup_stream_state(recovery_id)
    end

    callback.(error_chunk)
    {:error, reason}
  end

  defp is_recoverable_error?(reason) do
    case reason do
      {:error, {:connection_failed, _}} -> true
      {:service_unavailable, _} -> true
      {:rate_limit_error, _} -> true
      _ -> false
    end
  end

  defp save_stream_state(recovery_id, _url, request, _headers, options) do
    # Delegate to StreamingCoordinator for consistency
    if stream_recovery_enabled?() do
      provider = Keyword.get(options, :provider, :unknown)
      messages = extract_messages_from_request(request, provider)

      {:ok, _} = ExLLM.Core.Streaming.Recovery.init_recovery(provider, messages, options)
      Logger.debug("Enhanced stream recovery initialized for #{recovery_id}")
    end
  end

  defp mark_stream_recoverable(recovery_id, reason) do
    if stream_recovery_enabled?() do
      case ExLLM.Core.Streaming.Recovery.record_error(recovery_id, reason) do
        {:ok, recoverable} ->
          if recoverable do
            Logger.info(
              "Enhanced stream #{recovery_id} marked as recoverable: #{inspect(reason)}"
            )
          else
            Logger.debug(
              "Enhanced stream #{recovery_id} error recorded (not recoverable): #{inspect(reason)}"
            )
          end

        {:error, error} ->
          Logger.warning("Failed to mark enhanced stream as recoverable: #{inspect(error)}")
      end
    end
  end

  defp cleanup_stream_state(recovery_id) do
    if stream_recovery_enabled?() do
      # complete_stream uses GenServer.cast and always returns :ok
      ExLLM.Core.Streaming.Recovery.complete_stream(recovery_id)
      Logger.debug("Enhanced stream recovery state cleaned up: #{recovery_id}")
    end
  end

  defp stream_recovery_enabled? do
    Process.whereis(ExLLM.Core.Streaming.Recovery) != nil
  end

  defp extract_messages_from_request(request, :openai) when is_map(request) do
    Map.get(request, "messages", [])
  end

  defp extract_messages_from_request(request, :anthropic) when is_map(request) do
    Map.get(request, "messages", [])
  end

  defp extract_messages_from_request(request, :gemini) when is_map(request) do
    case Map.get(request, "contents", []) do
      contents when is_list(contents) ->
        Enum.map(contents, fn content ->
          %{
            role: Map.get(content, "role", "user"),
            content: extract_gemini_content(content)
          }
        end)

      _ ->
        []
    end
  end

  defp extract_messages_from_request(_request, _provider), do: []

  defp extract_gemini_content(%{"parts" => parts}) when is_list(parts) do
    parts
    |> Enum.map(fn
      %{"text" => text} -> text
      _ -> ""
    end)
    |> Enum.join(" ")
  end

  defp extract_gemini_content(_), do: ""

  defp generate_stream_id do
    "enhanced_stream_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end

  defp update_stream_stats(stats, key, increment) do
    Map.update(stats, key, increment, &(&1 + increment))
  end

  defp start_enhanced_metrics_tracker(stream_context, flow_controller, options) do
    parent = self()
    on_metrics = Keyword.get(options, :on_metrics)
    interval = Keyword.get(options, :metrics_interval_ms, @default_metrics_interval)

    spawn(fn ->
      track_enhanced_metrics_loop(parent, stream_context, flow_controller, on_metrics, interval)
    end)
  end

  defp track_enhanced_metrics_loop(parent, stream_context, flow_controller, on_metrics, interval) do
    receive do
      :stop ->
        :ok
    after
      interval ->
        if on_metrics && Process.alive?(parent) do
          metrics = calculate_enhanced_metrics(stream_context, flow_controller)
          on_metrics.(metrics)
        end

        track_enhanced_metrics_loop(parent, stream_context, flow_controller, on_metrics, interval)
    end
  end

  defp calculate_enhanced_metrics(stream_context, flow_controller) do
    current_time = System.monotonic_time(:millisecond)
    duration_ms = current_time - stream_context.start_time

    base_metrics = %{
      stream_id: stream_context.recovery_id,
      provider: stream_context.provider,
      duration_ms: duration_ms,
      chunks_received: stream_context.chunk_count,
      bytes_received: stream_context.byte_count,
      errors: stream_context.error_count,
      chunks_per_second: calculate_rate(stream_context.chunk_count, duration_ms),
      bytes_per_second: calculate_rate(stream_context.byte_count, duration_ms),
      enhanced_features: stream_context.enhanced_features
    }

    # Add flow controller metrics if available
    if flow_controller do
      flow_metrics = FlowController.get_metrics(flow_controller)

      Map.merge(base_metrics, %{
        flow_control: flow_metrics,
        status: FlowController.get_status(flow_controller)
      })
    else
      base_metrics
    end
  end

  defp calculate_rate(count, duration_ms) when duration_ms > 0 do
    Float.round(count * 1000 / duration_ms, 2)
  end

  defp calculate_rate(_, _), do: 0.0

  defp report_final_enhanced_metrics(stream_context, flow_controller, metrics_pid, options) do
    if metrics_pid do
      send(metrics_pid, :stop)
    end

    if on_metrics = Keyword.get(options, :on_metrics) do
      final_metrics = calculate_enhanced_metrics(stream_context, flow_controller)
      on_metrics.(Map.put(final_metrics, :status, :completed))
    end
  end

  @doc """
  Create a simple enhanced streaming implementation.

  This provides the same interface as StreamingCoordinator.simple_stream/1
  but with optional enhanced features.

  ## Example

      EnhancedStreamingCoordinator.simple_stream(
        url: url,
        request: request,
        headers: headers,
        callback: callback,
        parse_chunk: &parse_chunk/1,
        enable_flow_control: true,
        buffer_capacity: 50,
        enable_batching: true,
        batch_size: 3
      )
  """
  def simple_stream(params) do
    url = Keyword.fetch!(params, :url)
    request = Keyword.fetch!(params, :request)
    headers = Keyword.fetch!(params, :headers)
    callback = Keyword.fetch!(params, :callback)
    parse_chunk = Keyword.fetch!(params, :parse_chunk)
    options = Keyword.get(params, :options, [])

    # Extract enhanced options from params
    enhanced_options =
      params
      |> Keyword.drop([:url, :request, :headers, :callback, :parse_chunk, :options])
      |> Keyword.merge(options)
      |> Keyword.put(:parse_chunk_fn, parse_chunk)

    start_stream(url, request, headers, callback, enhanced_options)
  end
end
