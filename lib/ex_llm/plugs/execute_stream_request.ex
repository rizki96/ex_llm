defmodule ExLLM.Plugs.ExecuteStreamRequest do
  @moduledoc """
  Executes streaming HTTP requests to LLM providers using the configured Tesla client.

  This plug handles streaming responses by setting up a process to receive
  and forward chunks to the configured callback function.

  ## Prerequisites

  This plug expects:
  - `request.tesla_client` to be set (by BuildTeslaClient)
  - `request.private.provider_request_body` OR `request.provider_request` to be set (by provider prepare plugs)
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
    # Check both fields for backward compatibility
    body = request.private[:provider_request_body] || request.provider_request

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
    Logger.debug("execute_stream_request called for provider: #{request.provider}")
    client = request.tesla_client
    endpoint = get_endpoint(request)
    Logger.debug("Endpoint: #{endpoint}")

    # Check if we have a stream coordinator
    coordinator = request.stream_coordinator
    Logger.debug("Stream coordinator: #{inspect(coordinator)}")

    if coordinator do
      # Coordinator will handle the callback
      Logger.debug("Taking coordinated stream path")
      execute_coordinated_stream(request, client, endpoint, body, coordinator, opts)
    else
      # Direct streaming (backward compatibility)
      callback = request.config[:stream_callback]
      Logger.debug("Taking direct stream path, callback: #{inspect(callback)}")

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
    # Use the existing stream_ref from the request that the coordinator is expecting
    stream_ref = request.stream_ref
    
    if stream_ref == nil do
      Logger.error("No stream_ref found in request for coordinated streaming")
      Request.halt_with_error(request, %{
        plug: __MODULE__,
        error: :no_stream_ref,
        message: "No stream reference found in request"
      })
    else
      # Start streaming task that sends to coordinator
      {:ok, stream_pid} =
        Task.start(fn ->
          stream_to_coordinator(client, endpoint, body, coordinator, stream_ref, opts)
        end)

      %{request | stream_pid: stream_pid}
      |> Request.assign(:streaming_started, true)
      |> Request.put_metadata(:stream_start_time, System.monotonic_time(:millisecond))
      |> Request.put_state(:streaming)
    end
  end

  defp execute_direct_stream(request, client, endpoint, body, callback, opts) do
    parent = self()
    stream_ref = make_ref()

    {:ok, stream_pid} =
      Task.start(fn ->
        stream_response(client, endpoint, body, callback, parent, stream_ref, opts)
      end)

    %{request | stream_pid: stream_pid, stream_ref: stream_ref}
    |> Request.assign(:streaming_started, true)
    |> Request.put_metadata(:stream_start_time, System.monotonic_time(:millisecond))
  end

  defp stream_to_coordinator(client, endpoint, body, coordinator, ref, opts) do
    # Prepare streaming request with Hackney adapter for proper streaming support
    request_opts = [
      adapter: {Tesla.Adapter.Hackney, [
        recv_timeout: opts[:receive_timeout] || 60_000,
        stream_to: self()
        # Remove async: :once as it conflicts with stream_to
      ]}
    ]

    # Start the request
    Logger.debug("Starting stream request to #{endpoint} with Hackney adapter")
    case Tesla.post(client, endpoint, body, request_opts) do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        # Success - forward chunks to coordinator
        Logger.debug("Stream request successful, status: #{status}")
        forward_chunks_to_coordinator(coordinator, ref)

      %Tesla.Env{status: status} when status in 200..299 ->
        # Success (unwrapped response from streaming) - forward chunks to coordinator
        Logger.debug("Stream request successful (unwrapped), status: #{status}")
        forward_chunks_to_coordinator(coordinator, ref)

      {:ok, %Tesla.Env{} = env} ->
        # Error response
        send(coordinator, {:stream_error, ref, env})

      %Tesla.Env{} = env ->
        # Error response (unwrapped from streaming)
        send(coordinator, {:stream_error, ref, env})

      {:error, reason} ->
        # Connection error
        send(coordinator, {:stream_error, ref, reason})
    end
  end

  defp forward_chunks_to_coordinator(coordinator, ref) do
    receive do
      # Hackney's actual message format for streaming
      {:hackney_response, :more, chunk} ->
        Logger.debug("Hackney data chunk received: #{inspect(chunk)}")
        send(coordinator, {:stream_chunk, ref, chunk})
        forward_chunks_to_coordinator(coordinator, ref)

      {:hackney_response, :done, _} ->
        Logger.debug("Hackney stream ended")
        send(coordinator, {:stream_complete, ref})

      {:hackney_response, :error, reason} ->
        Logger.debug("Hackney stream error: #{inspect(reason)}")
        send(coordinator, {:stream_error, ref, reason})

      # Legacy patterns for backward compatibility
      {:data, chunk} ->
        send(coordinator, {:stream_chunk, ref, chunk})
        forward_chunks_to_coordinator(coordinator, ref)

      {:done, _} ->
        send(coordinator, {:stream_complete, ref})

      {:error, reason} ->
        send(coordinator, {:stream_error, ref, reason})

      other ->
        Logger.debug("Unexpected streaming message: #{inspect(other)}")
        forward_chunks_to_coordinator(coordinator, ref)
    after
      60_000 ->
        send(coordinator, {:stream_error, ref, :timeout})
    end
  end

  defp stream_response(client, endpoint, body, callback, parent, ref, opts) do
    # Prepare streaming request with Hackney adapter for proper streaming support
    request_opts = [
      adapter: {Tesla.Adapter.Hackney, [
        recv_timeout: opts[:receive_timeout] || 60_000,
        stream_to: self()
        # Remove async: :once as it conflicts with stream_to
      ]}
    ]

    # Start the request
    case Tesla.post(client, endpoint, body, request_opts) do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        # Success - stream will arrive as messages
        handle_stream_messages(callback, parent, ref)

      %Tesla.Env{status: status} when status in 200..299 ->
        # Success (unwrapped response from streaming) - stream will arrive as messages
        handle_stream_messages(callback, parent, ref)

      {:ok, %Tesla.Env{} = env} ->
        # Error response
        send(parent, {:stream_error, ref, env})

      %Tesla.Env{} = env ->
        # Error response (unwrapped from streaming)
        send(parent, {:stream_error, ref, env})

      {:error, reason} ->
        # Connection error
        send(parent, {:stream_error, ref, reason})
    end
  end

  defp handle_stream_messages(callback, parent, ref) do
    receive do
      # Hackney's actual message format for streaming
      {:hackney_response, :more, chunk} ->
        Logger.debug("Hackney data chunk received in handle_stream_messages: #{inspect(chunk)}")
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

      {:hackney_response, :done, _} ->
        Logger.debug("Hackney stream ended in handle_stream_messages")
        send(parent, {:stream_complete, ref})

      {:hackney_response, :error, reason} ->
        Logger.debug("Hackney stream error in handle_stream_messages: #{inspect(reason)}")
        send(parent, {:stream_error, ref, reason})

      # Legacy patterns for backward compatibility
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

      other ->
        Logger.debug("Unexpected streaming message in handle_stream_messages: #{inspect(other)}")
        handle_stream_messages(callback, parent, ref)
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
      :openai ->
        config[:base_url] || "https://api.openai.com/v1/chat/completions"

      :anthropic ->
        config[:base_url] || "https://api.anthropic.com/v1/messages"

      :gemini ->
        build_gemini_endpoint(config)

      :groq ->
        config[:base_url] || "https://api.groq.com/openai/v1/chat/completions"

      :mistral ->
        config[:base_url] || "https://api.mistral.ai/v1/chat/completions"

      :ollama ->
        config[:base_url] || "http://localhost:11434/api/chat"

      :lmstudio ->
        # Return relative path without leading slash so Tesla appends to base URL
        "chat/completions"

      _ ->
        config[:base_url] || config[:endpoint] || "/"
    end
  end

  defp build_gemini_endpoint(config) do
    model = config[:model] || "gemini-pro"
    base = config[:base_url] || "https://generativelanguage.googleapis.com/v1beta"
    "#{base}/models/#{model}:streamGenerateContent"
  end
end
