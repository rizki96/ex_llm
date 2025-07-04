defmodule ExLLM.Plugs.ExecuteStreamRequest do
  @moduledoc """
  Executes streaming HTTP requests to LLM providers using HTTP.Core.

  This plug handles streaming responses by setting up a process to receive
  and forward chunks to the configured callback function. It has been migrated
  from legacy HTTP client to use the modern HTTP.Core streaming infrastructure.

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
  alias ExLLM.Pipeline.Request

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
      Logger.debug(
        "ExecuteStreamRequest: provider=#{request.provider}, stream_callback=#{inspect(request.config[:stream_callback])}, coordinator=#{inspect(request.assigns[:stream_coordinator] || request.stream_pid)}"
      )

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
      # Direct streaming or pipeline streaming
      callback = request.config[:stream_callback]
      Logger.debug("Taking direct stream path, callback: #{inspect(callback)}")

      if is_function(callback, 1) do
        # Callback-based streaming (backward compatibility)
        # Get configurable timeout from request options, config, or default
        stream_timeout =
          request.options[:timeout] ||
            request.config[:streaming_timeout] ||
            opts[:timeout] ||
            @default_timeout

        Logger.debug("ExecuteStreamRequest using timeout: #{stream_timeout}ms")

        # Pass timeout in opts to execute_direct_stream
        stream_opts = Keyword.put(opts, :timeout, stream_timeout)
        execute_direct_stream(request, client, endpoint, body, callback, stream_opts)
      else
        # Pipeline streaming - create a response stream for Pipeline.stream
        Logger.debug("No callback provided, creating response stream for pipeline")
        execute_pipeline_stream(request, client, endpoint, body, opts)
      end
    end
  end

  defp execute_coordinated_stream(request, client, endpoint, body, coordinator, opts) do
    # Use the existing stream_ref from the request that the coordinator is expecting
    stream_ref = request.stream_ref

    # Get configurable timeout from request options, config, or default
    stream_timeout =
      request.options[:timeout] ||
        request.config[:streaming_timeout] ||
        opts[:timeout] ||
        @default_timeout

    Logger.debug("ExecuteStreamRequest coordinated stream using timeout: #{stream_timeout}ms")

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
          stream_to_coordinator(
            client,
            endpoint,
            body,
            coordinator,
            stream_ref,
            opts ++ [provider: request.provider, timeout: stream_timeout]
          )
        end)

      %{request | stream_pid: stream_pid}
      |> Request.assign(:streaming_started, true)
      |> Request.put_metadata(:stream_start_time, System.monotonic_time(:millisecond))
      |> Request.put_state(:streaming)
    end
  end

  defp execute_pipeline_stream(request, client, endpoint, body, opts) do
    # Get configurable timeout from request options, config, or default
    stream_timeout =
      request.options[:timeout] ||
        request.config[:streaming_timeout] ||
        opts[:timeout] ||
        @default_timeout

    Logger.debug("ExecuteStreamRequest pipeline stream using timeout: #{stream_timeout}ms")

    # Extract headers from the client's middleware  
    headers = extract_headers_from_client(client)

    # Create a lazy stream that will perform HTTP streaming when consumed
    response_stream =
      Stream.resource(
        fn ->
          # Setup: start streaming task and create communication channels
          parent = self()
          stream_ref = make_ref()
          chunk_buffer = :queue.new()

          # Create callback to send chunks to parent
          callback = fn chunk ->
            Logger.debug(
              "ExecuteStreamRequest callback received chunk: #{inspect(chunk, limit: 100)}"
            )

            send(parent, {stream_ref, {:chunk, chunk}})
          end

          # Start streaming task
          stream_context = %{
            provider: request.provider,
            client: client,
            endpoint: endpoint,
            body: body,
            headers: headers,
            timeout: stream_timeout,
            callback: callback,
            parent: parent,
            stream_ref: stream_ref
          }

          {:ok, stream_pid} =
            Task.start(fn ->
              handle_streaming_task(stream_context)
            end)

          # Return initial state
          {stream_ref, stream_pid, chunk_buffer, false}
        end,
        fn {stream_ref, stream_pid, buffer, done} ->
          if done do
            {:halt, {stream_ref, stream_pid, buffer, done}}
          else
            # Receive chunks or completion
            receive do
              {^stream_ref, {:chunk, chunk}} ->
                new_buffer = :queue.in(chunk, buffer)

                case :queue.out(new_buffer) do
                  {{:value, next_chunk}, remaining_buffer} ->
                    {[next_chunk], {stream_ref, stream_pid, remaining_buffer, false}}

                  {:empty, empty_buffer} ->
                    {[], {stream_ref, stream_pid, empty_buffer, false}}
                end

              {^stream_ref, :stream_complete} ->
                # Drain any remaining chunks from buffer
                remaining_chunks = :queue.to_list(buffer)
                {remaining_chunks, {stream_ref, stream_pid, :queue.new(), true}}

              {^stream_ref, {:stream_error, reason}} ->
                error_chunk = %ExLLM.Types.StreamChunk{
                  content: nil,
                  finish_reason: "error",
                  metadata: %{provider: request.provider, raw: %{error: reason}}
                }

                {[error_chunk], {stream_ref, stream_pid, :queue.new(), true}}
            after
              100 ->
                # No chunk received in 100ms, yield empty and continue
                {[], {stream_ref, stream_pid, buffer, false}}
            end
          end
        end,
        fn {_stream_ref, stream_pid, _buffer, _done} ->
          # Cleanup: ensure task is killed if stream is stopped early
          if Process.alive?(stream_pid) do
            Process.exit(stream_pid, :kill)
          end
        end
      )

    # Set the response stream in assigns and mark as streaming
    request
    |> Request.assign(:response_stream, response_stream)
    |> Request.put_metadata(:stream_start_time, System.monotonic_time(:millisecond))
    |> Request.put_state(:streaming)
  end

  defp execute_direct_stream(request, client, endpoint, body, callback, opts) do
    parent = self()
    stream_ref = make_ref()

    # Get configurable timeout from request options, config, or default
    stream_timeout =
      request.options[:timeout] ||
        request.config[:streaming_timeout] ||
        opts[:timeout] ||
        @default_timeout

    Logger.debug("ExecuteStreamRequest direct stream using timeout: #{stream_timeout}ms")

    # For callback-based streaming, create a minimal stream that just signals completion
    # The actual streaming happens via the callback in the task
    response_stream =
      Stream.resource(
        fn ->
          # Start the streaming task
          {:ok, stream_pid} =
            Task.start(fn ->
              # This will handle the streaming and invoke callbacks
              result =
                stream_response(
                  client,
                  endpoint,
                  body,
                  callback,
                  parent,
                  stream_ref,
                  opts ++ [provider: request.provider, timeout: stream_timeout]
                )

              # Signal completion or error
              case result do
                {:ok, _response} -> send(parent, {:stream_complete, stream_ref})
                {:error, reason} -> send(parent, {:stream_error, stream_ref, reason})
              end
            end)

          {stream_ref, stream_pid, false}
        end,
        fn {ref, pid, done} ->
          if done do
            {:halt, {ref, pid, done}}
          else
            # Wait for streaming to complete
            # Don't expect individual chunks - they're handled by the callback
            receive do
              {:stream_complete, ^ref} ->
                # Streaming completed successfully, halt the stream
                {:halt, {ref, pid, true}}

              {:stream_error, ^ref, reason} ->
                # Return error chunk and halt
                error_chunk = %ExLLM.Types.StreamChunk{
                  content: nil,
                  finish_reason: "error",
                  metadata: %{error: reason}
                }

                {[error_chunk], {ref, pid, true}}
            after
              100 ->
                # Check periodically but don't timeout yet
                {[], {ref, pid, false}}
            end
          end
        end,
        fn {_ref, pid, _done} ->
          # Cleanup
          if Process.alive?(pid) do
            Process.exit(pid, :kill)
          end
        end
      )

    %{request | stream_pid: parent, stream_ref: stream_ref}
    |> Request.assign(:streaming_started, true)
    |> Request.assign(:response_stream, response_stream)
    |> Request.put_metadata(:stream_start_time, System.monotonic_time(:millisecond))
    |> Request.put_state(:streaming)
  end

  defp stream_to_coordinator(client, endpoint, body, coordinator, ref, opts) do
    # Create a callback that forwards chunks to coordinator
    callback = fn chunk ->
      send(coordinator, {:stream_chunk, ref, chunk})
    end

    Logger.debug("Starting stream request to #{endpoint}")

    # Use HTTP.Core for streaming
    # Note: Don't pass headers - the client already has them configured
    case ExLLM.Providers.Shared.HTTP.Core.stream(
           client,
           endpoint,
           body,
           callback,
           timeout: opts[:timeout] || @default_timeout
         ) do
      {:ok, _response} ->
        send(coordinator, {:stream_complete, ref})

      {:error, reason} ->
        send(coordinator, {:stream_error, ref, reason})
    end
  end

  defp stream_response(client, endpoint, body, callback, _parent, _ref, opts) do
    # Use HTTP.Core for streaming
    # Note: Don't pass headers - the client already has them configured
    # Return the result directly - the caller will handle signaling
    ExLLM.Providers.Shared.HTTP.Core.stream(
      client,
      endpoint,
      body,
      callback,
      timeout: opts[:timeout] || @default_timeout
    )
  end

  defp get_endpoint(%Request{provider: provider, config: config}) do
    case provider do
      :gemini ->
        build_gemini_endpoint(config)

      _ ->
        # For streaming, we need just the path, not the full URL
        # The Tesla client already has BaseUrl middleware configured
        config[:endpoint] || get_provider_path(provider)
    end
  end

  defp get_provider_path(:ollama), do: "/api/chat"
  defp get_provider_path(:openai), do: "/v1/chat/completions"
  defp get_provider_path(:anthropic), do: "/v1/messages"
  defp get_provider_path(:groq), do: "/openai/v1/chat/completions"
  defp get_provider_path(:mistral), do: "/v1/chat/completions"
  defp get_provider_path(:lmstudio), do: "/chat/completions"
  defp get_provider_path(_), do: "/"

  defp build_gemini_endpoint(config) do
    model = config[:model] || "gemini-2.0-flash"
    base = config[:base_url] || "https://generativelanguage.googleapis.com/v1beta"
    "#{base}/models/#{model}:streamGenerateContent"
  end

  defp extract_headers_from_client(%Tesla.Client{pre: middleware}) do
    # Find the Headers middleware and extract its headers
    Enum.find_value(middleware, [], fn
      {Tesla.Middleware.Headers, :call, [headers]} -> headers
      _ -> nil
    end)
  end

  defp handle_streaming_task(context) do
    case context.provider do
      :ollama ->
        stream_ollama_ndjson(
          context.client,
          context.endpoint,
          context.body,
          context.headers,
          context.timeout,
          context.callback,
          context.parent,
          context.stream_ref
        )

      _ ->
        handle_non_ollama_streaming(
          context.client,
          context.endpoint,
          context.body,
          context.callback,
          context.timeout,
          context.parent,
          context.stream_ref
        )
    end
  end

  defp handle_non_ollama_streaming(
         client,
         endpoint,
         body,
         callback,
         stream_timeout,
         parent,
         stream_ref
       ) do
    parse_chunk_fn = &parse_openai_raw_chunk/1

    case ExLLM.Providers.Shared.HTTP.Core.stream(
           client,
           endpoint,
           body,
           callback,
           timeout: stream_timeout,
           parse_chunk: parse_chunk_fn
         ) do
      {:ok, _response} ->
        send(parent, {stream_ref, :stream_complete})

      {:error, reason} ->
        send(parent, {stream_ref, {:stream_error, reason}})
    end
  end

  defp extract_ollama_usage(%{
         "prompt_eval_count" => prompt_tokens,
         "eval_count" => completion_tokens
       }) do
    %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens
    }
  end

  defp extract_ollama_usage(_), do: %{}

  # Real-time NDJSON streaming for Ollama using Tesla async
  defp stream_ollama_ndjson(
         client,
         endpoint,
         body,
         _headers,
         stream_timeout,
         callback,
         parent,
         stream_ref
       ) do
    Logger.debug("Starting real-time Ollama NDJSON streaming")

    # Use Tesla with async streaming - this returns immediately
    # Note: Don't pass headers - the client already has them configured
    case Tesla.post(client, endpoint, body,
           opts: [
             adapter: [
               recv_timeout: stream_timeout,
               stream_to: self(),
               async: true,
               with_body: false
             ]
           ]
         ) do
      {:ok, _env} ->
        Logger.debug("Ollama async stream initiated")
        # Now handle the streaming response
        handle_ollama_stream(callback, parent, stream_ref, stream_timeout, "")

      {:error, reason} ->
        Logger.error("Failed to initiate Ollama stream: #{inspect(reason)}")
        send(parent, {stream_ref, {:stream_error, reason}})
    end
  end

  # Handle incoming stream chunks from Ollama
  defp handle_ollama_stream(callback, parent, stream_ref, timeout, buffer) do
    receive do
      {:hackney_response, _ref, {:status, _code, _reason}} ->
        # Status received, continue
        handle_ollama_stream(callback, parent, stream_ref, timeout, buffer)

      {:hackney_response, _ref, {:headers, _headers}} ->
        # Headers received, continue
        handle_ollama_stream(callback, parent, stream_ref, timeout, buffer)

      {:hackney_response, _ref, chunk} when is_binary(chunk) ->
        # Process the chunk - Ollama sends NDJSON
        new_buffer = buffer <> chunk
        {complete_lines, remaining_buffer} = extract_ndjson_lines(new_buffer)

        # Parse and send each complete line immediately
        Enum.each(complete_lines, fn line ->
          case parse_ollama_raw_chunk(line) do
            {:ok, parsed_chunk} ->
              callback.(parsed_chunk)

            _ ->
              :skip
          end
        end)

        # Continue with remaining buffer
        handle_ollama_stream(callback, parent, stream_ref, timeout, remaining_buffer)

      {:hackney_response, _ref, :done} ->
        # Stream completed
        if buffer != "" do
          # Process any remaining data
          case parse_ollama_raw_chunk(buffer) do
            {:ok, parsed_chunk} -> callback.(parsed_chunk)
            _ -> :skip
          end
        end

        send(parent, {stream_ref, :stream_complete})

      {:hackney_response, _ref, {:error, reason}} ->
        Logger.error("Ollama stream error: #{inspect(reason)}")
        send(parent, {stream_ref, {:stream_error, reason}})

      other ->
        Logger.warn("Unexpected message in Ollama stream: #{inspect(other)}")
        handle_ollama_stream(callback, parent, stream_ref, timeout, buffer)
    after
      timeout ->
        Logger.error("Ollama stream timeout")
        send(parent, {stream_ref, {:stream_error, :timeout}})
    end
  end

  # Extract complete NDJSON lines from buffer
  defp extract_ndjson_lines(buffer) do
    case String.split(buffer, "\n", parts: 2) do
      [complete_line, rest] ->
        # Found a newline, extract the line and continue
        {lines, final_buffer} = extract_ndjson_lines(rest)
        {[complete_line | lines], final_buffer}

      [incomplete] ->
        # No newline found, this is the remaining buffer
        {[], incomplete}
    end
  end

  # Parse raw chunk data for Ollama (NDJSON format)
  defp parse_ollama_raw_chunk(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, %{"done" => true} = chunk_data} ->
        # Final chunk with usage stats
        {:ok,
         %ExLLM.Types.StreamChunk{
           content: "",
           finish_reason: chunk_data["done_reason"] || "stop",
           model: chunk_data["model"],
           metadata: %{
             provider: :ollama,
             raw: chunk_data,
             usage: extract_ollama_usage(chunk_data)
           }
         }}

      {:ok, %{"message" => %{"content" => content}} = chunk_data} ->
        {:ok,
         %ExLLM.Types.StreamChunk{
           content: content || "",
           finish_reason: nil,
           model: chunk_data["model"],
           metadata: %{provider: :ollama, raw: chunk_data}
         }}

      {:ok, %{"response" => content} = chunk_data} ->
        # Alternative format for some Ollama models
        {:ok,
         %ExLLM.Types.StreamChunk{
           content: content || "",
           finish_reason: nil,
           model: chunk_data["model"],
           metadata: %{provider: :ollama, raw: chunk_data}
         }}

      {:error, _} ->
        {:error, :invalid_json}

      _ ->
        {:error, :unrecognized_format}
    end
  end

  # Parse raw chunk data for OpenAI-compatible providers (SSE format)
  defp parse_openai_raw_chunk(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, parsed} ->
        choices = parsed["choices"] || []

        first_choice =
          if is_list(choices) and length(choices) > 0, do: Enum.at(choices, 0), else: %{}

        delta = first_choice["delta"] || %{}
        content = delta["content"] || delta["reasoning_content"]
        finish_reason = first_choice["finish_reason"]

        {:ok,
         %ExLLM.Types.StreamChunk{
           content: content,
           finish_reason: finish_reason,
           id: parsed["id"],
           model: parsed["model"],
           metadata: %{provider: :openai, raw: parsed}
         }}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end
end
