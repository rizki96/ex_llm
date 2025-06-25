defmodule ExLLM.Providers.Shared.Streaming.Engine do
  @moduledoc """
  Core streaming engine using Tesla middleware architecture.

  This module provides a clean, composable streaming implementation that replaces
  the monolithic StreamingCoordinator. It uses Tesla's middleware pattern to 
  decompose streaming concerns into focused, testable components.

  ## Architecture

  The streaming engine uses a Tesla client with a structured middleware stack:

  ```
  Tesla Client
  ├── BaseUrl (provider base URL)
  ├── Headers (SSE headers + auth)
  ├── StreamCollector (core streaming logic)
  ├── SSEParser (Server-Sent Events parsing)
  ├── ChunkValidator (chunk validation)
  ├── StreamMetrics (metrics collection)
  ├── ErrorRecovery (error handling)
  └── FlowControl (optional backpressure)
  ```

  ## Features

  - **Clean separation of concerns** - Each responsibility in its own middleware
  - **Backward compatibility** - Maintains existing StreamingCoordinator API
  - **Composable middleware** - Mix and match features as needed
  - **Testable components** - Each middleware can be tested in isolation
  - **Provider-agnostic** - Works with all LLM providers
  - **Performance optimized** - Built on proven Tesla middleware infrastructure

  ## Usage

  ```elixir
  # Create a streaming client
  client = Streaming.Engine.client(
    provider: :openai,
    api_key: "sk-...",
    base_url: "https://api.openai.com/v1"
  )

  # Start streaming
  {:ok, stream_id} = Streaming.Engine.stream(
    client,
    "/chat/completions",
    request_body,
    callback: callback_fn,
    parse_chunk: &MyAdapter.parse_chunk/1,
    recovery_enabled: true
  )
  ```

  ## Configuration Options

  ### Core Options
  - `:callback` - Function to handle each streaming chunk (required)
  - `:parse_chunk` - Function to parse provider-specific chunk data (required)
  - `:timeout` - Stream timeout in milliseconds (default: 5 minutes)
  - `:recovery_enabled` - Enable stream recovery (default: false)

  ### Middleware Options
  - `:metrics_callback` - Function to receive metrics updates
  - `:chunk_validator` - Function to validate chunks before delivery
  - `:flow_control` - Flow control configuration (see FlowControl middleware)
  - `:batching` - Chunk batching configuration (see ChunkBatcher middleware)

  ### Provider Options
  - `:provider` - Provider atom (:openai, :anthropic, etc.)
  - `:api_key` - API key for authentication
  - `:base_url` - Provider base URL (optional, defaults based on provider)
  """

  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Types

  # Default timeouts
  @default_timeout :timer.minutes(5)
  @default_connect_timeout :timer.seconds(30)

  @typedoc """
  Streaming options for configuring the engine and middleware.
  """
  @type stream_opts :: [
          # Core streaming options
          callback: (Types.StreamChunk.t() -> any()),
          parse_chunk: (binary() -> {:ok, Types.StreamChunk.t() | :done} | {:error, term()}),
          timeout: pos_integer(),
          recovery_enabled: boolean(),
          return_env: boolean(),

          # Middleware options
          metrics_callback: (map() -> any()),
          chunk_validator: (Types.StreamChunk.t() -> :ok | {:error, term()}),
          flow_control: keyword(),
          batching: keyword(),

          # Provider options
          provider: atom(),
          api_key: String.t(),
          base_url: String.t()
        ]

  @typedoc """
  Client options for configuring the Tesla client and middleware stack.
  """
  @type client_opts :: [
          provider: atom(),
          api_key: String.t(),
          base_url: String.t(),
          timeout: pos_integer(),
          connect_timeout: pos_integer(),
          enable_metrics: boolean(),
          enable_recovery: boolean(),
          enable_flow_control: boolean(),
          enable_batching: boolean()
        ]

  @doc """
  Create a streaming Tesla client with configured middleware stack.

  The middleware stack is automatically configured based on the provided options.
  Optional middleware is only included when explicitly enabled.

  ## Examples

      # Basic streaming client
      client = Engine.client(provider: :openai, api_key: "sk-...")

      # Client with advanced features
      client = Engine.client(
        provider: :anthropic,
        api_key: "sk-ant-...",
        enable_metrics: true,
        enable_flow_control: true,
        enable_recovery: true
      )
  """
  @spec client() :: Tesla.Client.t()
  def client() do
    client([])
  end

  @spec client(client_opts()) :: Tesla.Client.t()
  def client(opts) when is_list(opts) do
    provider = Keyword.get(opts, :provider, :openai)
    base_url = Keyword.get(opts, :base_url) || get_default_base_url(provider)

    middleware = build_middleware_stack(opts)

    Logger.debug(
      "Creating streaming client for #{provider} with #{length(middleware)} middleware"
    )

    # Add base URL middleware to the stack
    middleware_with_base_url = [
      {Tesla.Middleware.BaseUrl, base_url} | middleware
    ]

    Tesla.client(middleware_with_base_url, {Tesla.Adapter.Hackney, build_adapter_opts(opts)})
  end

  @doc """
  Start a streaming request using the configured Tesla client.

  This is the main entry point for streaming requests. It creates a streaming
  request using Tesla's built-in streaming capabilities and processes the
  response through the configured middleware stack.

  ## Examples

      client = Engine.client(provider: :openai, api_key: "sk-...")
      
      {:ok, stream_id} = Engine.stream(
        client,
        "/chat/completions",
        %{
          model: "gpt-4",
          messages: [%{role: "user", content: "Hello"}],
          stream: true
        },
        callback: fn chunk ->
          IO.puts("Received: \#{chunk.content}")
        end,
        parse_chunk: &MyAdapter.parse_chunk/1
      )

  ## Returns

  - `{:ok, stream_id}` - Successfully started streaming
  - `{:error, reason}` - Failed to start stream
  """
  @spec stream(Tesla.Client.t(), String.t(), map(), stream_opts()) ::
          {:ok, String.t()} | {:ok, {String.t(), Tesla.Env.t()}} | {:error, term()}
  @dialyzer {:nowarn_function, stream: 4}
  def stream(client, path, body, opts \\ []) do
    callback = Keyword.fetch!(opts, :callback)
    parse_chunk_fn = Keyword.fetch!(opts, :parse_chunk)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    return_env = Keyword.get(opts, :return_env, false)

    # Generate unique stream ID
    stream_id = generate_stream_id()

    # Initialize stream context for middleware
    stream_context = %{
      stream_id: stream_id,
      provider: extract_provider_from_client(client),
      start_time: System.monotonic_time(:millisecond),
      callback: callback,
      parse_chunk_fn: parse_chunk_fn,
      opts: opts,
      return_env: return_env
    }

    Logger.debug("Starting stream #{stream_id} for #{path}")

    if return_env do
      # Synchronous execution for backward compatibility
      case execute_stream_sync(client, path, body, stream_context, timeout) do
        {:ok, response} -> {:ok, {stream_id, response}}
        {:error, reason} -> {:error, reason}
      end
    else
      # Start streaming task (original async behavior)
      task =
        Task.async(fn ->
          execute_stream(client, path, body, stream_context, timeout)
        end)

      # Store task reference for potential cancellation
      store_stream_task(stream_id, task)

      {:ok, stream_id}
    end
  end

  @doc """
  Cancel an active streaming request.

  ## Examples

      {:ok, stream_id} = Engine.stream(client, path, body, opts)
      :ok = Engine.cancel_stream(stream_id)
  """
  @spec cancel_stream(String.t()) :: :ok | {:error, :not_found}
  def cancel_stream(stream_id) do
    case get_stream_task(stream_id) do
      nil ->
        {:error, :not_found}

      task ->
        Task.shutdown(task, :brutal_kill)
        remove_stream_task(stream_id)
        Logger.debug("Cancelled stream #{stream_id}")
        :ok
    end
  end

  @doc """
  Get status information for an active stream.

  ## Examples

      {:ok, stream_id} = Engine.stream(client, path, body, opts)
      
      case Engine.stream_status(stream_id) do
        {:ok, :running} -> IO.puts("Stream is active")
        {:ok, :completed} -> IO.puts("Stream completed")
        {:error, :not_found} -> IO.puts("Stream not found")
      end
  """
  @spec stream_status(String.t()) :: {:ok, :running | :completed} | {:error, :not_found}
  def stream_status(stream_id) do
    case get_stream_task(stream_id) do
      nil ->
        {:error, :not_found}

      task ->
        if Process.alive?(task.pid) do
          {:ok, :running}
        else
          remove_stream_task(stream_id)
          {:ok, :completed}
        end
    end
  end

  # Private functions

  defp execute_stream_sync(client, path, body, stream_context, timeout) do
    stream_id = stream_context.stream_id

    try do
      # Prepare streaming request
      headers = [
        {"accept", "text/event-stream"},
        {"cache-control", "no-cache"}
      ]

      # Execute streaming POST request and return the response directly
      # Pass stream context in opts for middleware access
      case Tesla.post(client, path, body,
             headers: headers,
             opts: [recv_timeout: timeout, stream_to: self(), stream_context: stream_context]
           ) do
        {:ok, response} ->
          {:ok, response}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Stream #{stream_id} crashed: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end

  defp execute_stream(client, path, body, stream_context, timeout) do
    stream_id = stream_context.stream_id

    try do
      # Prepare streaming request
      headers = [
        {"accept", "text/event-stream"},
        {"cache-control", "no-cache"}
      ]

      # Execute streaming POST request
      # Pass stream context in opts for middleware access
      case Tesla.post(client, path, body,
             headers: headers,
             opts: [recv_timeout: timeout, stream_to: self(), stream_context: stream_context]
           ) do
        {:ok, response} ->
          handle_stream_response(response, stream_context)

        {:error, reason} ->
          handle_stream_error(reason, stream_context)
      end
    rescue
      error ->
        Logger.error("Stream #{stream_id} crashed: #{inspect(error)}")
        handle_stream_error({:exception, error}, stream_context)
    after
      remove_stream_task(stream_id)
    end
  end

  @dialyzer {:nowarn_function, handle_stream_response: 2}
  defp handle_stream_response(response, stream_context) do
    stream_id = stream_context.stream_id

    case response.status do
      200 ->
        Logger.debug("Stream #{stream_id} completed successfully")

        # Send completion chunk
        completion_chunk = %Types.StreamChunk{
          content: "",
          finish_reason: "stop"
        }

        stream_context.callback.(completion_chunk)
        :ok

      status ->
        error = {:http_error, status, response.body}
        handle_stream_error(error, stream_context)
    end
  end

  defp handle_stream_error(reason, stream_context) do
    stream_id = stream_context.stream_id

    Logger.error("Stream #{stream_id} error: #{inspect(reason)}")

    # Create error chunk
    error_chunk = %Types.StreamChunk{
      content: "Error: #{inspect(reason)}",
      finish_reason: "error"
    }

    stream_context.callback.(error_chunk)
    {:error, reason}
  end

  defp build_middleware_stack(opts) do
    provider = Keyword.get(opts, :provider, :openai)
    api_key = Keyword.get(opts, :api_key)

    # Build headers including auth
    headers = [{"user-agent", "ExLLM/1.0.0"}] ++ build_auth_headers(provider, api_key)

    base_middleware = [
      # Core middleware (always present)
      {Tesla.Middleware.Headers, headers},
      {Tesla.Middleware.JSON, engine: Jason},
      # Add our streaming collector middleware
      ExLLM.Providers.Shared.Streaming.Middleware.StreamCollector
    ]

    # Add optional middleware based on configuration
    base_middleware
    |> maybe_add_metrics_middleware(opts)
    |> maybe_add_recovery_middleware(opts)
    |> maybe_add_flow_control_middleware(opts)
    |> maybe_add_batching_middleware(opts)
  end

  defp maybe_add_metrics_middleware(middleware, opts) do
    if Keyword.get(opts, :enable_metrics, false) do
      # Extract metrics-specific options
      metrics_opts = [
        enabled: true,
        callback: Keyword.get(opts, :metrics_callback),
        interval: Keyword.get(opts, :metrics_interval, 1000),
        include_raw_data: Keyword.get(opts, :include_raw_chunks, false)
      ]

      middleware ++ [{ExLLM.Providers.Shared.Streaming.Middleware.MetricsPlug, metrics_opts}]
    else
      middleware
    end
  end

  defp maybe_add_recovery_middleware(middleware, opts) do
    if Keyword.get(opts, :enable_recovery, false) do
      # TODO: Add ErrorRecovery middleware when implemented
      middleware
    else
      middleware
    end
  end

  defp maybe_add_flow_control_middleware(middleware, opts) do
    if Keyword.get(opts, :enable_flow_control, false) do
      # TODO: Add FlowControl middleware when implemented
      middleware
    else
      middleware
    end
  end

  defp maybe_add_batching_middleware(middleware, opts) do
    if Keyword.get(opts, :enable_batching, false) do
      # TODO: Add ChunkBatcher middleware when implemented
      middleware
    else
      middleware
    end
  end

  defp build_adapter_opts(opts) do
    [
      recv_timeout: Keyword.get(opts, :timeout, @default_timeout),
      connect_timeout: Keyword.get(opts, :connect_timeout, @default_connect_timeout),
      stream_to: self()
    ]
  end

  defp build_auth_headers(provider, api_key) do
    case provider do
      :openai -> [{"authorization", "Bearer #{api_key}"}]
      :anthropic -> [{"x-api-key", api_key}, {"anthropic-version", "2023-06-01"}]
      :groq -> [{"authorization", "Bearer #{api_key}"}]
      :gemini -> [{"authorization", "Bearer #{api_key}"}]
      _ -> [{"authorization", "Bearer #{api_key}"}]
    end
  end

  defp get_default_base_url(provider) do
    case provider do
      :openai -> "https://api.openai.com/v1"
      :anthropic -> "https://api.anthropic.com"
      :groq -> "https://api.groq.com/openai/v1"
      :gemini -> "https://generativelanguage.googleapis.com/v1beta"
      :ollama -> "http://localhost:11434/api"
      :lmstudio -> "http://localhost:1234/v1"
      :mistral -> "https://api.mistral.ai/v1"
      :openrouter -> "https://openrouter.ai/api/v1"
      :perplexity -> "https://api.perplexity.ai"
      :xai -> "https://api.x.ai/v1"
      # Default fallback
      _ -> "https://api.openai.com/v1"
    end
  end

  defp extract_provider_from_client(_client) do
    # Extract provider from client options or base URL
    # This is a simplified implementation
    :unknown
  end

  defp generate_stream_id do
    "stream_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end

  # Simple in-memory storage for stream tasks
  # In production, this might use a more sophisticated storage mechanism

  defp store_stream_task(stream_id, task) do
    :persistent_term.put({__MODULE__, :stream_task, stream_id}, task)
  end

  defp get_stream_task(stream_id) do
    try do
      :persistent_term.get({__MODULE__, :stream_task, stream_id})
    rescue
      ArgumentError -> nil
    end
  end

  defp remove_stream_task(stream_id) do
    try do
      :persistent_term.erase({__MODULE__, :stream_task, stream_id})
    rescue
      ArgumentError -> :ok
    end
  end
end
