defmodule ExLLM.Plugs.ExecuteStreamRequest do
  @moduledoc """
  Executes streaming HTTP requests to LLM providers using the configured Tesla client.

  This plug handles streaming responses by setting up a process to receive
  and forward chunks to the configured callback function.

  ## Prerequisites

  This plug expects:
  - `request.tesla_client` to be set (by BuildTeslaClient)
  - `request.private.provider_request_body` to be set (by provider prepare plugs)
  - `request.config.stream_callback` to be set with a callback function

  ## Options

    * `:timeout` - Request timeout in milliseconds (default: 30_000)
    * `:receive_timeout` - Timeout for receiving chunks (default: 60_000)
  """

  use ExLLM.Plug
  require Logger

  @default_timeout 30_000
  @default_receive_timeout 60_000

  @impl true
  def init(opts) do
    opts
    |> Keyword.put_new(:timeout, @default_timeout)
    |> Keyword.put_new(:receive_timeout, @default_receive_timeout)
  end

  @impl true
  def call(%Request{tesla_client: nil} = request, _opts) do
    Request.halt_with_error(request, %{
      plug: __MODULE__,
      error: :no_tesla_client,
      message: "Tesla client not configured. Ensure BuildTeslaClient plug runs first."
    })
  end

  def call(%Request{} = request, opts) do
    body = request.private[:provider_request_body]

    if body do
      execute_stream_request(request, body, opts)
    else
      Request.halt_with_error(request, %{
        plug: __MODULE__,
        error: :no_request_body,
        message: "No request body prepared. Ensure provider prepare plug runs first."
      })
    end
  end

  defp execute_stream_request(request, body, opts) do
    client = request.tesla_client
    endpoint = get_endpoint(request)

    # Check if we have a stream coordinator
    coordinator = request[:stream_coordinator]

    if coordinator do
      # Coordinator will handle the callback
      execute_coordinated_stream(request, client, endpoint, body, coordinator, opts)
    else
      # Direct streaming (backward compatibility)
      callback = request.config[:stream_callback]

      if !is_function(callback, 1) do
        Request.halt_with_error(request, %{
          plug: __MODULE__,
          error: :no_stream_callback,
          message: "No stream callback function provided"
        })
      else
        execute_direct_stream(request, client, endpoint, body, callback, opts)
      end
    end
  end

  defp execute_coordinated_stream(request, client, endpoint, body, coordinator, opts) do
    stream_ref = make_ref()

    # Start streaming task that sends to coordinator
    {:ok, stream_pid} =
      Task.start(fn ->
        stream_to_coordinator(client, endpoint, body, coordinator, stream_ref, opts)
      end)

    request
    |> Map.put(:stream_pid, stream_pid)
    |> Map.put(:stream_ref, stream_ref)
    |> Request.assign(:streaming_started, true)
    |> Request.put_metadata(:stream_start_time, System.monotonic_time(:millisecond))
    |> Request.put_state(:streaming)
  end

  defp execute_direct_stream(request, client, endpoint, body, callback, opts) do
    parent = self()
    stream_ref = make_ref()

    {:ok, stream_pid} =
      Task.start(fn ->
        stream_response(client, endpoint, body, callback, parent, stream_ref, opts)
      end)

    request
    |> Map.put(:stream_pid, stream_pid)
    |> Map.put(:stream_ref, stream_ref)
    |> Request.assign(:streaming_started, true)
    |> Request.put_metadata(:stream_start_time, System.monotonic_time(:millisecond))
  end

  defp stream_to_coordinator(client, endpoint, body, coordinator, ref, opts) do
    # Prepare streaming request
    request_opts = [
      adapter: [
        receive_timeout: opts[:receive_timeout],
        stream_to: self()
      ]
    ]

    # Start the request
    case Tesla.post(client, endpoint, body, request_opts) do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        # Success - forward chunks to coordinator
        forward_chunks_to_coordinator(coordinator, ref)

      {:ok, %Tesla.Env{} = env} ->
        # Error response
        send(coordinator, {:stream_error, ref, env})

      {:error, reason} ->
        # Connection error
        send(coordinator, {:stream_error, ref, reason})
    end
  end

  defp forward_chunks_to_coordinator(coordinator, ref) do
    receive do
      {:data, chunk} ->
        send(coordinator, {:stream_chunk, ref, chunk})
        forward_chunks_to_coordinator(coordinator, ref)

      {:done, _} ->
        send(coordinator, {:stream_complete, ref})

      {:error, reason} ->
        send(coordinator, {:stream_error, ref, reason})
    after
      60_000 ->
        send(coordinator, {:stream_error, ref, :timeout})
    end
  end

  defp stream_response(client, endpoint, body, callback, parent, ref, opts) do
    # Prepare streaming request
    request_opts = [
      adapter: [
        receive_timeout: opts[:receive_timeout],
        stream_to: self()
      ]
    ]

    # Start the request
    case Tesla.post(client, endpoint, body, request_opts) do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        # Success - stream will arrive as messages
        handle_stream_messages(callback, parent, ref)

      {:ok, %Tesla.Env{} = env} ->
        # Error response
        send(parent, {:stream_error, ref, env})

      {:error, reason} ->
        # Connection error
        send(parent, {:stream_error, ref, reason})
    end
  end

  defp handle_stream_messages(callback, parent, ref) do
    receive do
      {:data, chunk} ->
        # Parse and forward chunk
        case parse_chunk(chunk) do
          {:ok, parsed} ->
            callback.(parsed)
            handle_stream_messages(callback, parent, ref)

          {:done, final} ->
            callback.(Map.put(final, :done, true))
            send(parent, {:stream_complete, ref})

          {:error, _reason} ->
            # Skip bad chunks
            handle_stream_messages(callback, parent, ref)
        end

      {:done, _} ->
        # Stream complete
        send(parent, {:stream_complete, ref})

      {:error, reason} ->
        send(parent, {:stream_error, ref, reason})
    after
      60_000 ->
        send(parent, {:stream_error, ref, :timeout})
    end
  end

  defp parse_chunk(chunk) when is_binary(chunk) do
    # Handle Server-Sent Events format
    chunk
    |> String.split("\n")
    |> Enum.reduce({:ok, %{}}, fn
      "data: [DONE]", _acc ->
        {:done, %{}}

      "data: " <> json, _acc ->
        case Jason.decode(json) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, :invalid_json}
        end

      _, acc ->
        acc
    end)
  end

  defp parse_chunk(_), do: {:error, :invalid_chunk}

  defp get_endpoint(%Request{provider: provider, config: config}) do
    case provider do
      :openai -> config[:base_url] || "https://api.openai.com/v1/chat/completions"
      :anthropic -> config[:base_url] || "https://api.anthropic.com/v1/messages"
      :gemini -> build_gemini_endpoint(config)
      :groq -> config[:base_url] || "https://api.groq.com/openai/v1/chat/completions"
      :mistral -> config[:base_url] || "https://api.mistral.ai/v1/chat/completions"
      :ollama -> config[:base_url] || "http://localhost:11434/api/chat"
      _ -> config[:base_url] || config[:endpoint] || "/"
    end
  end

  defp build_gemini_endpoint(config) do
    model = config[:model] || "gemini-pro"
    base = config[:base_url] || "https://generativelanguage.googleapis.com/v1beta"
    "#{base}/models/#{model}:streamGenerateContent"
  end
end
