defmodule ExLLM.Plugs.StreamCoordinator do
  @moduledoc """
  Coordinates streaming responses across the pipeline.

  This plug manages the streaming lifecycle, including:
  - Setting up stream handling
  - Coordinating chunk parsing
  - Managing accumulation of chunks
  - Handling stream completion and errors
  """

  use ExLLM.Plug
  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Types.StreamChunk

  # 60 seconds
  @default_timeout 60_000

  @impl true
  def init(opts) do
    Keyword.put_new(opts, :timeout, @default_timeout)
  end

  @impl true
  def call(%Request{config: %{stream: true}} = request, opts) do
    # Ensure we have a callback
    callback = request.config[:stream_callback]

    if is_function(callback, 1) do
      # Create a unique reference for this stream
      stream_ref = make_ref()

      # Update request with stream_ref first
      request_with_ref = %{request | stream_ref: stream_ref}

      # Start stream coordinator process with the updated request
      {:ok, coordinator} = start_coordinator(request_with_ref, callback, opts)

      %{request_with_ref | stream_pid: coordinator}
      |> Request.assign(:streaming_enabled, true)
      |> Request.assign(:stream_coordinator, coordinator)
    else
      Request.halt_with_error(request, %{
        plug: __MODULE__,
        error: :no_callback,
        message: "Streaming enabled but no callback provided"
      })
    end
  end

  def call(request, _opts) do
    # Non-streaming request, pass through
    request
  end

  defp start_coordinator(request, callback, opts) do
    Task.start_link(fn ->
      coordinate_stream(request, callback, opts)
    end)
  end

  defp coordinate_stream(request, callback, opts) do
    Logger.debug("StreamCoordinator started for request: #{inspect(request.stream_ref)}")

    # Get parser config from request
    parser_config = request.private[:stream_parser] || default_parser_config()
    Logger.debug("Using parser config: #{inspect(Map.keys(parser_config))}")

    # Initialize accumulator
    accumulator = parser_config.accumulator

    # Wait for stream chunks
    receive_chunks(request, callback, parser_config, accumulator, opts[:timeout])
  end

  defp receive_chunks(request, callback, parser_config, accumulator, timeout) do
    receive do
      {:stream_chunk, ref, data} when ref == request.stream_ref ->
        Logger.debug("StreamCoordinator received chunk: #{inspect(data)}")

        case parser_config.parse_chunk.(data) do
          {:continue, chunks} ->
            Logger.debug("Parsed chunks: #{inspect(chunks)}")
            # Process each chunk
            new_acc =
              Enum.reduce(chunks, accumulator, fn chunk, acc ->
                # Merge chunk data into accumulator
                merged = merge_chunk(acc, chunk)

                # Convert to StreamChunk and send to callback
                stream_chunk = to_stream_chunk(chunk, merged)
                Logger.debug("Sending StreamChunk to callback: #{inspect(stream_chunk)}")
                callback.(stream_chunk)

                merged
              end)

            receive_chunks(request, callback, parser_config, new_acc, timeout)

          {:done, final_chunk} ->
            Logger.debug("Stream done, final chunk: #{inspect(final_chunk)}")
            # Stream complete
            final = Map.merge(accumulator, final_chunk)
            # Convert to StreamChunk with finish_reason
            stream_chunk = to_stream_chunk(final, final)
            callback.(stream_chunk)

            # Emit telemetry
            :telemetry.execute(
              [:ex_llm, :stream, :complete],
              %{chunks_received: accumulator[:chunk_count] || 0},
              %{provider: request.provider}
            )
        end

      {:stream_error, ref, error} when ref == request.stream_ref ->
        # Handle error
        callback.(%{
          error: true,
          message: format_error(error),
          done: true
        })

      {:stream_complete, ref} when ref == request.stream_ref ->
        # Normal completion
        callback.(%{done: true})
    after
      timeout ->
        callback.(%{
          error: true,
          message: "Stream timeout after #{timeout}ms",
          done: true
        })
    end
  end

  defp merge_chunk(accumulator, chunk) do
    accumulator
    |> Map.update(:content, chunk[:content] || "", fn existing ->
      existing <> (chunk[:content] || "")
    end)
    |> Map.update(:chunk_count, 1, &(&1 + 1))
    |> merge_non_content_fields(chunk)
  end

  defp merge_non_content_fields(accumulator, chunk) do
    Enum.reduce(chunk, accumulator, fn
      {:content, _}, acc -> acc
      {key, value}, acc when not is_nil(value) -> Map.put(acc, key, value)
      _, acc -> acc
    end)
  end

  defp default_parser_config do
    %{
      parse_chunk: &default_parse_chunk/1,
      accumulator: %{content: "", role: "assistant"}
    }
  end

  defp default_parse_chunk(data) do
    # For SSE events, we should not be using the default parser
    # This is a fallback that just passes through the data
    Logger.warning(
      "Using default parser for streaming data - should use provider-specific parser"
    )

    {:continue, [%{content: to_string(data)}]}
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp to_stream_chunk(chunk, accumulator) do
    %StreamChunk{
      content: chunk[:content],
      finish_reason: chunk[:stop_reason] || chunk[:finish_reason],
      model: chunk[:model] || accumulator[:model],
      id: chunk[:id],
      metadata: Map.drop(chunk, [:content, :stop_reason, :finish_reason, :model, :id])
    }
  end
end
