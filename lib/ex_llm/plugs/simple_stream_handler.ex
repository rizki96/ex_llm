defmodule ExLLM.Plugs.SimpleStreamHandler do
  @moduledoc """
  A simple streaming handler that creates a response stream directly.

  This plug replaces the complex ExecuteStreamRequest flow with a simpler
  approach that creates a stream that the pipeline can consume.
  """

  use ExLLM.Plug
  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Shared.HTTP.Core
  alias ExLLM.Types.StreamChunk

  @impl true
  def call(%Request{config: %{stream: true}} = request, _opts) do
    # Get the endpoint
    endpoint = get_endpoint(request)

    # Create the response stream
    stream = create_http_stream(request, endpoint)

    request
    |> Request.assign(:response_stream, stream)
    |> Request.put_state(:streaming)
  end

  def call(request, _opts), do: request

  defp create_http_stream(request, endpoint) do
    Stream.resource(
      fn -> initialize_stream_state(request, endpoint) end,
      &process_stream_state/1,
      fn _state -> :ok end
    )
  end

  defp initialize_stream_state(request, endpoint) do
    %{
      buffer: "",
      parser_config: request.private[:stream_parser],
      done: false,
      request: request,
      endpoint: endpoint
    }
  end

  defp process_stream_state(%{done: true} = state) do
    {:halt, state}
  end

  defp process_stream_state(state) do
    task = create_streaming_task(state)
    handle_task_result(Task.await(task, 35_000), state)
  end

  defp create_streaming_task(state) do
    Task.async(fn ->
      execute_http_stream(state)
    end)
  end

  defp execute_http_stream(state) do
    chunks = []
    chunk_ref = make_ref()
    callback = create_chunk_callback(chunk_ref)

    case start_http_stream(callback, state) do
      {:ok, _} -> collect_chunks(chunk_ref, chunks, state.parser_config)
      {:error, error} -> {:error, error}
    end
  end

  defp create_chunk_callback(chunk_ref) do
    fn chunk_data -> send(self(), {chunk_ref, chunk_data}) end
  end

  defp start_http_stream(callback, state) do
    Core.stream(
      state.request.tesla_client,
      state.endpoint,
      state.request.provider_request,
      callback,
      timeout: 30_000
    )
  end

  defp handle_task_result({:ok, chunks}, state) do
    {chunks, %{state | done: true}}
  end

  defp handle_task_result({:error, error}, state) do
    error_chunk = create_error_chunk(error)
    {[error_chunk], %{state | done: true}}
  end

  defp create_error_chunk(error) do
    %StreamChunk{
      content: nil,
      finish_reason: "error",
      metadata: %{error: error}
    }
  end

  defp collect_chunks(ref, chunks, parser_config, timeout \\ 30_000) do
    receive do
      {^ref, data} ->
        # Parse the chunk
        new_chunks = parse_chunk_data(data, parser_config)
        collect_chunks(ref, chunks ++ new_chunks, parser_config, timeout)
    after
      timeout ->
        # Return what we have
        {:ok, chunks}
    end
  end

  defp parse_chunk_data(data, nil) do
    # No parser, return raw data
    [%StreamChunk{content: to_string(data)}]
  end

  defp parse_chunk_data(data, parser_config) do
    case parser_config.parse_chunk.(data) do
      {:continue, chunks} when is_list(chunks) ->
        Enum.map(chunks, &to_stream_chunk/1)

      {:continue, chunk} ->
        [to_stream_chunk(chunk)]

      {:done, chunk} ->
        [to_stream_chunk(Map.put(chunk, :finish_reason, "stop"))]

      _ ->
        []
    end
  end

  defp to_stream_chunk(data) when is_map(data) do
    %StreamChunk{
      content: data[:content],
      finish_reason: data[:finish_reason],
      model: data[:model],
      id: data[:id],
      metadata: Map.drop(data, [:content, :finish_reason, :model, :id])
    }
  end

  defp to_stream_chunk(content) when is_binary(content) do
    %StreamChunk{content: content}
  end

  defp to_stream_chunk(_), do: %StreamChunk{}

  defp get_endpoint(%Request{provider: provider, config: config, assigns: assigns}) do
    # Check assigns first for http_path
    case assigns[:http_path] do
      nil ->
        # Fall back to provider-specific logic
        case provider do
          :gemini ->
            model = config[:model] || "gemini-2.0-flash"
            "/models/#{model}:streamGenerateContent"

          :anthropic ->
            "/v1/messages"

          :openai ->
            "/v1/chat/completions"

          :groq ->
            "/v1/chat/completions"

          :mistral ->
            "/v1/chat/completions"

          _ ->
            "/v1/chat/completions"
        end

      path ->
        path
    end
  end
end
