defmodule ExLLM.Providers.Shared.Streaming.Middleware.StreamCollector do
  @moduledoc """
  Tesla middleware for collecting and processing streaming data.

  This middleware handles the core streaming logic:
  - Collecting streaming HTTP response data
  - Processing Server-Sent Events (SSE) format
  - Maintaining stream state and buffers
  - Invoking callbacks with parsed chunks

  This is the heart of the new streaming engine, implementing the synchronous
  processing approach that replaced the problematic Task.start() spawning in
  the original StreamingCoordinator.

  ## Usage

  The middleware is automatically included in streaming clients created by
  `Streaming.Engine.client/1`. It processes the `:stream_to` option from
  Tesla's adapter to collect streaming data.

  ## Stream Context

  The middleware expects a `:stream_context` option in the Tesla client that
  contains:
  - `:stream_id` - Unique identifier for this stream
  - `:callback` - Function to invoke with parsed chunks
  - `:parse_chunk_fn` - Function to parse provider-specific chunk data
  - `:opts` - Additional streaming options

  ## State Management

  The middleware maintains stream state through the request lifecycle:
  - Text buffer for incomplete SSE lines
  - Chunk buffer for batching (if enabled)
  - Statistics (bytes processed, chunks delivered, errors)
  - Recovery information (if enabled)
  """

  @behaviour Tesla.Middleware

  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Infrastructure.Streaming.SSEParser
  alias ExLLM.Types.StreamChunk

  @impl Tesla.Middleware
  def call(%Tesla.Env{opts: opts} = env, next, _middleware_opts) do
    case Keyword.get(opts, :stream_context) do
      nil ->
        # Not a streaming request, pass through
        Tesla.run(env, next)

      stream_context ->
        # This is a streaming request, set up collection
        setup_streaming_request(env, next, stream_context)
    end
  end

  defp setup_streaming_request(env, next, stream_context) do
    stream_id = stream_context.stream_id
    Logger.debug("Setting up streaming collection for #{stream_id}")

    # Initialize stream state
    initial_state = %{
      stream_id: stream_id,
      sse_parser: SSEParser.new(),
      chunk_buffer: [],
      stats: %{
        start_time: System.monotonic_time(:millisecond),
        bytes_processed: 0,
        chunks_delivered: 0,
        errors: 0
      },
      callback: stream_context.callback,
      parse_chunk_fn: stream_context.parse_chunk_fn,
      opts: stream_context.opts
    }

    # Store initial state for the streaming process
    store_stream_state(stream_id, initial_state)

    # Execute the request with streaming collection
    case Tesla.run(env, next) do
      {:ok, response} ->
        # Start collecting streaming data
        collect_streaming_data(response, stream_context)

      {:error, _} = error ->
        cleanup_stream_state(stream_id)
        error
    end
  end

  defp collect_streaming_data(response, stream_context) do
    stream_id = stream_context.stream_id

    # Check if this is a streaming response
    case get_header_value(response.headers, "content-type") do
      "text/event-stream" <> _ ->
        Logger.debug("Collecting SSE streaming data for #{stream_id}")
        collect_sse_stream(response, stream_context)

      _ ->
        Logger.debug("Non-streaming response for #{stream_id}")
        {:ok, response}
    end
  end

  defp collect_sse_stream(response, stream_context) do
    stream_id = stream_context.stream_id

    # Set up message handling for streaming chunks
    receive_loop(stream_id)

    {:ok, response}
  end

  defp receive_loop(stream_id) do
    receive do
      {:hackney_response, _ref, {:data, data}} ->
        # Process the streaming data chunk
        process_streaming_chunk(stream_id, data)
        receive_loop(stream_id)

      {:hackney_response, _ref, :done} ->
        # Stream completed
        Logger.debug("Stream #{stream_id} completed")
        finalize_stream(stream_id)
        :ok

      {:hackney_response, _ref, {:error, reason}} ->
        # Stream error
        Logger.error("Stream #{stream_id} error: #{inspect(reason)}")
        handle_stream_error(stream_id, reason)
        {:error, reason}
    after
      30_000 ->
        # Timeout
        Logger.error("Stream #{stream_id} timeout")
        handle_stream_error(stream_id, :timeout)
        {:error, :timeout}
    end
  end

  defp process_streaming_chunk(stream_id, data) do
    case get_stream_state(stream_id) do
      nil ->
        Logger.warning("Stream state not found for #{stream_id}")
        :error

      state ->
        # Update state with new data
        updated_stats = update_in(state.stats.bytes_processed, &(&1 + byte_size(data)))

        # Process the chunk using synchronous processing (our recent fix)
        {updated_parser, new_chunk_buffer, new_stats} =
          process_stream_data_sync(
            data,
            state.sse_parser,
            state.chunk_buffer,
            state.callback,
            state.parse_chunk_fn,
            updated_stats,
            get_buffer_size(state.opts),
            state.opts
          )

        # Update stored state
        final_state = %{
          state
          | sse_parser: updated_parser,
            chunk_buffer: new_chunk_buffer,
            stats: new_stats
        }

        store_stream_state(stream_id, final_state)
        :ok
    end
  end

  @doc """
  Get the current stats for a stream.
  Used by MetricsPlug and other monitoring components.
  """
  def get_stream_stats(stream_id) do
    case get_stream_state(stream_id) do
      nil -> nil
      state -> state.stats
    end
  end

  # This uses SSEParser to process chunks of streaming data.
  defp process_stream_data_sync(
         data,
         sse_parser,
         chunk_buffer,
         callback,
         parse_chunk_fn,
         stats,
         buffer_size,
         _options
       ) do
    {events, updated_parser} = SSEParser.parse_data_events(sse_parser, data)

    {new_chunk_buffer, new_stats} =
      Enum.reduce(events, {chunk_buffer, stats}, fn event, {chunks, current_stats} ->
        process_sse_event(
          event,
          chunks,
          current_stats,
          parse_chunk_fn,
          callback,
          buffer_size
        )
      end)

    {updated_parser, new_chunk_buffer, new_stats}
  end

  defp process_sse_event(:done, chunks, stats, _parse_chunk_fn, callback, _buffer_size) do
    # [DONE] marker received, flush any remaining chunks in the buffer
    if chunks != [] do
      Enum.each(chunks, callback)
    end

    {[], update_in(stats.chunks_delivered, &(&1 + length(chunks)))}
  end

  defp process_sse_event(event_data, chunks, stats, parse_chunk_fn, callback, buffer_size)
       when is_binary(event_data) do
    case parse_chunk_fn.(event_data) do
      {:ok, :done} ->
        Logger.debug("Stream signaled done")
        {chunks, stats}

      {:ok, chunk} when is_struct(chunk, StreamChunk) ->
        handle_new_chunk_sync(chunk, chunks, stats, callback, buffer_size)

      %StreamChunk{} = chunk ->
        handle_new_chunk_sync(chunk, chunks, stats, callback, buffer_size)

      nil ->
        {chunks, stats}

      {:error, reason} ->
        Logger.debug("Failed to parse chunk: #{inspect(reason)}")
        {chunks, update_in(stats.errors, &(&1 + 1))}
    end
  end

  defp handle_new_chunk_sync(chunk, chunks, stats, callback, buffer_size) do
    new_chunks = chunks ++ [chunk]

    if length(new_chunks) >= buffer_size do
      # Flush buffer
      Enum.each(new_chunks, callback)
      {[], update_in(stats.chunks_delivered, &(&1 + length(new_chunks)))}
    else
      {new_chunks, stats}
    end
  end

  defp finalize_stream(stream_id) do
    case get_stream_state(stream_id) do
      nil ->
        :ok

      state ->
        # Flush the SSE parser for any remaining data
        {final_events, _parser} = SSEParser.flush(state.sse_parser)

        {final_chunk_buffer, final_stats} =
          Enum.reduce(final_events, {state.chunk_buffer, state.stats}, fn event,
                                                                          {chunks, stats} ->
            process_sse_event(
              event,
              chunks,
              stats,
              state.parse_chunk_fn,
              state.callback,
              get_buffer_size(state.opts)
            )
          end)

        # Flush any remaining chunks in the chunk_buffer
        if final_chunk_buffer != [] do
          Enum.each(final_chunk_buffer, state.callback)
        end

        # Send completion chunk
        completion_chunk = %StreamChunk{
          content: "",
          finish_reason: "stop"
        }

        state.callback.(completion_chunk)

        # Log final stats
        total_delivered = final_stats.chunks_delivered + length(final_chunk_buffer)
        duration = System.monotonic_time(:millisecond) - final_stats.start_time

        Logger.debug(
          "Stream #{stream_id} completed: #{total_delivered} chunks, #{final_stats.bytes_processed} bytes in #{duration}ms"
        )

        cleanup_stream_state(stream_id)
        :ok
    end
  end

  defp handle_stream_error(stream_id, reason) do
    case get_stream_state(stream_id) do
      nil ->
        :ok

      state ->
        # Create error chunk
        error_chunk = %StreamChunk{
          content: "Error: #{inspect(reason)}",
          finish_reason: "error"
        }

        state.callback.(error_chunk)
        cleanup_stream_state(stream_id)
        :ok
    end
  end

  defp get_header_value(headers, name) do
    headers
    |> Enum.find(fn {key, _value} -> String.downcase(key) == String.downcase(name) end)
    |> case do
      {_key, value} -> value
      nil -> nil
    end
  end

  defp get_buffer_size(opts) do
    Keyword.get(opts, :buffer_chunks, 1)
  end

  # Simple in-memory storage for stream state
  # In production, this might use ETS or another storage mechanism

  defp store_stream_state(stream_id, state) do
    :persistent_term.put({__MODULE__, :stream_state, stream_id}, state)
  end

  defp get_stream_state(stream_id) do
    try do
      :persistent_term.get({__MODULE__, :stream_state, stream_id})
    rescue
      ArgumentError -> nil
    end
  end

  defp cleanup_stream_state(stream_id) do
    try do
      :persistent_term.erase({__MODULE__, :stream_state, stream_id})
    rescue
      ArgumentError -> :ok
    end
  end
end
