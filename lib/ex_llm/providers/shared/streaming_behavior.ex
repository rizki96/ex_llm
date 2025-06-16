defmodule ExLLM.Providers.Shared.StreamingBehavior do
  @moduledoc """
  Shared streaming behavior and utilities for ExLLM adapters.

  Provides common patterns for handling Server-Sent Events (SSE) streaming
  responses from LLM APIs. This module can be used as a behavior or just
  for its utility functions.
  """

  alias ExLLM.Types

  @doc """
  Callback for parsing a streaming chunk into an ExLLM StreamChunk.

  Each provider has a different chunk format, so adapters must implement this.
  """
  @callback parse_stream_chunk(String.t()) ::
              {:ok, Types.StreamChunk.t() | :done} | {:error, term()}

  @doc """
  Common streaming response handler that works with HTTPoison async responses.

  ## Options
  - `:timeout` - Stream timeout in milliseconds (default: 5 minutes)
  - `:buffer` - Initial buffer content (default: "")
  - `:on_error` - Error callback function

  ## Examples

      StreamingBehavior.handle_stream(ref, MyAdapter, fn chunk ->
        # Process each chunk
        send(self(), {:chunk, chunk})
      end)
  """
  @spec handle_stream(reference(), module(), function(), keyword()) ::
          {:ok, any()} | {:error, term()}
  def handle_stream(ref, adapter_module, callback, opts \\ []) do
    # 5 minutes
    timeout = Keyword.get(opts, :timeout, 300_000)
    buffer = Keyword.get(opts, :buffer, "")

    do_handle_stream(ref, adapter_module, callback, buffer, timeout, opts)
  end

  @doc """
  Parse Server-Sent Events from a data stream.

  Returns a list of parsed events and the remaining buffer.
  """
  @spec parse_sse_stream(binary(), binary()) :: {list(String.t()), binary()}
  def parse_sse_stream(data, buffer) do
    # Combine buffer with new data
    full_data = buffer <> data

    # Split by double newline (SSE event separator)
    case String.split(full_data, "\n\n", parts: 2) do
      [complete_event, rest] ->
        # Parse the complete event
        event_data = parse_sse_event(complete_event)

        # Recursively parse rest
        {more_events, final_buffer} = parse_sse_stream(rest, "")

        if event_data do
          {[event_data | more_events], final_buffer}
        else
          {more_events, final_buffer}
        end

      [incomplete] ->
        # No complete event yet, return empty list and updated buffer
        {[], incomplete}
    end
  end

  @doc """
  Create a stream chunk for text content.
  """
  @spec create_text_chunk(String.t(), keyword()) :: Types.StreamChunk.t()
  def create_text_chunk(text, opts \\ []) do
    %Types.StreamChunk{
      content: text,
      finish_reason: Keyword.get(opts, :finish_reason),
      model: Keyword.get(opts, :model),
      id: Keyword.get(opts, :id)
    }
  end

  @doc """
  Create a stream chunk for function calls.
  """
  @spec create_function_chunk(String.t(), String.t(), keyword()) :: Types.StreamChunk.t()
  def create_function_chunk(name, arguments, opts \\ []) do
    # StreamChunk doesn't have function_call field, so we put it in content
    %Types.StreamChunk{
      content: Jason.encode!(%{function_call: %{name: name, arguments: arguments}}),
      finish_reason: Keyword.get(opts, :finish_reason),
      model: Keyword.get(opts, :model),
      id: Keyword.get(opts, :id)
    }
  end

  @doc """
  Accumulate streaming chunks into a complete response.

  Useful for collecting all chunks before processing.
  """
  @spec accumulate_chunks(list(Types.StreamChunk.t())) :: map()
  def accumulate_chunks(chunks) do
    chunks
    |> Enum.reduce(%{content: "", function_calls: [], usage: nil}, fn chunk, acc ->
      acc
      |> accumulate_content(chunk)
      |> accumulate_function_calls(chunk)
      |> accumulate_usage(chunk)
    end)
    |> format_accumulated_response()
  end

  # Private functions

  defp do_handle_stream(ref, adapter_module, callback, buffer, timeout, opts) do
    receive do
      {^ref, {:chunk, chunk}} ->
        {events, new_buffer} = parse_sse_stream(chunk, buffer)

        # Process each complete event
        Enum.each(events, fn event_data ->
          case adapter_module.parse_stream_chunk(event_data) do
            {:ok, :done} ->
              # Stream completed
              :ok

            {:ok, stream_chunk} ->
              callback.(stream_chunk)

            {:error, _reason} ->
              # Log but don't fail the stream
              :ok
          end
        end)

        do_handle_stream(ref, adapter_module, callback, new_buffer, timeout, opts)

      {^ref, :done} ->
        {:ok, :completed}

      {^ref, {:error, error}} ->
        error
    after
      timeout ->
        {:error, :timeout}
    end
  end

  defp parse_sse_event(event_string) do
    event_string
    |> String.split("\n")
    |> Enum.reduce(nil, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        ["data", data] -> String.trim(data)
        _ -> acc
      end
    end)
  end

  defp accumulate_content(acc, %{content: nil}), do: acc

  defp accumulate_content(acc, %{content: content}) do
    Map.update!(acc, :content, &(&1 <> content))
  end

  defp accumulate_function_calls(acc, _chunk) do
    # StreamChunk doesn't have function_call field
    acc
  end

  defp accumulate_usage(acc, _chunk) do
    # StreamChunk doesn't have usage field
    acc
  end

  defp format_accumulated_response(%{content: "", function_calls: [fc | _]} = acc) do
    # Response with function call
    %{
      content: nil,
      function_call: fc,
      usage: acc.usage
    }
  end

  defp format_accumulated_response(acc) do
    # Text response
    %{
      content: acc.content,
      usage: acc.usage
    }
  end
end
