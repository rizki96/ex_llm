defmodule ExLLM.Providers.Anthropic.StreamParseResponse do
  @moduledoc """
  Streaming response parser plug for Anthropic provider.

  This plug handles Server-Sent Events (SSE) from Anthropic's streaming API,
  parsing message events and yielding StreamChunk structs.
  """

  use ExLLM.Plug

  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Shared.HTTPClient
  alias ExLLM.Types

  @impl true
  def call(%Request{state: :executing} = request, _opts) do
    # Extract streaming option
    stream_option = get_in(request.options, [:stream])

    if stream_option do
      initiate_streaming(request)
    else
      # Not a streaming request, pass through
      request
    end
  end

  def call(request, _opts), do: request

  defp initiate_streaming(request) do
    url = request.assigns.request_url
    headers = request.assigns.request_headers
    body = request.assigns.request_body
    timeout = request.assigns[:timeout] || 60_000

    # Create a stream using the callback-based API
    stream =
      Stream.resource(
        # Start function - initiate the request
        fn ->
          parent = self()
          ref = make_ref()

          # Define callback that sends chunks to parent process
          callback = fn chunk ->
            send(parent, {ref, :chunk, chunk})
          end

          # Start the streaming request
          case HTTPClient.stream_request(url, body, headers, callback,
                 timeout: timeout,
                 provider: request.provider
               ) do
            {:ok, _stream_result} ->
              # Return ref to identify chunks from this stream
              ref

            {:error, error} ->
              # Send error and halt
              send(parent, {ref, :error, error})
              nil
          end
        end,
        # Next function - receive chunks
        fn
          nil ->
            {:halt, nil}

          ref ->
            receive do
              {^ref, :chunk, chunk} ->
                # Continue receiving, yield chunk
                {[chunk], ref}

              {^ref, :error, error} ->
                # Halt on error
                Logger.error("Streaming error: #{inspect(error)}")
                {:halt, nil}
            after
              timeout ->
                # Timeout waiting for chunk
                Logger.error("Streaming timeout after #{timeout}ms")
                {:halt, nil}
            end
        end,
        # Cleanup function
        fn _ref -> :ok end
      )

    # Convert to StreamChunk stream
    chunk_stream =
      stream
      |> Stream.transform({"", nil}, &process_sse_chunk/2)
      |> Stream.map(&parse_anthropic_chunk(&1, request.provider))
      |> Stream.reject(&is_nil/1)

    request
    |> Request.assign(:response_stream, chunk_stream)
    |> Request.put_state(:streaming)
  end

  defp process_sse_chunk(chunk, {buffer, current_event}) do
    # Accumulate chunks and extract complete SSE events
    new_buffer = buffer <> chunk
    {events, remaining, new_event} = extract_sse_events(new_buffer, current_event)
    {events, {remaining, new_event}}
  end

  defp extract_sse_events(buffer, current_event) do
    # Process line by line for Anthropic's multi-line event format
    lines = String.split(buffer, "\n")

    {events, current_event, remaining_lines} =
      process_lines(lines, current_event, [])

    remaining = Enum.join(remaining_lines, "\n")
    {events, remaining, current_event}
  end

  defp process_lines([], current_event, events) do
    {Enum.reverse(events), current_event, []}
  end

  defp process_lines([line | rest], current_event, events) do
    cond do
      # Start of new event
      String.starts_with?(line, "event: ") ->
        event_type = String.trim_leading(line, "event: ")
        process_lines(rest, %{type: event_type, data: ""}, events)

      # Data line
      String.starts_with?(line, "data: ") && current_event ->
        data = String.trim_leading(line, "data: ")
        updated_event = %{current_event | data: current_event.data <> data}
        process_lines(rest, updated_event, events)

      # Empty line - end of event
      line == "" && current_event ->
        process_lines(rest, nil, [current_event | events])

      # Skip other lines
      true ->
        process_lines(rest, current_event, events)
    end
  end

  defp parse_anthropic_chunk(%{type: type, data: data}, _provider) do
    case type do
      "message_start" ->
        # Initial message, no content yet
        nil

      "content_block_start" ->
        # Content block starting, no content yet
        nil

      "content_block_delta" ->
        # Parse delta content
        case Jason.decode(data) do
          {:ok, %{"delta" => %{"text" => text}}} ->
            %Types.StreamChunk{
              content: text,
              finish_reason: nil
            }

          _ ->
            nil
        end

      "content_block_stop" ->
        # Content block ended, no action
        nil

      "message_delta" ->
        # Check for stop reason
        case Jason.decode(data) do
          {:ok, %{"delta" => %{"stop_reason" => reason}}} when not is_nil(reason) ->
            %Types.StreamChunk{
              content: nil,
              finish_reason: reason
            }

          _ ->
            nil
        end

      "message_stop" ->
        # Final message stop
        %Types.StreamChunk{
          content: nil,
          finish_reason: "stop"
        }

      _ ->
        nil
    end
  end

  defp parse_anthropic_chunk(_, _), do: nil
end
