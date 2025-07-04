defmodule ExLLM.Plugs.StreamingResponseHandler do
  @moduledoc """
  Creates a response stream that the pipeline expects for streaming requests.

  This plug should run for streaming requests and creates a Stream that can
  be consumed by the pipeline system.
  """

  use ExLLM.Plug
  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Shared.HTTP.Core
  alias ExLLM.Types.StreamChunk

  @impl true
  def call(%Request{config: %{stream: true}} = request, _opts) do
    # Check if we have what we need
    if request.tesla_client && request.provider_request do
      # Get the endpoint
      endpoint = get_endpoint(request)

      # Create a stream
      stream = create_sse_stream(request, endpoint)

      request
      |> Request.assign(:response_stream, stream)
      |> Request.put_state(:streaming)
    else
      request
    end
  end

  def call(request, _opts), do: request

  defp create_sse_stream(request, endpoint) do
    # Create a stream that makes the HTTP request and parses SSE
    Stream.resource(
      # Start function
      fn ->
        # Start the HTTP request in a task
        task =
          Task.async(fn ->
            make_streaming_request(request, endpoint)
          end)

        # Return task as accumulator
        {task, request.private[:stream_parser], []}
      end,

      # Next function - get chunks from the task
      fn {task, parser_config, buffer} ->
        case Task.yield(task, 100) do
          {:ok, {:ok, chunks}} ->
            # Got all chunks, convert to StreamChunks
            stream_chunks =
              Enum.map(chunks, fn chunk ->
                convert_to_stream_chunk(chunk, parser_config)
              end)
              |> List.flatten()

            {stream_chunks, :done}

          {:ok, {:error, error}} ->
            # Error occurred
            error_chunk = %StreamChunk{
              content: nil,
              finish_reason: "error",
              metadata: %{error: error}
            }

            {[error_chunk], :done}

          nil ->
            # Still running, check if task is alive
            if Process.alive?(task.pid) do
              # Keep waiting
              {[], {task, parser_config, buffer}}
            else
              # Task died
              {[], :done}
            end

          {:exit, reason} ->
            # Task crashed
            error_chunk = %StreamChunk{
              content: nil,
              finish_reason: "error",
              metadata: %{error: {:task_exit, reason}}
            }

            {[error_chunk], :done}
        end
      end,

      # Cleanup function
      fn
        {task, _, _} -> Task.shutdown(task, :brutal_kill)
        :done -> :ok
      end
    )
  end

  defp make_streaming_request(request, endpoint) do
    # Collect all chunks from the HTTP stream
    chunks = []
    chunk_ref = make_ref()
    parent = self()

    # Callback that sends chunks to parent
    callback = fn chunk_data ->
      send(parent, {chunk_ref, chunk_data})
    end

    # Make the streaming request
    result =
      Core.stream(
        request.tesla_client,
        endpoint,
        request.provider_request,
        callback,
        timeout: 30_000
      )

    case result do
      {:ok, _} ->
        # Collect all chunks
        collected = collect_all_chunks(chunk_ref, chunks, 30_000)
        {:ok, collected}

      {:error, error} ->
        {:error, error}
    end
  end

  defp collect_all_chunks(ref, chunks, timeout) do
    receive do
      {^ref, data} ->
        collect_all_chunks(ref, [data | chunks], timeout)
    after
      timeout ->
        Enum.reverse(chunks)
    end
  end

  defp convert_to_stream_chunk(data, nil) do
    # No parser, return raw chunk
    %StreamChunk{content: to_string(data)}
  end

  defp convert_to_stream_chunk(data, parser_config) when is_map(parser_config) do
    # Use the configured parser
    case parser_config.parse_chunk.(data) do
      {:continue, chunks} when is_list(chunks) ->
        Enum.map(chunks, &chunk_to_stream_chunk/1)

      {:continue, chunk} ->
        [chunk_to_stream_chunk(chunk)]

      {:done, chunk} ->
        [chunk_to_stream_chunk(Map.put(chunk, :finish_reason, "stop"))]

      _ ->
        []
    end
  end

  defp convert_to_stream_chunk(data, _), do: %StreamChunk{content: to_string(data)}

  defp chunk_to_stream_chunk(data) when is_map(data) do
    %StreamChunk{
      content: data[:content],
      finish_reason: data[:finish_reason],
      model: data[:model],
      id: data[:id],
      metadata: Map.drop(data, [:content, :finish_reason, :model, :id])
    }
  end

  defp chunk_to_stream_chunk(content) when is_binary(content) do
    %StreamChunk{content: content}
  end

  defp chunk_to_stream_chunk(_), do: %StreamChunk{}

  defp get_endpoint(%Request{provider: provider, config: config}) do
    case provider do
      :gemini ->
        model = config[:model] || "gemini-2.0-flash"
        "/models/#{model}:streamGenerateContent"

      :anthropic ->
        "/v1/messages"

      _ ->
        "/v1/chat/completions"
    end
  end
end
