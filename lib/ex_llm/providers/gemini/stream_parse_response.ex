defmodule ExLLM.Providers.Gemini.StreamParseResponse do
  @moduledoc """
  Streaming response parser plug for Gemini provider.

  Gemini uses a multiline JSON format where each chunk is prefixed with "data: "
  and contains complete candidate content.
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
            {:ok, :streaming} ->
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

    # Convert raw stream to StreamChunk stream
    chunk_stream =
      stream
      |> Stream.transform("", &process_gemini_chunk/2)
      |> Stream.map(&parse_gemini_chunk(&1, request.provider))
      |> Stream.reject(&is_nil/1)

    request
    |> Request.assign(:response_stream, chunk_stream)
    |> Request.put_state(:streaming)
  end

  defp process_gemini_chunk(chunk, buffer) do
    # Accumulate chunks and extract complete data events
    new_buffer = buffer <> chunk
    {events, remaining} = extract_data_events(new_buffer)
    {events, remaining}
  end

  defp extract_data_events(buffer) do
    # Split by newline to find "data: " prefixed lines
    lines = String.split(buffer, "\n")

    {events, remaining_lines} = process_data_lines(lines, [])
    remaining = Enum.join(remaining_lines, "\n")

    {Enum.reverse(events), remaining}
  end

  defp process_data_lines([], events) do
    {events, []}
  end

  defp process_data_lines([line | rest], events) do
    cond do
      String.starts_with?(line, "data: ") ->
        # Extract JSON data
        json_data = String.trim_leading(line, "data: ")

        # Check if this is a complete JSON object
        case Jason.decode(json_data) do
          {:ok, _} ->
            # Complete JSON, add to events
            process_data_lines(rest, [json_data | events])

          {:error, _} ->
            # Incomplete JSON, need to accumulate more
            # This handles multiline JSON
            {accumulated, remaining} = accumulate_json(json_data, rest)

            if accumulated do
              process_data_lines(remaining, [accumulated | events])
            else
              # Couldn't complete JSON, return what we have
              {events, [line | rest]}
            end
        end

      line == "" ->
        # Empty line, skip
        process_data_lines(rest, events)

      true ->
        # Not a data line, keep in buffer
        {events, [line | rest]}
    end
  end

  defp accumulate_json(partial, lines) do
    # Try to accumulate lines until we have valid JSON
    accumulate_json(partial, lines, 0)
  end

  defp accumulate_json(_json, [], _depth) do
    # No more lines, return incomplete
    {nil, []}
  end

  defp accumulate_json(json, [line | rest], depth) when depth < 10 do
    # Add line to JSON
    combined = json <> "\n" <> line

    case Jason.decode(combined) do
      {:ok, _} ->
        # Valid JSON now
        {combined, rest}

      {:error, _} ->
        # Still incomplete, continue
        accumulate_json(combined, rest, depth + 1)
    end
  end

  defp accumulate_json(_json, lines, _depth) do
    # Too deep, give up
    {nil, lines}
  end

  defp parse_gemini_chunk(json_data, _provider) do
    case Jason.decode(json_data) do
      {:ok, %{"candidates" => [candidate | _]}} ->
        parse_candidate_chunk(candidate)

      _ ->
        nil
    end
  end

  defp parse_candidate_chunk(%{"content" => %{"parts" => parts}} = candidate) do
    # Extract text from parts
    text =
      Enum.map_join(parts, "", fn
        %{"text" => text} -> text
        _ -> ""
      end)

    # Check for finish reason
    finish_reason = Map.get(candidate, "finishReason")

    %Types.StreamChunk{
      content: if(text == "", do: nil, else: text),
      finish_reason: translate_finish_reason(finish_reason)
    }
  end

  defp parse_candidate_chunk(_), do: nil

  defp translate_finish_reason(nil), do: nil
  defp translate_finish_reason("STOP"), do: "stop"
  defp translate_finish_reason("MAX_TOKENS"), do: "length"
  defp translate_finish_reason("SAFETY"), do: "content_filter"
  defp translate_finish_reason(_), do: "stop"
end
