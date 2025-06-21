defmodule ExLLM.Providers.Shared.StreamingCoordinator do
  @moduledoc """
  Unified streaming coordinator for all LLM adapters.

  This module provides a consistent streaming implementation that eliminates
  code duplication across adapters. It handles:

  - Task management for async streaming
  - SSE (Server-Sent Events) parsing
  - Chunk buffering and processing
  - Error recovery integration
  - Provider-agnostic streaming patterns
  """

  alias ExLLM.Providers.Shared.HTTPClient
  alias ExLLM.Types

  alias ExLLM.Infrastructure.Logger

  @default_timeout :timer.minutes(5)
  # Log metrics every 1 second during streaming
  @metrics_interval 1000

  @doc """
  Start a streaming request with unified handling.

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
  def start_stream(url, request, headers, callback, options \\ []) do
    parse_chunk_fn = Keyword.fetch!(options, :parse_chunk_fn)
    recovery_id = Keyword.get(options, :recovery_id, generate_stream_id())

    # Initialize stream context
    stream_context = %{
      recovery_id: recovery_id,
      start_time: System.monotonic_time(:millisecond),
      chunk_count: 0,
      byte_count: 0,
      error_count: 0,
      provider: Keyword.get(options, :provider, :unknown)
    }

    Task.async(fn ->
      execute_stream(url, request, headers, callback, parse_chunk_fn, stream_context, options)
    end)

    {:ok, recovery_id}
  end

  @doc """
  Execute the actual streaming request with unified SSE handling.
  """
  def execute_stream(url, request, headers, callback, parse_chunk_fn, stream_context, options) do
    recovery_id = stream_context.recovery_id

    # Save stream state for potential recovery
    if Keyword.get(options, :stream_recovery, false) do
      save_stream_state(recovery_id, url, request, headers, options)
    end

    # Setup metrics tracking
    metrics_pid =
      if Keyword.get(options, :track_metrics, false) do
        start_metrics_tracker(stream_context, options)
      end

    # Create enhanced callback with transformations
    enhanced_callback = create_enhanced_callback(callback, stream_context, options)

    # Use HTTPClient for consistent request handling
    stream_opts = [
      headers: headers,
      receive_timeout: Keyword.get(options, :timeout, @default_timeout),
      into: create_stream_collector(enhanced_callback, parse_chunk_fn, stream_context, options)
    ]

    result =
      case HTTPClient.post_stream(url, request, stream_opts) do
        {:ok, _response} ->
          # Send completion chunk
          enhanced_callback.(%ExLLM.Types.StreamChunk{
            content: "",
            finish_reason: "stop"
          })

          # Report final metrics
          report_final_metrics(stream_context, metrics_pid, options)

          # Clean up recovery state
          cleanup_stream_state(recovery_id)
          :ok

        {:error, reason} ->
          Logger.error("Stream error for #{recovery_id}: #{inspect(reason)}")

          # Handle error with optional recovery
          handle_stream_error(reason, enhanced_callback, stream_context, options)
      end

    # Stop metrics tracker if running
    if metrics_pid, do: Process.exit(metrics_pid, :normal)

    result
  end

  @doc """
  Create a stream collector function for Req's into option.
  """
  def create_stream_collector(callback, parse_chunk_fn, stream_context, options) do
    # Initialize chunk buffer for batching
    buffer_size = Keyword.get(options, :buffer_chunks, 1)

    # Simple collector that accumulates data for Req and processes callbacks
    fn
      {:data, data}, acc ->
        # Initialize accumulator if needed - binary for response body
        body =
          case acc do
            binary when is_binary(binary) -> binary
            _ -> ""
          end

        # Process stream data for callbacks (side effects)
        # We'll handle this in a separate process to avoid affecting the accumulator
        Task.start(fn ->
          process_stream_data(
            data,
            # text_buffer
            "",
            # chunk_buffer  
            [],
            callback,
            parse_chunk_fn,
            stream_context,
            buffer_size,
            options
          )
        end)

        # Accumulate the raw data as binary for Req
        {:cont, body <> data}

      {:error, reason}, _acc ->
        Logger.error("Stream collector error: #{inspect(reason)}")
        {:halt, {:error, reason}}
    end
  end

  @doc """
  Process streaming data with unified SSE parsing and buffering.
  """
  def process_stream_data(
        data,
        text_buffer,
        chunk_buffer,
        callback,
        parse_chunk_fn,
        stats,
        buffer_size,
        options
      ) do
    full_data = text_buffer <> data
    recovery_id = stats.recovery_id

    # Update byte count
    stats = update_stream_stats(stats, :byte_count, byte_size(data))

    # Split by newlines for SSE processing
    lines = String.split(full_data, "\n")
    {complete_lines, [last_line]} = Enum.split(lines, -1)

    # Process lines and accumulate chunks
    {new_chunk_buffer, new_stats} =
      Enum.reduce(complete_lines, {chunk_buffer, stats}, fn line, acc ->
        process_stream_line(
          line,
          acc,
          parse_chunk_fn,
          recovery_id,
          options,
          callback,
          buffer_size
        )
      end)

    {last_line, new_chunk_buffer, new_stats}
  end

  defp process_stream_line(
         line,
         {chunks, st},
         parse_chunk_fn,
         recovery_id,
         options,
         callback,
         buffer_size
       ) do
    case parse_sse_line(line) do
      {:data, event_data} ->
        process_event_data(
          event_data,
          chunks,
          st,
          parse_chunk_fn,
          recovery_id,
          options,
          callback,
          buffer_size
        )

      :done ->
        handle_stream_done(chunks, st, callback, recovery_id)

      :skip ->
        {chunks, st}
    end
  end

  defp process_event_data(
         event_data,
         chunks,
         st,
         parse_chunk_fn,
         recovery_id,
         options,
         callback,
         buffer_size
       ) do
    case handle_event_data(event_data, parse_chunk_fn, recovery_id, st, options) do
      {:ok, chunk} ->
        handle_new_chunk(chunk, chunks, st, callback, buffer_size)

      :skip ->
        {chunks, st}
    end
  end

  defp handle_new_chunk(chunk, chunks, st, callback, buffer_size) do
    new_chunks = chunks ++ [chunk]

    if length(new_chunks) >= buffer_size do
      flush_chunk_buffer(new_chunks, callback, st)
      {[], update_stream_stats(st, :chunk_count, length(new_chunks))}
    else
      {new_chunks, st}
    end
  end

  defp handle_stream_done(chunks, st, callback, recovery_id) do
    if chunks != [] do
      flush_chunk_buffer(chunks, callback, st)
    end

    Logger.debug("Stream #{recovery_id} completed after #{st.chunk_count} chunks")
    {[], st}
  end

  @doc """
  Parse a single SSE line according to the SSE specification.
  """
  def parse_sse_line(line) do
    line = String.trim(line)

    cond do
      line == "" ->
        :skip

      String.starts_with?(line, "data: [DONE]") ->
        :done

      String.starts_with?(line, "data: ") ->
        data = String.replace_prefix(line, "data: ", "")
        {:data, data}

      String.starts_with?(line, "event: ") ->
        # Could handle custom events here
        :skip

      String.starts_with?(line, ":") ->
        # SSE comment, ignore
        :skip

      true ->
        :skip
    end
  end

  defp handle_event_data(data, parse_chunk_fn, recovery_id, stats, options) do
    case parse_chunk_fn.(data) do
      {:ok, :done} ->
        Logger.debug("Stream #{recovery_id} signaled done")
        :skip

      {:ok, chunk} when is_struct(chunk, Types.StreamChunk) ->
        # Validate chunk if validator provided
        if validator = Keyword.get(options, :validate_chunk) do
          case validator.(chunk) do
            :ok ->
              save_chunk_if_recovery_enabled(recovery_id, chunk, stats.chunk_count, options)
              {:ok, chunk}

            {:error, reason} ->
              Logger.warning("Invalid chunk rejected: #{inspect(reason)}")
              :skip
          end
        else
          save_chunk_if_recovery_enabled(recovery_id, chunk, stats.chunk_count, options)
          {:ok, chunk}
        end

      # Handle direct StreamChunk return (new parse functions)
      %ExLLM.Types.StreamChunk{} = chunk ->
        # Validate chunk if validator provided
        if validator = Keyword.get(options, :validate_chunk) do
          case validator.(chunk) do
            :ok ->
              save_chunk_if_recovery_enabled(recovery_id, chunk, stats.chunk_count, options)
              {:ok, chunk}

            {:error, reason} ->
              Logger.warning("Invalid chunk rejected: #{inspect(reason)}")
              :skip
          end
        else
          save_chunk_if_recovery_enabled(recovery_id, chunk, stats.chunk_count, options)
          {:ok, chunk}
        end

      # Handle nil return (skip chunk)
      nil ->
        :skip

      {:error, reason} ->
        Logger.debug("Failed to parse chunk in stream #{recovery_id}: #{inspect(reason)}")
        :skip
    end
  end

  defp save_chunk_if_recovery_enabled(recovery_id, chunk, chunk_count, options) do
    if Keyword.get(options, :stream_recovery, false) do
      save_stream_chunk(recovery_id, chunk, chunk_count)
    end
  end

  defp handle_stream_error(reason, callback, stream_context, options) do
    recovery_id = stream_context.recovery_id

    # Create an error chunk without the error field
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
      {:api_error, _} -> false
      {:authentication_error, _} -> false
      {:rate_limit_error, _} -> false
      {:service_unavailable, _} -> false
      {:validation, _, _} -> false
    end
  end

  # Stream recovery state management

  defp save_stream_state(recovery_id, url, request, headers, options) do
    if stream_recovery_enabled?() do
      provider = Keyword.get(options, :provider, :unknown)
      messages = extract_messages_from_request(request, provider)

      # Initialize recovery with StreamRecovery module
      {:ok, _} = ExLLM.Core.Streaming.Recovery.init_recovery(provider, messages, options)
      Logger.debug("Stream recovery initialized for #{recovery_id}")

      # Store additional context for recovery (currently not used)
      _recovery_context = %{
        url: url,
        headers: sanitize_headers(headers),
        request_template: sanitize_request(request),
        original_options: options
      }

      # ExLLM.Core.Streaming.Recovery.update_context(recovery_id, recovery_context)
      # Note: update_context function doesn't exist in StreamRecovery module
    end
  end

  defp save_stream_chunk(recovery_id, chunk, chunk_count) do
    if stream_recovery_enabled?() do
      # record_chunk uses GenServer.cast and always returns :ok
      ExLLM.Core.Streaming.Recovery.record_chunk(recovery_id, chunk)
      Logger.debug("Saved chunk #{chunk_count} for stream #{recovery_id}")
    end
  end

  defp mark_stream_recoverable(recovery_id, reason) do
    if stream_recovery_enabled?() do
      case ExLLM.Core.Streaming.Recovery.record_error(recovery_id, reason) do
        {:ok, recoverable} ->
          if recoverable do
            Logger.info("Stream #{recovery_id} marked as recoverable: #{inspect(reason)}")
          else
            Logger.debug(
              "Stream #{recovery_id} error recorded (not recoverable): #{inspect(reason)}"
            )
          end

        {:error, error} ->
          Logger.warning("Failed to mark stream as recoverable: #{inspect(error)}")
      end
    end
  end

  defp cleanup_stream_state(recovery_id) do
    if stream_recovery_enabled?() do
      # complete_stream uses GenServer.cast and always returns :ok
      ExLLM.Core.Streaming.Recovery.complete_stream(recovery_id)
      Logger.debug("Stream recovery state cleaned up: #{recovery_id}")
    end
  end

  # Helper functions for stream recovery

  defp stream_recovery_enabled? do
    # Check if StreamRecovery process is running
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

  defp sanitize_headers(headers) do
    # Remove sensitive headers like API keys
    headers
    |> Enum.reject(fn {key, _value} ->
      key_lower = String.downcase(key)
      String.contains?(key_lower, ["authorization", "api-key", "x-api-key"])
    end)
    |> Enum.into(%{})
  end

  defp sanitize_request(request) when is_map(request) do
    # Remove actual message content but keep structure
    request
    |> Map.delete("messages")
    |> Map.delete("contents")
    |> Map.put("_structure", %{
      messages_count: length(Map.get(request, "messages", [])),
      has_system: has_system_message?(request)
    })
  end

  defp sanitize_request(request), do: request

  defp has_system_message?(%{"messages" => messages}) when is_list(messages) do
    Enum.any?(messages, fn msg -> Map.get(msg, "role") == "system" end)
  end

  defp has_system_message?(_), do: false

  defp generate_stream_id do
    "stream_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end

  # New helper functions for enhanced streaming

  defp create_enhanced_callback(callback, _stream_context, options) do
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

  defp flush_chunk_buffer(chunks, callback, _stats) do
    # For buffered chunks, we can aggregate or process them together
    Enum.each(chunks, fn chunk ->
      callback.(chunk)
    end)
  end

  defp update_stream_stats(stats, key, increment) do
    Map.update(stats, key, increment, &(&1 + increment))
  end

  defp start_metrics_tracker(stream_context, options) do
    parent = self()
    on_metrics = Keyword.get(options, :on_metrics)

    spawn(fn ->
      track_metrics_loop(parent, stream_context, on_metrics)
    end)
  end

  defp track_metrics_loop(parent, initial_context, on_metrics) do
    receive do
      {:update_metrics, updates} ->
        new_context =
          Enum.reduce(updates, initial_context, fn {k, v}, ctx ->
            Map.put(ctx, k, v)
          end)

        track_metrics_loop(parent, new_context, on_metrics)

      :stop ->
        :ok
    after
      @metrics_interval ->
        if on_metrics && Process.alive?(parent) do
          metrics = calculate_current_metrics(initial_context)
          on_metrics.(metrics)
        end

        track_metrics_loop(parent, initial_context, on_metrics)
    end
  end

  defp calculate_current_metrics(context) do
    current_time = System.monotonic_time(:millisecond)
    duration_ms = current_time - context.start_time

    %{
      stream_id: context.recovery_id,
      provider: context.provider,
      duration_ms: duration_ms,
      chunks_received: context.chunk_count,
      bytes_received: context.byte_count,
      errors: context.error_count,
      chunks_per_second: calculate_rate(context.chunk_count, duration_ms),
      bytes_per_second: calculate_rate(context.byte_count, duration_ms)
    }
  end

  defp calculate_rate(count, duration_ms) when duration_ms > 0 do
    Float.round(count * 1000 / duration_ms, 2)
  end

  defp calculate_rate(_, _), do: 0.0

  defp report_final_metrics(stream_context, metrics_pid, options) do
    if metrics_pid do
      send(metrics_pid, :stop)
    end

    if on_metrics = Keyword.get(options, :on_metrics) do
      final_metrics = calculate_current_metrics(stream_context)
      on_metrics.(Map.put(final_metrics, :status, :completed))
    end
  end

  @doc """
  Create a simple streaming implementation for adapters.

  This is a high-level function that adapters can use to implement
  streaming with minimal boilerplate.

  ## Example

      def stream_chat(messages, options, callback) do
        base_url = "https://api.openai.com/v1"
        api_key = "your-api-key"
        
        StreamingCoordinator.simple_stream(
          url: "\#{base_url}/chat/completions",
          request: build_request(messages, options),
          headers: build_headers(api_key),
          callback: callback,
          parse_chunk: &parse_openai_chunk/1,
          options: options
        )
      end
  """
  def simple_stream(params) do
    url = Keyword.fetch!(params, :url)
    request = Keyword.fetch!(params, :request)
    headers = Keyword.fetch!(params, :headers)
    callback = Keyword.fetch!(params, :callback)
    parse_chunk = Keyword.fetch!(params, :parse_chunk)
    options = Keyword.get(params, :options, [])

    stream_options = Keyword.merge(options, parse_chunk_fn: parse_chunk)

    start_stream(url, request, headers, callback, stream_options)
  end
end
