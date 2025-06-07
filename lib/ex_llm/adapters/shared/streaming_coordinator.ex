defmodule ExLLM.Adapters.Shared.StreamingCoordinator do
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

  alias ExLLM.{Types, Logger}
  alias ExLLM.Adapters.Shared.HTTPClient

  @doc """
  Start a streaming request with unified handling.

  ## Options
  - `:parse_chunk_fn` - Function to parse provider-specific chunks (required)
  - `:recovery_id` - Optional ID for stream recovery
  - `:timeout` - Stream timeout in milliseconds (default: 5 minutes)
  - `:on_error` - Error callback function
  """
  def start_stream(url, request, headers, callback, options \\ []) do
    parse_chunk_fn = Keyword.fetch!(options, :parse_chunk_fn)
    recovery_id = Keyword.get(options, :recovery_id, generate_stream_id())

    Task.async(fn ->
      execute_stream(url, request, headers, callback, parse_chunk_fn, recovery_id, options)
    end)

    {:ok, recovery_id}
  end

  @doc """
  Execute the actual streaming request with unified SSE handling.
  """
  def execute_stream(url, request, headers, callback, parse_chunk_fn, recovery_id, options) do
    # Save stream state for potential recovery
    if Keyword.get(options, :stream_recovery, false) do
      save_stream_state(recovery_id, url, request, headers, options)
    end

    # Use HTTPClient for consistent request handling
    stream_opts = [
      headers: headers,
      receive_timeout: Keyword.get(options, :timeout, 300_000),
      into: create_stream_collector(callback, parse_chunk_fn, recovery_id, options)
    ]

    case HTTPClient.post_stream(url, request, stream_opts) do
      {:ok, _response} ->
        # Send completion chunk
        callback.(%Types.StreamChunk{
          content: "",
          finish_reason: "stop"
        })

        # Clean up recovery state
        cleanup_stream_state(recovery_id)
        :ok

      {:error, reason} ->
        Logger.error("Stream error for #{recovery_id}: #{inspect(reason)}")

        # Handle error with optional recovery
        handle_stream_error(reason, callback, recovery_id, options)
    end
  end

  @doc """
  Create a stream collector function for Req's into option.
  """
  def create_stream_collector(callback, parse_chunk_fn, recovery_id, options) do
    # Return a function that initializes the accumulator
    fn
      {:data, data}, acc ->
        # Initialize accumulator if needed
        {buffer, chunk_count} =
          case acc do
            {_, _} = state -> state
            _ -> {"", 0}
          end

        {new_buffer, new_count} =
          process_stream_data(
            data,
            buffer,
            callback,
            parse_chunk_fn,
            recovery_id,
            chunk_count,
            options
          )

        {:cont, {new_buffer, new_count}}

      {:error, reason}, _acc ->
        Logger.error("Stream collector error: #{inspect(reason)}")
        {:halt, {:error, reason}}
    end
  end

  @doc """
  Process streaming data with unified SSE parsing.
  """
  def process_stream_data(
        data,
        buffer,
        callback,
        parse_chunk_fn,
        recovery_id,
        chunk_count,
        options
      ) do
    full_data = buffer <> data

    # Split by newlines for SSE processing
    lines = String.split(full_data, "\n")
    {complete_lines, [last_line]} = Enum.split(lines, -1)

    # Track chunks for recovery
    chunks_received =
      Enum.reduce(complete_lines, chunk_count, fn line, count ->
        case parse_sse_line(line) do
          {:data, event_data} ->
            handle_event_data(event_data, callback, parse_chunk_fn, recovery_id, count, options)
            count + 1

          :done ->
            # Stream completed
            Logger.debug("Stream #{recovery_id} completed after #{count} chunks")
            count

          :skip ->
            count
        end
      end)

    {last_line, chunks_received}
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

  defp handle_event_data(data, callback, parse_chunk_fn, recovery_id, chunk_count, options) do
    case parse_chunk_fn.(data) do
      {:ok, :done} ->
        Logger.debug("Stream #{recovery_id} signaled done")

      {:ok, chunk} when is_struct(chunk, Types.StreamChunk) ->
        # Track chunk for recovery if enabled
        if Keyword.get(options, :stream_recovery, false) do
          save_stream_chunk(recovery_id, chunk, chunk_count)
        end

        callback.(chunk)

      {:error, reason} ->
        Logger.debug("Failed to parse chunk in stream #{recovery_id}: #{inspect(reason)}")
        # Continue processing other chunks
    end
  end

  defp handle_stream_error(reason, callback, recovery_id, options) do
    # Create an error chunk without the error field
    error_chunk = %Types.StreamChunk{
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
      {:timeout, _} -> true
      {:closed, _} -> true
      {:network_error, _} -> true
      _ -> false
    end
  end

  # Stream recovery state management

  defp save_stream_state(recovery_id, _url, _request, _headers, _options) do
    # This would integrate with ExLLM.StreamRecovery
    # For now, we'll just log
    Logger.debug("Saving stream state for recovery: #{recovery_id}")
  end

  defp save_stream_chunk(recovery_id, _chunk, chunk_count) do
    # This would integrate with ExLLM.StreamRecovery
    Logger.debug("Saving chunk #{chunk_count} for stream #{recovery_id}")
  end

  defp mark_stream_recoverable(recovery_id, reason) do
    # This would integrate with ExLLM.StreamRecovery
    Logger.info("Stream #{recovery_id} marked as recoverable: #{inspect(reason)}")
  end

  defp cleanup_stream_state(recovery_id) do
    # This would integrate with ExLLM.StreamRecovery
    Logger.debug("Cleaning up stream state: #{recovery_id}")
  end

  defp generate_stream_id do
    "stream_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
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
