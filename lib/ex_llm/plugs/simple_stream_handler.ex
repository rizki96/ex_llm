defmodule ExLLM.Plugs.SimpleStreamHandler do
  @moduledoc """
  A simple streaming handler that creates a response stream directly.

  This plug replaces the complex ExecuteStreamRequest flow with a simpler
  approach that creates a stream that the pipeline can consume.
  """

  use ExLLM.Plug
  alias ExLLM.Pipeline.Request
  alias ExLLM.Types.StreamChunk
  alias ExLLM.Providers.Shared.HTTP.Core

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
      # Start function
      fn ->
        # Initialize state
        %{
          buffer: "",
          parser_config: request.private[:stream_parser],
          done: false
        }
      end,

      # Next function
      fn state ->
        if state.done do
          {:halt, state}
        else
          # Make the HTTP request in a separate process
          task =
            Task.async(fn ->
              chunks = []
              chunk_ref = make_ref()

              callback = fn chunk_data ->
                send(self(), {chunk_ref, chunk_data})
              end

              # Start the HTTP stream
              case Core.stream(
                     request.tesla_client,
                     endpoint,
                     request.provider_request,
                     callback,
                     timeout: 30_000
                   ) do
                {:ok, _} ->
                  # Collect all chunks
                  collect_chunks(chunk_ref, chunks, state.parser_config)

                {:error, error} ->
                  {:error, error}
              end
            end)

          # Wait for task to complete
          case Task.await(task, 35_000) do
            {:ok, chunks} ->
              # Return all chunks and mark as done
              {chunks, %{state | done: true}}

            {:error, error} ->
              # Return error chunk
              error_chunk = %StreamChunk{
                content: nil,
                finish_reason: "error",
                metadata: %{error: error}
              }

              {[error_chunk], %{state | done: true}}
          end
        end
      end,

      # Cleanup function
      fn _state -> :ok end
    )
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
