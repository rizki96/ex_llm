defmodule ExLLM.Providers.Ollama.StreamParseResponse do
  @moduledoc """
  Streaming response parser plug for Ollama provider.

  Ollama uses a different streaming format than OpenAI - newline-delimited JSON.
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

    # Convert raw NDJSON stream to StreamChunk stream
    chunk_stream =
      stream
      |> Stream.transform("", &process_ndjson_chunk/2)
      |> Stream.map(&parse_ollama_chunk(&1, request.provider))
      |> Stream.reject(&is_nil/1)

    request
    |> Request.assign(:response_stream, chunk_stream)
    |> Request.put_state(:streaming)
  end

  defp process_ndjson_chunk(chunk, buffer) do
    # Accumulate chunks and extract complete JSON lines
    new_buffer = buffer <> chunk
    {lines, remaining} = extract_json_lines(new_buffer)
    {lines, remaining}
  end

  defp extract_json_lines(buffer) do
    # Split by newline
    lines = String.split(buffer, "\n")

    case lines do
      [single] ->
        # No complete line yet
        {[], single}

      multiple ->
        # Last part might be incomplete
        {complete, [maybe_incomplete]} = Enum.split(multiple, -1)

        # Filter out empty lines
        complete = Enum.reject(complete, &(&1 == ""))

        # Check if the last part is actually complete
        if String.ends_with?(buffer, "\n") do
          {complete, ""}
        else
          {complete, maybe_incomplete}
        end
    end
  end

  defp parse_ollama_chunk(json_line, _provider) do
    case Jason.decode(json_line) do
      {:ok, %{"message" => %{"content" => content}, "done" => false}} ->
        %Types.StreamChunk{
          content: content,
          finish_reason: nil
        }

      {:ok, %{"message" => %{"content" => content}, "done" => true}} ->
        %Types.StreamChunk{
          content: content,
          finish_reason: "stop"
        }

      {:ok, %{"done" => true}} ->
        %Types.StreamChunk{
          content: nil,
          finish_reason: "stop"
        }

      _ ->
        nil
    end
  end
end
