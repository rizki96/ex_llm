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
  require Logger

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

    if !is_function(callback, 1) do
      Request.halt_with_error(request, %{
        plug: __MODULE__,
        error: :no_callback,
        message: "Streaming enabled but no callback provided"
      })
    else
      # Create a unique reference for this stream
      stream_ref = make_ref()

      # Start stream coordinator process
      {:ok, coordinator} = start_coordinator(request, callback, opts)

      request
      |> Map.put(:stream_coordinator, coordinator)
      |> Map.put(:stream_ref, stream_ref)
      |> Request.assign(:streaming_enabled, true)
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
    # Get parser config from request
    parser_config = request.private[:stream_parser] || default_parser_config()

    # Initialize accumulator
    accumulator = parser_config.accumulator

    # Wait for stream chunks
    receive_chunks(request, callback, parser_config, accumulator, opts[:timeout])
  end

  defp receive_chunks(request, callback, parser_config, accumulator, timeout) do
    receive do
      {:stream_chunk, ref, data} when ref == request.stream_ref ->
        case parser_config.parse_chunk.(data) do
          {:continue, chunks} ->
            # Process each chunk
            new_acc =
              Enum.reduce(chunks, accumulator, fn chunk, acc ->
                # Merge chunk data into accumulator
                merged = merge_chunk(acc, chunk)

                # Send to callback
                callback.(chunk)

                merged
              end)

            receive_chunks(request, callback, parser_config, new_acc, timeout)

          {:done, final_chunk} ->
            # Stream complete
            final = Map.merge(accumulator, final_chunk)
            callback.(Map.put(final, :done, true))

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
    # Basic text chunk
    {:continue, [%{content: to_string(data)}]}
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
