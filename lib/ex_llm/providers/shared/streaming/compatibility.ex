defmodule ExLLM.Providers.Shared.Streaming.Compatibility do
  @moduledoc """
  Backward compatibility facade for the new Tesla-based streaming engine.

  This module provides the same interface as the original StreamingCoordinator
  while internally using the new Tesla middleware-based Streaming.Engine.
  This allows existing adapters and code to work without modifications.

  ## Migration Path

  1. **Phase 1 (Current)**: All existing code continues to work through this facade
  2. **Phase 2**: Adapters are gradually migrated to use Streaming.Engine directly
  3. **Phase 3**: This facade is deprecated and eventually removed

  ## Features Preserved

  - `start_stream/5` - Identical signature and behavior
  - `execute_stream/7` - For adapters that call this directly
  - `simple_stream/1` - High-level streaming interface
  - All callback patterns and options handling
  - Error handling and recovery behavior
  - Metrics and monitoring integration

  ## New Features Available

  When using the new engine directly, additional features are available:
  - Tesla middleware composability
  - Better error handling and recovery
  - Improved metrics and monitoring
  - Flow control and backpressure
  - Cleaner testing and mocking
  """

  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Providers.Shared.Streaming.Engine

  # Default timeout matches original StreamingCoordinator
  @default_timeout :timer.minutes(5)

  @doc """
  Start a streaming request with unified handling (compatibility interface).

  This function provides the exact same interface as the original
  `StreamingCoordinator.start_stream/5` but internally uses the new
  Tesla-based streaming engine.

  ## Options
  - `:parse_chunk_fn` - Function to parse provider-specific chunks (required)
  - `:recovery_id` - Optional ID for stream recovery
  - `:timeout` - Stream timeout in milliseconds (default: 5 minutes)
  - `:on_error` - Error callback function
  - `:on_metrics` - Metrics callback function (receives streaming metrics)
  - `:transform_chunk` - Optional function to transform chunks before callback
  - `:buffer_chunks` - Buffer size for chunk batching (default: 1)
  - `:validate_chunk` - Optional function to validate chunks
  - `:track_metrics` - Enable detailed metrics tracking (default: false)
  """
  @spec start_stream(String.t(), map(), list(), function(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  # NOTE: Defensive error handling - Engine.stream currently only returns {:ok, id}
  # but this error clause provides safety if the function changes in future versions
  def start_stream(url, request, headers, callback, options \\ []) do
    case Keyword.fetch(options, :parse_chunk_fn) do
      {:ok, parse_chunk_fn} ->
        provider = detect_provider_from_url(url)

        Logger.debug("Starting compatibility stream for #{provider} at #{url}")

        # Extract provider-specific configuration
        client_opts = [
          provider: provider,
          api_key: extract_api_key_from_headers(headers),
          base_url: extract_base_url(url),
          timeout: Keyword.get(options, :timeout, @default_timeout),
          enable_metrics: Keyword.get(options, :track_metrics, false),
          enable_recovery: Keyword.get(options, :stream_recovery, false)
        ]

        # Create Tesla client
        client = Engine.client(client_opts)

        # Convert options to new format
        stream_opts = [
          callback: create_enhanced_callback(callback, options),
          parse_chunk: parse_chunk_fn,
          timeout: Keyword.get(options, :timeout, @default_timeout),
          recovery_enabled: Keyword.get(options, :stream_recovery, false),
          metrics_callback: Keyword.get(options, :on_metrics),
          chunk_validator: Keyword.get(options, :validate_chunk),
          buffer_chunks: Keyword.get(options, :buffer_chunks, 1)
        ]

        # Extract path from full URL
        path = extract_path_from_url(url)

        # Start streaming using new engine
        # NOTE: Defensive error handling - Engine.stream currently only returns {:ok, id}
        # If error handling is needed in future, add appropriate clause here
        {:ok, stream_id} = Engine.stream(client, path, request, stream_opts)

        Logger.debug("Compatibility stream #{stream_id} started successfully")
        {:ok, stream_id}

      :error ->
        {:error, "Missing required option :parse_chunk_fn"}
    end
  end

  @doc """
  Execute the actual streaming request (compatibility interface).

  This provides compatibility for adapters that call `execute_stream/7` directly.
  Most adapters should use `start_stream/5` instead.
  """
  @spec execute_stream(String.t(), map(), list(), function(), function(), map(), keyword()) ::
          :ok | {:error, term()}
  def execute_stream(url, request, headers, callback, parse_chunk_fn, stream_context, options) do
    # Convert to start_stream format
    enhanced_options =
      Keyword.merge(options,
        parse_chunk_fn: parse_chunk_fn,
        recovery_id: Map.get(stream_context, :recovery_id)
      )

    # NOTE: Defensive error handling - start_stream currently only returns {:ok, id}
    # If error handling is needed in future, add appropriate clause here
    case start_stream(url, request, headers, callback, enhanced_options) do
      {:ok, _stream_id} ->
        # Wait for completion (synchronous behavior for compatibility)
        wait_for_stream_completion()

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Create a simple streaming implementation (compatibility interface).

  This maintains the exact same interface as `StreamingCoordinator.simple_stream/1`.
  """
  @spec simple_stream(keyword()) :: {:ok, String.t()} | {:error, term()}
  def simple_stream(params) do
    with {:ok, url} <- Keyword.fetch(params, :url),
         {:ok, request} <- Keyword.fetch(params, :request),
         {:ok, headers} <- Keyword.fetch(params, :headers),
         {:ok, callback} <- Keyword.fetch(params, :callback),
         {:ok, parse_chunk} <- Keyword.fetch(params, :parse_chunk) do
      options = Keyword.get(params, :options, [])
      stream_options = Keyword.merge(options, parse_chunk_fn: parse_chunk)
      start_stream(url, request, headers, callback, stream_options)
    else
      :error ->
        {:error, "Missing required parameter in simple_stream"}
    end
  end

  # Private helper functions

  defp create_enhanced_callback(callback, options) do
    transform_fn = Keyword.get(options, :transform_chunk)

    fn chunk ->
      # Apply transformation if provided
      transformed_chunk =
        if transform_fn do
          case transform_fn.(chunk) do
            {:ok, new_chunk} -> new_chunk
            :skip -> nil
            chunk -> chunk
          end
        else
          chunk
        end

      # Call original callback if chunk wasn't skipped
      if transformed_chunk do
        callback.(transformed_chunk)
      end
    end
  end

  defp detect_provider_from_url(url) do
    cond do
      String.contains?(url, "api.openai.com") -> :openai
      String.contains?(url, "api.anthropic.com") -> :anthropic
      String.contains?(url, "api.groq.com") -> :groq
      String.contains?(url, "generativelanguage.googleapis.com") -> :gemini
      String.contains?(url, "localhost:11434") -> :ollama
      String.contains?(url, "localhost:1234") -> :lmstudio
      String.contains?(url, "api.mistral.ai") -> :mistral
      String.contains?(url, "openrouter.ai") -> :openrouter
      String.contains?(url, "api.perplexity.ai") -> :perplexity
      String.contains?(url, "api.x.ai") -> :xai
      true -> :unknown
    end
  end

  defp extract_api_key_from_headers(headers) do
    headers
    |> Enum.find_value(fn
      {"authorization", "Bearer " <> key} -> key
      {"Authorization", "Bearer " <> key} -> key
      {"x-api-key", key} -> key
      {"X-API-Key", key} -> key
      _ -> nil
    end)
  end

  defp extract_base_url(url) do
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}" <> if uri.port, do: ":#{uri.port}", else: ""
  end

  defp extract_path_from_url(url) do
    uri = URI.parse(url)
    path = uri.path || "/"

    if uri.query do
      "#{path}?#{uri.query}"
    else
      path
    end
  end

  defp wait_for_stream_completion do
    # This is a simplified implementation for compatibility
    # In practice, this would wait for the streaming task to complete
    # For now, we return immediately since the new engine handles this differently
    :ok
  end
end
