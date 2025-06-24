defmodule ExLLM.Providers.Shared.StreamingEngine do
  @moduledoc """
  Unified streaming facade that replaces the three parallel streaming implementations.

  This module serves as the single entry point for all streaming operations in ExLLM.
  It intelligently delegates between different streaming approaches based on feature
  requirements while maintaining full backward compatibility.

  ## Architecture Decision

  After analyzing the three existing streaming implementations:
  - `StreamingCoordinator` (771 lines, monolithic, basic features)
  - `EnhancedStreamingCoordinator` (798 lines, facade with FlowController)
  - `Streaming.Engine` (474 lines, Tesla middleware, incomplete)

  This facade consolidates them into a single, clean interface that:
  1. **Delegates to EnhancedStreamingCoordinator** for advanced features
  2. **Falls back to StreamingCoordinator** for basic streaming
  3. **Provides Tesla middleware path** for future extensibility
  4. **Maintains 100% backward compatibility** with existing code

  ## Usage Patterns

  ### Basic Streaming (StreamingCoordinator)
  ```elixir
  {:ok, stream_id} = StreamingEngine.start_stream(
    url, request, headers, callback,
    parse_chunk_fn: &parse_chunk/1
  )
  ```

  ### Advanced Streaming (EnhancedStreamingCoordinator)
  ```elixir
  {:ok, stream_id} = StreamingEngine.start_stream(
    url, request, headers, callback,
    parse_chunk_fn: &parse_chunk/1,
    enable_flow_control: true,
    buffer_capacity: 100,
    backpressure_threshold: 0.8
  )
  ```

  ### Tesla Middleware Mode (Future)
  ```elixir
  client = StreamingEngine.tesla_client(provider: :openai, api_key: "sk-...")
  {:ok, stream_id} = StreamingEngine.tesla_stream(
    client, "/chat/completions", request, 
    callback: callback, parse_chunk: &parse_chunk/1
  )
  ```

  ## Implementation Strategy

  This facade uses the proven conditional delegation pattern from EnhancedStreamingCoordinator:

  ```elixir
  if use_advanced_features do
    EnhancedStreamingCoordinator.start_stream(...)
  else
    StreamingCoordinator.start_stream(...)
  end
  ```

  ## Feature Detection

  Advanced features are automatically enabled when any of these options are present:
  - `:enable_flow_control`
  - `:enable_batching` 
  - `:buffer_capacity`
  - `:backpressure_threshold`
  - `:overflow_strategy`
  - `:batch_config`
  - `:track_detailed_metrics`

  ## Backward Compatibility

  All existing code using `StreamingCoordinator` or `EnhancedStreamingCoordinator`
  directly will continue to work unchanged. This facade simply provides a unified
  entry point for new code.

  ## Future Migration

  Once Tesla middleware infrastructure is complete, this facade can seamlessly
  transition to the Tesla-based approach without breaking existing integrations.
  """

  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Providers.Shared.{EnhancedStreamingCoordinator, StreamingCoordinator}
  require Logger

  # Stream tracking for status reporting
  @stream_tracker_name __MODULE__.StreamTracker

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @doc false
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: @stream_tracker_name)
  end

  # Re-export Tesla middleware functionality for future use
  defdelegate tesla_client(opts), to: ExLLM.Providers.Shared.Streaming.Engine, as: :client

  defdelegate tesla_stream(client, path, body, opts),
    to: ExLLM.Providers.Shared.Streaming.Engine,
    as: :stream

  defdelegate cancel_stream(stream_id),
    to: ExLLM.Providers.Shared.Streaming.Engine

  defdelegate stream_status(stream_id),
    to: ExLLM.Providers.Shared.Streaming.Engine

  @doc """
  Start a unified streaming request with intelligent feature detection.

  This is the main entry point for all streaming operations. It automatically
  detects required features and delegates to the appropriate implementation:

  - **Basic streaming**: Uses StreamingCoordinator for simple, fast streaming
  - **Advanced streaming**: Uses EnhancedStreamingCoordinator for flow control, 
    batching, and advanced metrics
  - **Tesla mode**: Uses Tesla middleware stack (when explicitly requested)

  ## Options

  ### Core Options (all implementations)
  - `:parse_chunk_fn` - Function to parse provider-specific chunks (required)
  - `:recovery_id` - Optional ID for stream recovery
  - `:timeout` - Stream timeout in milliseconds (default: 5 minutes)
  - `:on_error` - Error callback function
  - `:provider` - Provider atom for metrics and recovery

  ### Basic Features (StreamingCoordinator)
  - `:transform_chunk` - Optional function to transform chunks before callback
  - `:buffer_chunks` - Buffer size for chunk batching (default: 1) 
  - `:validate_chunk` - Optional function to validate chunks
  - `:track_metrics` - Enable basic metrics tracking (default: false)
  - `:on_metrics` - Metrics callback function

  ### Advanced Features (EnhancedStreamingCoordinator)
  - `:enable_flow_control` - Enable advanced flow control (triggers advanced mode)
  - `:enable_batching` - Enable intelligent chunk batching (triggers advanced mode)
  - `:buffer_capacity` - Buffer capacity in chunks (triggers advanced mode)
  - `:backpressure_threshold` - Buffer fill ratio to trigger backpressure
  - `:overflow_strategy` - Strategy when buffer overflows: `:drop`, `:overwrite`, `:block`
  - `:rate_limit_ms` - Minimum time between chunks in ms
  - `:batch_config` - Batching configuration (triggers advanced mode)
  - `:track_detailed_metrics` - Enable detailed metrics tracking (triggers advanced mode)

  ### Tesla Mode (future)
  - `:use_tesla` - Force Tesla middleware mode (experimental)

  ## Examples

  ```elixir
  # Basic streaming (fast path)
  {:ok, stream_id} = StreamingEngine.start_stream(
    url, request, headers, callback,
    parse_chunk_fn: &MyAdapter.parse_chunk/1
  )

  # Advanced streaming with flow control
  {:ok, stream_id} = StreamingEngine.start_stream(
    url, request, headers, callback,
    parse_chunk_fn: &MyAdapter.parse_chunk/1,
    enable_flow_control: true,
    buffer_capacity: 50,
    backpressure_threshold: 0.9
  )

  # Advanced streaming with batching
  {:ok, stream_id} = StreamingEngine.start_stream(
    url, request, headers, callback,
    parse_chunk_fn: &MyAdapter.parse_chunk/1,
    enable_batching: true,
    batch_config: [
      batch_size: 5,
      batch_timeout_ms: 25,
      adaptive: true
    ]
  )

  # Combined advanced features
  {:ok, stream_id} = StreamingEngine.start_stream(
    url, request, headers, callback,
    parse_chunk_fn: &MyAdapter.parse_chunk/1,
    enable_flow_control: true,
    enable_batching: true,
    buffer_capacity: 100,
    batch_config: [batch_size: 3],
    track_detailed_metrics: true,
    on_metrics: &handle_metrics/1
  )
  ```

  ## Returns

  - `{:ok, stream_id}` - Successfully started streaming
  - `{:error, reason}` - Failed to start stream
  """
  @spec start_stream(String.t(), map(), list(), function(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def start_stream(url, request, headers, callback, options \\ []) do
    _parse_chunk_fn = Keyword.fetch!(options, :parse_chunk_fn)
    recovery_id = Keyword.get(options, :recovery_id, generate_stream_id())

    # Detect which streaming mode to use
    streaming_mode = detect_streaming_mode(options)

    Logger.debug("StreamingEngine using #{streaming_mode} mode for stream #{recovery_id}")

    result =
      case streaming_mode do
        :tesla ->
          start_tesla_stream(url, request, headers, callback, recovery_id, options)

        :enhanced ->
          EnhancedStreamingCoordinator.start_stream(url, request, headers, callback, options)

        :basic ->
          StreamingCoordinator.start_stream(url, request, headers, callback, options)
      end

    # Track the stream if successful
    case result do
      {:ok, stream_id} ->
        track_stream(stream_id, streaming_mode)
        {:ok, stream_id}

      error ->
        error
    end
  end

  @doc """
  High-level streaming function that matches StreamingCoordinator.simple_stream/1 API.

  This provides a backward-compatible interface for adapters that use the simple
  streaming pattern.

  ## Examples

  ```elixir
  StreamingEngine.simple_stream(
    url: "https://api.openai.com/v1/chat/completions",
    request: %{model: "gpt-4", messages: [...], stream: true},
    headers: [{"authorization", "Bearer sk-..."}],
    callback: callback_fn,
    parse_chunk: &MyAdapter.parse_chunk/1,
    # Advanced options (optional)
    enable_flow_control: true,
    buffer_capacity: 50
  )
  ```
  """
  @spec simple_stream(keyword()) :: {:ok, String.t()} | {:error, term()}
  def simple_stream(params) do
    url = Keyword.fetch!(params, :url)
    request = Keyword.fetch!(params, :request)
    headers = Keyword.fetch!(params, :headers)
    callback = Keyword.fetch!(params, :callback)
    parse_chunk = Keyword.fetch!(params, :parse_chunk)
    base_options = Keyword.get(params, :options, [])

    # Extract streaming-specific options from params
    streaming_options =
      params
      |> Keyword.drop([:url, :request, :headers, :callback, :parse_chunk, :options])
      |> Keyword.merge(base_options)
      |> Keyword.put(:parse_chunk_fn, parse_chunk)

    start_stream(url, request, headers, callback, streaming_options)
  end

  @doc """
  Get comprehensive status information about an active stream.

  Returns detailed status from the appropriate streaming implementation.

  ## Examples

  ```elixir
  case StreamingEngine.get_stream_status(stream_id) do
    {:ok, %{implementation: :enhanced, flow_control: flow_metrics}} ->
      IO.puts("Advanced stream with flow control active")
      
    {:ok, %{implementation: :basic, metrics: basic_metrics}} ->
      IO.puts("Basic stream active")
      
    {:error, :not_found} ->
      IO.puts("Stream not found")
  end
  ```
  """
  @spec get_stream_status(String.t()) :: {:ok, map()} | {:error, term()}
  def get_stream_status(stream_id) do
    # First check our tracker
    case get_tracked_stream(stream_id) do
      {:ok, implementation} ->
        get_tracked_stream_status(stream_id, implementation)

      {:error, :not_found} ->
        # Fallback to prefix-based detection for untracked streams
        get_untracked_stream_status(stream_id)
    end
  end

  defp get_tracked_stream_status(stream_id, implementation) do
    case implementation do
      :enhanced ->
        {:ok, %{implementation: :enhanced, stream_id: stream_id}}

      :basic ->
        {:ok, %{implementation: :basic, stream_id: stream_id}}

      :tesla ->
        get_tesla_stream_status(stream_id)
    end
  end

  defp get_tesla_stream_status(stream_id) do
    case stream_status(stream_id) do
      {:ok, status} ->
        {:ok, %{implementation: :tesla, status: status, stream_id: stream_id}}

      {:error, _} ->
        # Stream was tracked but Tesla doesn't know about it anymore
        {:ok, %{implementation: :tesla, status: :completed, stream_id: stream_id}}
    end
  end

  defp get_untracked_stream_status(stream_id) do
    Logger.warning(
      "get_stream_status called for untracked stream_id: #{stream_id}. " <>
        "The stream was likely started by directly calling a coordinator instead of StreamingEngine. " <>
        "This fallback is deprecated and will be removed in a future version."
    )

    cond do
      String.starts_with?(stream_id, "enhanced_stream_") ->
        {:ok, %{implementation: :enhanced, stream_id: stream_id}}

      String.starts_with?(stream_id, "unified_stream_") ->
        get_unified_stream_status(stream_id)

      String.starts_with?(stream_id, "stream_") ->
        get_basic_or_tesla_stream_status(stream_id)

      true ->
        {:error, :invalid_stream_id}
    end
  end

  defp get_unified_stream_status(stream_id) do
    case stream_status(stream_id) do
      {:ok, status} ->
        {:ok, %{implementation: :unified, status: status, stream_id: stream_id}}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp get_basic_or_tesla_stream_status(stream_id) do
    case stream_status(stream_id) do
      {:ok, status} ->
        {:ok, %{implementation: :tesla, status: status, stream_id: stream_id}}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Check if advanced streaming features are available.

  This can be used by adapters to conditionally enable advanced features
  based on infrastructure availability.

  ## Examples

  ```elixir
  if StreamingEngine.advanced_features_available?() do
    # Use flow control and batching
    StreamingEngine.start_stream(url, request, headers, callback,
      parse_chunk_fn: parse_fn,
      enable_flow_control: true
    )
  else
    # Fall back to basic streaming
    StreamingEngine.start_stream(url, request, headers, callback,
      parse_chunk_fn: parse_fn
    )
  end
  ```
  """
  @spec advanced_features_available?() :: boolean()
  def advanced_features_available?() do
    Code.ensure_loaded?(ExLLM.Infrastructure.Streaming.FlowController) and
      Code.ensure_loaded?(ExLLM.Providers.Shared.EnhancedStreamingCoordinator)
  end

  @doc """
  Get predefined configuration presets for different use cases.

  ## Available Presets

  - `:high_throughput` - Optimized for maximum chunk throughput
  - `:low_latency` - Optimized for minimal latency 
  - `:balanced` - Balanced throughput and latency
  - `:conservative` - Safe defaults with error recovery

  ## Examples

  ```elixir
  # Use high throughput preset
  opts = StreamingEngine.config(:high_throughput)
  StreamingEngine.start_stream(url, request, headers, callback, opts)

  # Customize a preset
  opts = StreamingEngine.config(:balanced, buffer_capacity: 200)
  StreamingEngine.start_stream(url, request, headers, callback, opts)
  ```
  """
  @spec config(atom() | keyword(), keyword()) :: keyword()
  def config(preset_or_opts, overrides \\ [])

  def config(:high_throughput, overrides) do
    [
      enable_flow_control: true,
      buffer_capacity: 200,
      backpressure_threshold: 0.9,
      rate_limit_ms: 0,
      overflow_strategy: :drop,
      enable_batching: true,
      batch_config: [
        batch_size: 10,
        batch_timeout_ms: 50,
        adaptive: true
      ]
    ]
    |> Keyword.merge(overrides)
  end

  def config(:low_latency, overrides) do
    [
      enable_flow_control: true,
      buffer_capacity: 20,
      backpressure_threshold: 0.7,
      rate_limit_ms: 0,
      overflow_strategy: :drop
      # No batching for low latency
    ]
    |> Keyword.merge(overrides)
  end

  def config(:balanced, overrides) do
    [
      enable_flow_control: true,
      buffer_capacity: 100,
      backpressure_threshold: 0.8,
      rate_limit_ms: 1,
      overflow_strategy: :drop,
      enable_batching: true,
      batch_config: [
        batch_size: 5,
        batch_timeout_ms: 25,
        adaptive: true
      ],
      track_detailed_metrics: true
    ]
    |> Keyword.merge(overrides)
  end

  def config(:conservative, overrides) do
    [
      enable_flow_control: true,
      buffer_capacity: 50,
      backpressure_threshold: 0.6,
      rate_limit_ms: 2,
      overflow_strategy: :block,
      stream_recovery: true,
      track_detailed_metrics: true
    ]
    |> Keyword.merge(overrides)
  end

  def config(custom_opts, overrides) when is_list(custom_opts) do
    # Pure custom configuration - merge custom options with overrides only
    # Note: No preset defaults are applied for custom configurations
    Keyword.merge(custom_opts, overrides)
  end

  # Private implementation

  defp detect_streaming_mode(options) do
    result =
      cond do
        # Explicit Tesla mode request
        Keyword.get(options, :use_tesla, false) ->
          :tesla

        # Advanced features trigger enhanced mode
        has_advanced_features?(options) and advanced_features_available?() ->
          :enhanced

        # Default to basic streaming
        true ->
          :basic
      end

    result
  end

  defp has_advanced_features?(options) do
    advanced_feature_keys = [
      :enable_flow_control,
      :enable_batching,
      :buffer_capacity,
      :backpressure_threshold,
      :overflow_strategy,
      :batch_config,
      :track_detailed_metrics,
      :rate_limit_ms
    ]

    result =
      Enum.any?(advanced_feature_keys, fn key ->
        has_key = Keyword.has_key?(options, key)
        value = Keyword.get(options, key)

        # Ensure the value is not false or nil for boolean keys
        feature_present =
          has_key and
            case {key, value} do
              {:track_detailed_metrics, false} -> false
              {:enable_flow_control, false} -> false
              {:enable_batching, false} -> false
              {_, nil} -> false
              {_, _} -> true
            end

        feature_present
      end)

    result
  end

  defp start_tesla_stream(url, request, headers, callback, _recovery_id, options) do
    # Extract provider and API key from options or headers
    provider = Keyword.get(options, :provider, :unknown)
    api_key = extract_api_key(headers, provider)

    # Create Tesla client
    client =
      tesla_client(
        provider: provider,
        api_key: api_key,
        enable_flow_control: Keyword.get(options, :enable_flow_control, false),
        enable_metrics: Keyword.get(options, :track_detailed_metrics, false)
      )

    # Convert to Tesla streaming options
    tesla_opts = [
      callback: callback,
      parse_chunk: Keyword.fetch!(options, :parse_chunk_fn),
      timeout: Keyword.get(options, :timeout, :timer.minutes(5))
    ]

    # Extract path from URL
    case extract_path_from_url(url) do
      {:ok, path} ->
        tesla_stream(client, path, request, tesla_opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_api_key(headers, _provider) do
    # Extract API key from authorization headers
    auth_header =
      Enum.find(headers, fn
        {"authorization", _} ->
          true

        {"x-api-key", _} ->
          true

        {key, _} when is_binary(key) ->
          String.downcase(key) in ["authorization", "x-api-key"]

        _ ->
          false
      end)

    case auth_header do
      {"authorization", "Bearer " <> token} -> token
      {"x-api-key", token} -> token
      _ -> nil
    end
  end

  defp extract_path_from_url(url) do
    # Basic URL path extraction
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) and path != "" ->
        {:ok, path}

      _ ->
        {:error, :invalid_url_path}
    end
  end

  defp generate_stream_id do
    "unified_stream_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end

  # Stream tracking helpers

  defp track_stream(stream_id, implementation) do
    Agent.update(@stream_tracker_name, fn streams ->
      Map.put(streams, stream_id, implementation)
    end)
  end

  defp get_tracked_stream(stream_id) do
    case Agent.get(@stream_tracker_name, fn streams -> Map.get(streams, stream_id) end) do
      nil -> {:error, :not_found}
      implementation -> {:ok, implementation}
    end
  end
end
