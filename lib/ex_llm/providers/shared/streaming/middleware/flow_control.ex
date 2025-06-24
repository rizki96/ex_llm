defmodule ExLLM.Providers.Shared.Streaming.Middleware.FlowControl do
  @moduledoc """
  Tesla middleware for streaming flow control and backpressure management.

  This middleware provides intelligent flow control for streaming operations by
  integrating with the ExLLM.Infrastructure.Streaming.FlowController to manage
  backpressure, rate limiting, and graceful degradation under load.

  ## Features

  - **Automatic Backpressure**: Prevents overwhelming slow consumers
  - **Rate Limiting**: Controls the maximum chunk delivery rate
  - **Buffer Management**: Configurable buffer thresholds and overflow strategies
  - **Chunk Batching**: Optional intelligent batching for optimized output
  - **Comprehensive Metrics**: Real-time throughput and performance tracking
  - **Graceful Degradation**: Handles consumer errors and overload conditions

  ## Usage

  The middleware is automatically included when flow control is enabled:

  ```elixir
  client = Streaming.Engine.client(
    provider: :openai,
    api_key: "sk-...",
    enable_flow_control: true,
    flow_control: [
      buffer_capacity: 50,
      backpressure_threshold: 0.8,
      rate_limit_ms: 10
    ]
  )
  ```

  ## Configuration

  Configure via Tesla client options:

  ```elixir
  Tesla.client([
    {FlowControl, [
      enabled: true,
      buffer_capacity: 100,        # Maximum chunks to buffer
      backpressure_threshold: 0.8, # Buffer fill ratio to trigger backpressure
      rate_limit_ms: 5,            # Minimum ms between chunks
      overflow_strategy: :drop,     # :drop | :overwrite | :block
      batch_config: [              # Optional chunk batching
        batch_size: 5,
        batch_timeout_ms: 25
      ],
      on_metrics: &handle_metrics/1 # Optional metrics callback
    ]}
  ])
  ```

  ## Flow Control Strategies

  - **:drop** - Drop new chunks when buffer is full (default)
  - **:overwrite** - Overwrite oldest chunks when buffer is full
  - **:block** - Return backpressure error when buffer is full

  ## Integration with Streaming Infrastructure

  This middleware delegates flow control to the `ExLLM.Infrastructure.Streaming.FlowController`
  GenServer, providing consistent flow control behavior across the system while
  maintaining the Tesla middleware architecture.

  ## Metrics

  The middleware provides comprehensive metrics including:
  - Chunks received/delivered/dropped
  - Bytes processed and throughput
  - Backpressure events and consumer errors
  - Buffer utilization and performance
  """

  @behaviour Tesla.Middleware

  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Infrastructure.Streaming.FlowController

  # Default configuration
  @default_enabled true
  @default_buffer_capacity 100
  @default_backpressure_threshold 0.8
  @default_rate_limit_ms 5
  @default_overflow_strategy :drop

  @impl Tesla.Middleware
  def call(%Tesla.Env{opts: opts} = env, next, middleware_opts) do
    # Check if flow control is enabled
    enabled = get_option(opts, middleware_opts, :enabled, @default_enabled)

    if enabled && streaming_request?(env, opts) do
      call_with_flow_control(env, next, middleware_opts)
    else
      # Flow control disabled or not a streaming request
      Tesla.run(env, next)
    end
  end

  defp call_with_flow_control(%Tesla.Env{opts: opts} = env, next, middleware_opts) do
    stream_context = Keyword.get(opts, :stream_context)

    if stream_context && flow_control_supported?() do
      # Setup flow control for this stream
      setup_flow_control(env, next, stream_context, middleware_opts)
    else
      # No stream context or flow controller not available
      Tesla.run(env, next)
    end
  end

  defp setup_flow_control(env, next, stream_context, middleware_opts) do
    # Extract flow control configuration
    flow_config = build_flow_control_config(stream_context, middleware_opts)

    # Create original callback from stream context
    original_callback = stream_context.callback

    # Start flow controller
    case FlowController.start_link(flow_config) do
      {:ok, controller} ->
        Logger.debug("Flow control initialized for stream: #{stream_context.stream_id}")

        # Create flow-controlled callback
        flow_controlled_callback = create_flow_controlled_callback(controller, original_callback)

        # Enhance stream context with flow control
        enhanced_context =
          enhance_stream_context(stream_context, controller, flow_controlled_callback)

        # Execute the request with flow control monitoring
        execute_with_flow_control(env, next, enhanced_context, controller)

      {:error, reason} ->
        Logger.warning("Failed to initialize flow control: #{inspect(reason)}")
        # Continue without flow control
        Tesla.run(env, next)
    end
  end

  defp execute_with_flow_control(env, next, stream_context, controller) do
    # Update env with enhanced stream context
    env_with_flow_control = %{env | opts: Keyword.put(env.opts, :stream_context, stream_context)}

    # Execute the streaming request
    result = Tesla.run(env_with_flow_control, next)

    # Complete the stream and get final metrics
    case result do
      {:ok, response} ->
        # Stream completed successfully
        FlowController.complete_stream(controller)
        Logger.debug("Flow control completed for stream: #{stream_context.stream_id}")

        # Optionally attach metrics to response
        final_metrics = FlowController.get_metrics(controller)
        response_with_metrics = add_metrics_to_response(response, final_metrics)

        {:ok, response_with_metrics}

      {:error, reason} ->
        # Stream failed - still complete flow control
        FlowController.complete_stream(controller)
        Logger.debug("Flow control completed after error for stream: #{stream_context.stream_id}")

        {:error, reason}
    end
  end

  defp create_flow_controlled_callback(controller, original_callback) do
    fn chunk ->
      # Push chunk to flow controller
      case FlowController.push_chunk(controller, chunk) do
        :ok ->
          # Chunk accepted, the flow controller's consumer will handle calling original_callback
          :ok

        {:error, :backpressure} ->
          # Backpressure active - we could implement retry logic here
          # For now, we'll log and continue
          Logger.debug("Backpressure detected in flow control")
          # Try calling original callback directly as fallback
          original_callback.(chunk)
      end
    end
  end

  defp enhance_stream_context(stream_context, controller, flow_controlled_callback) do
    # Replace callback with flow-controlled version
    stream_context
    |> Map.put(:callback, flow_controlled_callback)
    |> Map.put(:flow_controller, controller)
    |> Map.put(:flow_control_enabled, true)
  end

  defp build_flow_control_config(stream_context, middleware_opts) do
    # Build consumer callback that uses flow controller
    original_callback = stream_context.callback

    consumer_callback = fn chunk ->
      try do
        original_callback.(chunk)
        :ok
      catch
        kind, reason ->
          Logger.error("Flow control consumer error: #{kind} #{inspect(reason)}")
          :error
      end
    end

    # Extract configuration, ensuring positive values
    buffer_capacity =
      max(
        1,
        get_option(stream_context, middleware_opts, :buffer_capacity, @default_buffer_capacity)
      )

    backpressure_threshold =
      max(
        0.1,
        min(
          1.0,
          get_option(
            stream_context,
            middleware_opts,
            :backpressure_threshold,
            @default_backpressure_threshold
          )
        )
      )

    rate_limit_ms =
      max(0, get_option(stream_context, middleware_opts, :rate_limit_ms, @default_rate_limit_ms))

    # Merge configuration from various sources
    base_config = [
      consumer: consumer_callback,
      buffer_capacity: buffer_capacity,
      backpressure_threshold: backpressure_threshold,
      rate_limit_ms: rate_limit_ms,
      overflow_strategy:
        get_option(
          stream_context,
          middleware_opts,
          :overflow_strategy,
          @default_overflow_strategy
        )
    ]

    # Add optional batch configuration
    batch_config = get_option(stream_context, middleware_opts, :batch_config, nil)

    base_config =
      if batch_config,
        do: Keyword.put(base_config, :batch_config, batch_config),
        else: base_config

    # Add optional metrics callback
    on_metrics = get_option(stream_context, middleware_opts, :on_metrics, nil)

    base_config =
      if on_metrics, do: Keyword.put(base_config, :on_metrics, on_metrics), else: base_config

    base_config
  end

  defp add_metrics_to_response(response, metrics) do
    # Add flow control metrics to response headers or metadata
    flow_control_headers = [
      {"x-flow-control-chunks-delivered", to_string(metrics.chunks_delivered)},
      {"x-flow-control-throughput", to_string(metrics.throughput_chunks_per_sec)},
      {"x-flow-control-backpressure-events", to_string(metrics.backpressure_events)},
      {"x-flow-control-buffer-max", to_string(metrics.max_buffer_size)}
    ]

    # Add to existing headers
    updated_headers = (response.headers || []) ++ flow_control_headers

    %{response | headers: updated_headers}
  end

  # Helper functions

  defp streaming_request?(%{opts: opts}, _middleware_opts) do
    # Check if this is a streaming request
    Keyword.has_key?(opts, :stream_context)
  end

  defp flow_control_supported? do
    # Check if FlowController is available (not just the module, but that it can start)
    try do
      # Try to check if the infrastructure modules are loaded
      Code.ensure_loaded?(ExLLM.Infrastructure.Streaming.FlowController) &&
        Code.ensure_loaded?(ExLLM.Infrastructure.Streaming.StreamBuffer)
    rescue
      _ -> false
    end
  end

  defp get_option(env_opts, middleware_opts, key, default) do
    # First check env opts (runtime), then middleware opts (compile time), then default
    case env_opts do
      %{} = map -> Map.get(map, key, Keyword.get(middleware_opts, key, default))
      keyword_list -> Keyword.get(keyword_list, key, Keyword.get(middleware_opts, key, default))
    end
  end

  @doc """
  Check if flow control is currently active for a stream context.

  ## Examples

      iex> stream_context = %{flow_control_enabled: true}
      iex> FlowControl.active?(stream_context)
      true
      
      iex> stream_context = %{}
      iex> FlowControl.active?(stream_context)
      false
  """
  @spec active?(map()) :: boolean()
  def active?(%{flow_control_enabled: true}), do: true
  def active?(_), do: false

  @doc """
  Get current flow control metrics for a stream context.

  Returns `{:ok, metrics}` if flow control is active, or `{:error, :not_active}`.
  """
  @spec get_metrics(map()) :: {:ok, map()} | {:error, :not_active}
  def get_metrics(%{flow_controller: controller}) when is_pid(controller) do
    try do
      metrics = FlowController.get_metrics(controller)
      {:ok, metrics}
    catch
      :exit, _ -> {:error, :controller_dead}
    end
  end

  def get_metrics(_), do: {:error, :not_active}

  @doc """
  Get current flow control status for a stream context.

  Returns detailed status including buffer state and performance metrics.
  """
  @spec get_status(map()) :: {:ok, map()} | {:error, :not_active}
  def get_status(%{flow_controller: controller}) when is_pid(controller) do
    try do
      status = FlowController.get_status(controller)
      {:ok, status}
    catch
      :exit, _ -> {:error, :controller_dead}
    end
  end

  def get_status(_), do: {:error, :not_active}

  @doc """
  Create a flow control configuration map for common use cases.

  ## Examples

      # High-throughput configuration
      config = FlowControl.config(:high_throughput)
      
      # Low-latency configuration
      config = FlowControl.config(:low_latency)
      
      # Custom configuration
      config = FlowControl.config(
        buffer_capacity: 200,
        rate_limit_ms: 1
      )
  """
  @spec config(atom() | keyword()) :: keyword()
  def config(:high_throughput) do
    [
      enabled: true,
      buffer_capacity: 200,
      backpressure_threshold: 0.9,
      rate_limit_ms: 1,
      overflow_strategy: :overwrite,
      batch_config: [
        batch_size: 10,
        batch_timeout_ms: 50
      ]
    ]
  end

  def config(:low_latency) do
    [
      enabled: true,
      buffer_capacity: 20,
      backpressure_threshold: 0.5,
      rate_limit_ms: 0,
      overflow_strategy: :drop
      # No batching for low latency
    ]
  end

  def config(:balanced) do
    [
      enabled: true,
      buffer_capacity: @default_buffer_capacity,
      backpressure_threshold: @default_backpressure_threshold,
      rate_limit_ms: @default_rate_limit_ms,
      overflow_strategy: @default_overflow_strategy,
      batch_config: [
        batch_size: 5,
        batch_timeout_ms: 25
      ]
    ]
  end

  def config(custom_opts) when is_list(custom_opts) do
    defaults = config(:balanced)
    Keyword.merge(defaults, custom_opts)
  end
end
