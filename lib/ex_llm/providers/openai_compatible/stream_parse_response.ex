defmodule ExLLM.Providers.OpenAICompatible.StreamParseResponse do
  @moduledoc """
  Template module for creating streaming response parsers for OpenAI-compatible providers.

  This module provides a macro that generates a streaming parser plug
  compatible with OpenAI's SSE format.
  """

  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)

    quote do
      @moduledoc """
      Streaming response parser plug for #{unquote(provider)} provider.

      Generated from OpenAI-compatible template.
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

        # Convert to StreamChunk stream
        chunk_stream =
          stream
          |> Stream.transform("", &process_sse_chunk/2)
          |> Stream.map(&parse_chunk(&1, request.provider))
          |> Stream.reject(&is_nil/1)

        request
        |> Request.assign(:response_stream, chunk_stream)
        |> Request.put_state(:streaming)
      end

      defp process_sse_chunk(chunk, buffer) do
        # Accumulate chunks and extract complete SSE events
        new_buffer = buffer <> chunk
        {events, remaining} = extract_sse_events(new_buffer)
        {events, remaining}
      end

      defp extract_sse_events(buffer) do
        # Split by double newline (SSE event separator)
        parts = String.split(buffer, "\n\n")

        case parts do
          [single] ->
            # No complete event yet
            {[], single}

          multiple ->
            # Last part might be incomplete
            {complete, [maybe_incomplete]} = Enum.split(multiple, -1)

            # Check if the last part is actually complete
            if String.ends_with?(buffer, "\n\n") do
              {complete ++ [maybe_incomplete], ""}
            else
              {complete, maybe_incomplete}
            end
        end
      end

      defp parse_chunk(event, _provider) do
        # Extract data from SSE event
        case parse_sse_event(event) do
          {:ok, "data: [DONE]"} ->
            # Stream complete
            %Types.StreamChunk{
              content: nil,
              finish_reason: "stop"
            }

          {:ok, "data: " <> json_data} ->
            # Parse JSON data
            case Jason.decode(json_data) do
              {:ok, data} ->
                parse_chunk_data(data)

              {:error, _} ->
                nil
            end

          _ ->
            nil
        end
      end

      defp parse_sse_event(event) do
        # Parse SSE format
        lines = String.split(event, "\n")

        data_line =
          Enum.find(lines, fn line ->
            String.starts_with?(line, "data: ")
          end)

        if data_line do
          {:ok, data_line}
        else
          {:error, :no_data}
        end
      end

      defp parse_chunk_data(%{"choices" => [%{"delta" => delta} | _]} = data) do
        content = Map.get(delta, "content")
        finish_reason = get_in(data, ["choices", Access.at(0), "finish_reason"])

        %Types.StreamChunk{
          content: content,
          finish_reason: finish_reason
        }
      end

      defp parse_chunk_data(_), do: nil

      # Allow providers to override specific functions
      defoverridable parse_chunk_data: 1
    end
  end
end
