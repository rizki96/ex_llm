defmodule ExLLM.Providers.Shared.HTTP.Core do
  @moduledoc """
  Core HTTP client module using Tesla middleware architecture.

  This module provides the foundation for HTTP operations across all providers,
  implementing a declarative middleware stack for cross-cutting concerns like
  authentication, caching, error handling, and request/response processing.

  ## Tesla Middleware Stack

  The middleware stack is assembled in order of execution:
  1. BaseURL - Sets the base URL for requests
  2. JSON - Handles JSON encoding/decoding  
  3. Authentication - Adds provider-specific auth headers
  4. Cache - Implements response caching
  5. ErrorHandling - Handles retries and error mapping
  6. Logger - Request/response logging
  7. Adapter - HTTP adapter (Hackney/Mint)

  ## Usage

      client = HTTP.Core.client(provider: :openai, api_key: "sk-...")
      {:ok, response} = Tesla.get(client, "/v1/models")
      
      # Streaming
      {:ok, response} = HTTP.Core.stream(client, "/chat/completions", body, callback)
  """

  alias ExLLM.Infrastructure.Streaming.SSEParser
  alias ExLLM.Providers.Shared.HTTP

  require Logger

  @doc """
  Create a Tesla client with the appropriate middleware stack for a provider.

  ## Options
  - `:provider` - Provider atom (`:openai`, `:anthropic`, etc.)
  - `:api_key` - API key for authentication
  - `:base_url` - Base URL for the provider
  - `:cache_enabled` - Enable response caching (default: false)
  - `:retry_enabled` - Enable retry logic (default: true)
  - `:timeout` - Request timeout in milliseconds (default: 60_000)
  - `:adapter_opts` - Options for the HTTP adapter
  """
  @spec client(keyword()) :: Tesla.Client.t()
  def client(opts \\ []) do
    provider = Keyword.get(opts, :provider, :openai)

    # Build cache config from opts
    cache_config = Enum.into(opts, %{})
    
    # Use cache to get or create client
    ExLLM.Tesla.ClientCache.get_or_create(provider, cache_config, fn ->
      middleware = build_middleware_stack(provider, opts)
      adapter = build_adapter(opts)
      Tesla.client(middleware, adapter)
    end)
  end

  @doc """
  Send a streaming POST request with Server-Sent Events handling.

  ## Parameters
  - `client` - Tesla client instance
  - `path` - Request path (e.g., "/chat/completions") 
  - `body` - Request body (will be JSON encoded)
  - `callback` - Function to call for each streaming chunk
  - `opts` - Additional options

  ## Options
  - `:headers` - Additional headers
  - `:timeout` - Streaming timeout (default: 300_000ms)
  - `:parse_chunk` - Function to parse SSE chunks

  ## Returns
  `{:ok, final_response}` on success, `{:error, reason}` on failure.
  """
  @spec stream(Tesla.Client.t(), String.t(), term(), function(), keyword()) ::
          {:ok, Tesla.Env.t()} | {:error, term()}
  def stream(client, path, body, callback, opts \\ []) do
    parse_chunk_fn = Keyword.get(opts, :parse_chunk, &default_parse_chunk/1)
    streaming_body = prepare_streaming_body(body)

    if Application.get_env(:ex_llm, :use_tesla_mock, false) do
      handle_test_mode_streaming(client, path, streaming_body, callback, parse_chunk_fn)
    else
      handle_production_streaming(client, path, streaming_body, callback, parse_chunk_fn, opts)
    end
  end

  defp prepare_streaming_body(body) do
    body
    |> ensure_map()
    |> ensure_stream_flag()
  end

  defp handle_test_mode_streaming(client, path, body, callback, parse_chunk_fn) do
    case Tesla.post(client, path, body) do
      {:ok, response} ->
        if is_binary(response.body) && String.contains?(response.body, "data:") do
          simulate_streaming_from_body(response.body, callback, parse_chunk_fn)
        end

        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_production_streaming(client, path, body, callback, parse_chunk_fn, opts) do
    Logger.debug("HTTP.Core starting streaming POST to path: #{path}")
    Logger.debug("Body keys: #{inspect(Map.keys(body))}")

    stream_timeout = Keyword.get(opts, :timeout, 300_000)
    Logger.debug("HTTP.Core using stream timeout: #{stream_timeout}ms")

    streaming_client = build_streaming_client(client, stream_timeout)

    case Tesla.post(streaming_client, path, body) do
      {:ok, env} -> handle_streaming_response(env, callback, parse_chunk_fn, stream_timeout)
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_streaming_response(env, callback, parse_chunk_fn, timeout) do
    cond do
      ExLLM.HTTP.successful?(env) ->
        status = ExLLM.HTTP.get_status(env)
        body = ExLLM.HTTP.get_body(env)

        Logger.debug(
          "HTTP.Core got initial async response, status: #{status}, body type: #{inspect(body) |> String.slice(0, 100)}"
        )

        handle_response_body(body, env, callback, parse_chunk_fn, timeout)

      ExLLM.HTTP.timeout_error?(env) ->
        {:error, :timeout}

      true ->
        status = ExLLM.HTTP.get_status(env)
        Logger.debug("HTTP.Core got non-streaming response: #{inspect(status)}")
        {:error, {:api_error, status}}
    end
  end

  defp handle_response_body(body, env, callback, parse_chunk_fn, timeout)
       when is_reference(body) do
    Logger.debug("HTTP.Core using async streaming with reference")
    result = handle_stream_chunks(callback, parse_chunk_fn, timeout)
    Logger.debug("HTTP.Core streaming result: #{inspect(result)}")
    {:ok, env}
  end

  defp handle_response_body(body, env, callback, parse_chunk_fn, _timeout) when is_binary(body) do
    if String.contains?(body, "data:") do
      Logger.debug("HTTP.Core received full SSE body, processing...")
      simulate_streaming_from_body(body, callback, parse_chunk_fn)
      {:ok, env}
    else
      Logger.error("HTTP.Core received non-SSE binary body for 2xx response: #{inspect(body)}")
      {:error, {:unexpected_streaming_body, body}}
    end
  end

  defp handle_response_body(body, _env, _callback, _parse_chunk_fn, _timeout) do
    Logger.error("HTTP.Core received unexpected body type for 2xx response: #{inspect(body)}")
    {:error, {:unexpected_streaming_body_type, body}}
  end

  @doc """
  Upload a file using multipart/form-data.

  ## Parameters
  - `client` - Tesla client instance
  - `path` - Upload endpoint path
  - `multipart_data` - List of form parts
  - `opts` - Additional options

  ## Multipart Data Format
  Each part is a tuple: `{name, content}` or `{name, content, headers}`

  ## Example
      multipart = [
        {"purpose", "fine-tune"},
        {"file", file_content, [{"filename", "data.txt"}]}
      ]
      
      {:ok, response} = HTTP.Core.upload(client, "/files", multipart)
  """
  @spec upload(Tesla.Client.t(), String.t(), list(), keyword()) ::
          {:ok, Tesla.Env.t()} | {:error, term()}
  def upload(client, path, multipart_data, opts \\ []) do
    headers =
      [
        {"content-type", "multipart/form-data"}
      ] ++ Keyword.get(opts, :headers, [])

    Tesla.post(
      client,
      path,
      format_multipart_data(multipart_data),
      headers: headers
    )
  end

  # Private functions

  defp simulate_streaming_from_body(body, callback, parse_chunk_fn) do
    # For Bypass tests, the body contains the full SSE response
    # Parse it and invoke callbacks as if it were streaming
    parser = SSEParser.new()
    {events, _parser} = SSEParser.parse_data_events(parser, body)

    Enum.each(events, fn
      :done ->
        # [DONE] marker, ignore
        :ok

      event_data ->
        # Parse the chunk and invoke callback
        case parse_chunk_fn.(event_data) do
          {:ok, chunk} when not is_nil(chunk) ->
            callback.(chunk)

          _ ->
            :skip
        end
    end)
  end

  defp handle_stream_chunks(callback, parse_chunk_fn, timeout) do
    receive do
      {:hackney_response, _ref, {:status, code, reason}} ->
        # Status received, continue
        Logger.debug("HTTP.Core received status: #{code} #{reason}")
        handle_stream_chunks(callback, parse_chunk_fn, timeout)

      {:hackney_response, _ref, {:headers, headers}} ->
        # Headers received, continue
        Logger.debug("HTTP.Core received headers: #{inspect(headers)}")
        handle_stream_chunks(callback, parse_chunk_fn, timeout)

      {:hackney_response, _ref, chunk} when is_binary(chunk) ->
        # Process the chunk through SSE parser
        Logger.debug("HTTP.Core received chunk: #{byte_size(chunk)} bytes")
        parser = SSEParser.new()
        {events, _parser} = SSEParser.parse_data_events(parser, chunk)

        Enum.each(events, fn
          :done ->
            :ok

          event_data ->
            case parse_chunk_fn.(event_data) do
              {:ok, parsed_chunk} when not is_nil(parsed_chunk) ->
                callback.(parsed_chunk)

              _ ->
                :skip
            end
        end)

        # Continue receiving chunks
        handle_stream_chunks(callback, parse_chunk_fn, timeout)

      {:hackney_response, _ref, :done} ->
        # Stream completed
        Logger.debug("HTTP.Core stream completed")
        :ok

      {:hackney_response, _ref, {:error, reason}} ->
        # Error occurred
        Logger.debug("HTTP.Core stream error: #{inspect(reason)}")
        {:error, reason}

      other ->
        Logger.debug("HTTP.Core received unexpected message: #{inspect(other)}")
        handle_stream_chunks(callback, parse_chunk_fn, timeout)
    after
      timeout ->
        Logger.debug("HTTP.Core stream timeout after #{timeout}ms")
        {:error, :timeout}
    end
  end

  defp build_middleware_stack(provider, opts) do
    json_middleware =
      if Keyword.get(opts, :json_enabled, true) do
        [{Tesla.Middleware.JSON, engine_opts: [keys: :strings]}]
      else
        []
      end

    base_middleware =
      [
        {Tesla.Middleware.BaseUrl, get_base_url(provider, opts)}
      ] ++ json_middleware

    auth_middleware =
      if Keyword.get(opts, :auth_enabled, true) do
        auth_opts = [provider: provider]

        # Add API key if present
        auth_opts =
          if api_key = Keyword.get(opts, :api_key) do
            Keyword.put(auth_opts, :api_key, api_key)
          else
            auth_opts
          end

        # Add OAuth token if present
        auth_opts =
          if oauth_token = Keyword.get(opts, :oauth_token) do
            Keyword.put(auth_opts, :oauth_token, oauth_token)
          else
            auth_opts
          end

        [{HTTP.Authentication, auth_opts}]
      else
        []
      end

    cache_middleware =
      if Keyword.get(opts, :cache_enabled, false) do
        [{HTTP.Cache, cache_opts(opts)}]
      else
        []
      end

    error_middleware =
      if Keyword.get(opts, :retry_enabled, true) do
        [{HTTP.ErrorHandling, error_opts(opts)}]
      else
        []
      end

    logging_middleware =
      if Keyword.get(opts, :logging_enabled, true) do
        debug_level =
          Keyword.get(opts, :debug, Application.get_env(:ex_llm, :log_level, :info) == :debug)

        [{Tesla.Middleware.Logger, debug: debug_level}]
      else
        []
      end

    # Add response capture middleware if enabled
    capture_middleware =
      if ExLLM.ResponseCapture.enabled?() do
        [{HTTP.ResponseCapture, [provider: provider]}]
      else
        []
      end

    # Assemble middleware stack in execution order
    base_middleware ++
      auth_middleware ++
      cache_middleware ++
      error_middleware ++
      logging_middleware ++
      capture_middleware
  end

  defp build_adapter(opts) do
    # Use Tesla.Mock in tests if configured
    default_adapter =
      if Application.get_env(:ex_llm, :use_tesla_mock, false) do
        Tesla.Mock
      else
        ExLLM.Providers.Shared.HTTP.SafeHackneyAdapter
      end

    adapter_name = Keyword.get(opts, :adapter, default_adapter)
    adapter_opts = Keyword.get(opts, :adapter_opts, [])

    default_opts = [
      recv_timeout: Keyword.get(opts, :timeout, 60_000),
      follow_redirect: true,
      max_redirect: 3
    ]

    case adapter_name do
      Tesla.Mock -> Tesla.Mock
      adapter -> {adapter, Keyword.merge(default_opts, adapter_opts)}
    end
  end

  defp get_base_url(provider, opts) do
    result = Keyword.get(opts, :base_url) || get_default_base_url(provider)

    Logger.debug(
      "HTTP.Core get_base_url: provider=#{provider}, base_url_opt=#{inspect(Keyword.get(opts, :base_url))}, result=#{result}"
    )

    result
  end

  defp get_default_base_url(provider) do
    case provider do
      :openai -> "https://api.openai.com"
      :anthropic -> "https://api.anthropic.com"
      :groq -> "https://api.groq.com/openai"
      :gemini -> "https://generativelanguage.googleapis.com/v1beta"
      :ollama -> "http://localhost:11434"
      :lmstudio -> "http://localhost:1234"
      :mistral -> "https://api.mistral.ai"
      :openrouter -> "https://openrouter.ai"
      :perplexity -> "https://api.perplexity.ai"
      :xai -> "https://api.x.ai"
      _ -> raise ArgumentError, "Unknown provider: #{provider}"
    end
  end

  defp cache_opts(opts) do
    [
      ttl: Keyword.get(opts, :cache_ttl, 300_000),
      key_prefix: Keyword.get(opts, :cache_key_prefix, "http_cache"),
      enabled: true
    ]
  end

  defp error_opts(opts) do
    [
      max_retries: Keyword.get(opts, :max_retries, 3),
      retry_delay: Keyword.get(opts, :retry_delay, 1000),
      backoff_factor: Keyword.get(opts, :backoff_factor, 2.0),
      retry_codes: Keyword.get(opts, :retry_codes, [500, 502, 503, 504])
    ]
  end

  defp default_parse_chunk(data) do
    case Jason.decode(data) do
      {:ok, parsed} ->
        choices = parsed["choices"] || []

        first_choice =
          if is_list(choices) and length(choices) > 0, do: Enum.at(choices, 0), else: %{}

        delta = first_choice["delta"] || %{}
        content = delta["content"] || delta["reasoning_content"] || ""
        finish_reason = first_choice["finish_reason"]

        chunk = %ExLLM.Types.StreamChunk{
          content: content,
          finish_reason: finish_reason
        }

        {:ok, chunk}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp format_multipart_data(data) do
    # Convert to Tesla-compatible multipart format
    parts =
      Enum.map(data, fn
        {name, content} ->
          {name, content}

        {name, content, headers} ->
          {name, content, headers}
      end)

    {:multipart, parts}
  end

  defp ensure_map(data) when is_map(data), do: data
  defp ensure_map(data), do: %{"data" => data}

  defp ensure_stream_flag(body) do
    # Check if stream flag already exists with either atom or string key
    if Map.has_key?(body, :stream) || Map.has_key?(body, "stream") do
      # Ensure we have atom key and remove any string key
      body
      |> Map.delete("stream")
      |> Map.put(:stream, true)
    else
      # No stream flag exists, add it
      Map.put(body, :stream, true)
    end
  end

  defp build_streaming_client(
         %Tesla.Client{pre: middleware, adapter: _original_adapter} = _client,
         timeout
       ) do
    # Create a new client specifically for streaming
    # We need to copy the middleware but use a streaming-enabled adapter
    streaming_adapter = {
      ExLLM.Providers.Shared.HTTP.SafeHackneyAdapter,
      [
        recv_timeout: timeout,
        stream_to: self(),
        async: true,
        with_body: false,
        follow_redirect: true,
        max_redirect: 3
      ]
    }

    # Convert middleware from runtime format to builder format
    # Tesla stores middleware as {module, :call, [args]} in runtime format
    builder_middleware =
      Enum.map(middleware, fn
        {module, :call, []} -> module
        {module, :call, [args]} -> {module, args}
        other -> other
      end)

    Tesla.client(builder_middleware, streaming_adapter)
  end
end
