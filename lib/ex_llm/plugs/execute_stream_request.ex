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
  alias ExLLM.Infrastructure.Logger

  # Default endpoints for each provider
  @default_endpoints %{
    openai: "https://api.openai.com/v1/chat/completions",
    anthropic: "https://api.anthropic.com/v1/messages",
    groq: "https://api.groq.com/openai/v1/chat/completions",
    mistral: "https://api.mistral.ai/v1/chat/completions",
    ollama: "http://localhost:11434/api/chat",
    lmstudio: "chat/completions"
  }

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
    coordinator = request.assigns[:stream_coordinator] || request.stream_pid
    Logger.debug("Stream coordinator: #{inspect(coordinator)}")

    if coordinator do
      # Coordinator will handle the callback
      Logger.debug("Taking coordinated stream path")
      execute_coordinated_stream(request, client, endpoint, body, coordinator, opts)
    else
      # Direct streaming (backward compatibility)
      callback = request.config[:stream_callback]
      Logger.debug("Taking direct stream path, callback: #{inspect(callback)}")

      if is_function(callback, 1) do
        execute_direct_stream(request, client, endpoint, body, callback, opts)
      else
        Request.halt_with_error(request, %{
          plug: __MODULE__,
          error: :no_stream_callback,
          message: "No stream callback function provided"
        })
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
    # Extract headers from the client's middleware
    Logger.debug("Original client: #{inspect(client)}")
    headers = extract_headers_from_client(client)
    Logger.debug("Extracted headers: #{inspect(headers)}")

    # Build a new client specifically for streaming
    stream_client =
      Tesla.client(
        [
          {Tesla.Middleware.Headers, headers},
          Tesla.Middleware.JSON
        ],
        {Tesla.Adapter.Hackney,
         [recv_timeout: opts[:receive_timeout] || 60_000, stream_to: self()]}
      )

    # Start the request
    Logger.debug("Starting stream request to #{endpoint}")

    result = Tesla.post(stream_client, endpoint, body)
    Logger.debug("Tesla.post result: #{inspect(result)}")

    case result do
      {:ok, %Tesla.Env{status: status} = env} when status in 200..299 ->
        # Success - check if we got the full body or if it's streaming
        Logger.debug("Stream request successful, status: #{status}")
        Logger.debug("Response headers: #{inspect(env.headers)}")

        if env.body && env.body != "" do
          # We got the full body, parse it as SSE events
          Logger.debug("Got full SSE body, parsing events")
          parse_and_forward_sse_body(env.body, coordinator, ref)
        else
          # Body is empty, expect streaming chunks
          Logger.debug("Empty body, waiting for streaming chunks")
          forward_chunks_to_coordinator(coordinator, ref)
        end

      %Tesla.Env{status: status} = env when status in 200..299 ->
        # Success (unwrapped response from streaming) - forward chunks to coordinator
        Logger.debug("Stream request successful (unwrapped), status: #{status}")
        Logger.debug("Response headers: #{inspect(env.headers)}")
        Logger.debug("Response body: #{inspect(env.body)}")
        # The body has already been consumed by streaming, so we receive chunks via messages
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
    Logger.debug("Waiting for chunks to forward to coordinator #{inspect(coordinator)}")

    receive do
      # Hackney's actual message format for streaming
      {:hackney_response, _ref, :more, chunk} ->
        Logger.debug("Hackney data chunk received (4-tuple): #{inspect(chunk)}")
        send(coordinator, {:stream_chunk, ref, chunk})
        forward_chunks_to_coordinator(coordinator, ref)

      {:hackney_response, :more, chunk} ->
        Logger.debug("Hackney data chunk received (3-tuple): #{inspect(chunk)}")
        send(coordinator, {:stream_chunk, ref, chunk})
        forward_chunks_to_coordinator(coordinator, ref)

      {:hackney_response, _ref, :done, _} ->
        Logger.debug("Hackney stream ended (4-tuple)")
        send(coordinator, {:stream_complete, ref})

      {:hackney_response, :done, _} ->
        Logger.debug("Hackney stream ended (3-tuple)")
        send(coordinator, {:stream_complete, ref})

      {:hackney_response, _ref, :error, reason} ->
        Logger.debug("Hackney stream error (4-tuple): #{inspect(reason)}")
        send(coordinator, {:stream_error, ref, reason})

      {:hackney_response, :error, reason} ->
        Logger.debug("Hackney stream error (3-tuple): #{inspect(reason)}")
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
        Logger.warning("Unexpected streaming message in forward_chunks: #{inspect(other)}")
        # Check if it's some other message we should handle
        case other do
          {:tcp, _, _} ->
            Logger.debug("Received raw TCP data, continuing...")
            forward_chunks_to_coordinator(coordinator, ref)

          {:ssl, _, _} ->
            Logger.debug("Received raw SSL data, continuing...")
            forward_chunks_to_coordinator(coordinator, ref)

          _ ->
            forward_chunks_to_coordinator(coordinator, ref)
        end
    after
      5_000 ->
        Logger.error("Timeout waiting for stream chunks after 5 seconds")
        send(coordinator, {:stream_error, ref, :timeout})
    end
  end

  defp stream_response(client, endpoint, body, callback, parent, ref, opts) do
    # Extract headers from the client's middleware
    headers = extract_headers_from_client(client)

    # Build a new client specifically for streaming
    stream_client =
      Tesla.client(
        [
          {Tesla.Middleware.Headers, headers},
          Tesla.Middleware.JSON
        ],
        {Tesla.Adapter.Hackney,
         [recv_timeout: opts[:receive_timeout] || 60_000, stream_to: self()]}
      )

    # Start the request
    case Tesla.post(stream_client, endpoint, body) do
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
    # Initialize SSE parser for the stream
    sse_parser = ExLLM.Infrastructure.Streaming.SSEParser.new()
    handle_stream_messages(callback, parent, ref, sse_parser)
  end

  defp handle_stream_messages(callback, parent, ref, sse_parser) do
    receive do
      # Hackney's actual message format for streaming
      {:hackney_response, :more, chunk} ->
        Logger.debug("Hackney data chunk received in handle_stream_messages: #{inspect(chunk)}")

        # Parse SSE events from chunk
        {events, updated_parser} =
          ExLLM.Infrastructure.Streaming.SSEParser.parse_json_events(sse_parser, chunk)

        # Process each event
        stream_complete =
          Enum.any?(events, fn event ->
            case format_stream_event(event) do
              {:ok, parsed} ->
                callback.(parsed)
                false

              {:done, _} ->
                # Stream complete
                true

              {:error, reason} ->
                Logger.warning("Failed to parse stream event: #{inspect(reason)}")
                false
            end
          end)

        if stream_complete do
          send(parent, {:stream_complete, ref})
        else
          # Continue processing
          handle_stream_messages(callback, parent, ref, updated_parser)
        end

      {:hackney_response, :done, _} ->
        Logger.debug("Hackney stream ended in handle_stream_messages")
        # Flush any remaining data in the parser
        {final_events, _} = ExLLM.Infrastructure.Streaming.SSEParser.flush(sse_parser)

        Enum.each(final_events, fn event ->
          case format_stream_event(event) do
            {:ok, parsed} -> callback.(parsed)
            _ -> :ok
          end
        end)

        send(parent, {:stream_complete, ref})

      {:hackney_response, :error, reason} ->
        Logger.debug("Hackney stream error in handle_stream_messages: #{inspect(reason)}")
        send(parent, {:stream_error, ref, reason})

      # Legacy patterns for backward compatibility
      {:data, chunk} ->
        # Use SSE parser for legacy format too
        {events, updated_parser} =
          ExLLM.Infrastructure.Streaming.SSEParser.parse_json_events(sse_parser, chunk)

        stream_complete =
          Enum.any?(events, fn event ->
            case format_stream_event(event) do
              {:ok, parsed} ->
                callback.(parsed)
                false

              {:done, _} ->
                true

              _ ->
                false
            end
          end)

        if stream_complete do
          send(parent, {:stream_complete, ref})
        else
          handle_stream_messages(callback, parent, ref, updated_parser)
        end

      {:done, _} ->
        # Stream complete
        send(parent, {:stream_complete, ref})

      {:error, reason} ->
        send(parent, {:stream_error, ref, reason})

      other ->
        Logger.debug("Unexpected streaming message in handle_stream_messages: #{inspect(other)}")
        handle_stream_messages(callback, parent, ref, sse_parser)
    after
      60_000 ->
        send(parent, {:stream_error, ref, :timeout})
    end
  end

  # Format parsed SSE event into expected format
  defp format_stream_event(%{"done" => true}), do: {:done, %{}}
  defp format_stream_event(%{done: true}), do: {:done, %{}}

  defp format_stream_event(event) when is_map(event) do
    {:ok, event}
  end

  defp format_stream_event(other) do
    {:error, {:unexpected_format, other}}
  end

  defp get_endpoint(%Request{provider: provider, config: config}) do
    case provider do
      :gemini -> build_gemini_endpoint(config)
      _ -> config[:base_url] || config[:endpoint] || Map.get(@default_endpoints, provider, "/")
    end
  end

  defp build_gemini_endpoint(config) do
    model = config[:model] || "gemini-pro"
    base = config[:base_url] || "https://generativelanguage.googleapis.com/v1beta"
    "#{base}/models/#{model}:streamGenerateContent"
  end

  defp extract_headers_from_client(%Tesla.Client{pre: middleware}) do
    # Find the Headers middleware and extract its headers
    Enum.find_value(middleware, [], fn
      {Tesla.Middleware.Headers, :call, [headers | _]} -> headers
      _ -> nil
    end)
  end

  defp parse_and_forward_sse_body(body, coordinator, ref) do
    # Send the entire body as one chunk - the coordinator's parser will handle it
    send(coordinator, {:stream_chunk, ref, body})

    # Don't send completion here - let the parser detect the end
  end
end
