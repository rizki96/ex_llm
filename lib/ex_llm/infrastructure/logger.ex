defmodule ExLLM.Infrastructure.Logger do
  @moduledoc """
  Unified logging for ExLLM with automatic context and security features.

  This module provides a simple, unified logging interface that combines
  the simplicity of Elixir's Logger with ExLLM-specific features like
  context tracking, security redaction, and component filtering.

  ## Usage

  Simple logging (like Elixir's Logger):

      ExLLM.Infrastructure.Logger.info("Model loaded successfully")
      ExLLM.Infrastructure.Logger.error("Failed to connect", error: reason)
      ExLLM.Infrastructure.Logger.debug("Processing chunk", size: byte_size(data))

  With provider context:

      ExLLM.Infrastructure.Logger.with_context(provider: :openai, operation: :chat) do
        ExLLM.Infrastructure.Logger.info("Starting chat request")
        # ... do work ...
        ExLLM.Infrastructure.Logger.info("Chat completed", tokens: 150)
      end

  Structured logging for specific events:

      ExLLM.Infrastructure.Logger.log_request(:openai, url, body, headers)
      ExLLM.Infrastructure.Logger.log_response(:openai, response, duration_ms)
      ExLLM.Infrastructure.Logger.log_retry(:anthropic, attempt, max_attempts, reason)

  ## Configuration

      config :ex_llm,
        log_level: :info,  # :debug, :info, :warn, :error, :none
        log_components: %{
          requests: true,
          responses: true,
          streaming: false,
          retries: true,
          cache: false,
          models: true
        },
        log_redaction: %{
          api_keys: true,
          content: false
        }
  """

  require Logger

  # Store context in process dictionary
  @context_key :ex_llm_logger_context

  # Public API - Simple logging functions

  @doc """
  Log a debug message with optional metadata.
  """
  def debug(message, metadata \\ []) do
    log(:debug, message, metadata)
  end

  @doc """
  Log an info message with optional metadata.
  """
  def info(message, metadata \\ []) do
    log(:info, message, metadata)
  end

  @doc """
  Log a warning message with optional metadata.
  """
  def warn(message, metadata \\ []) do
    log(:warning, message, metadata)
  end

  @doc """
  Log a warning message with optional metadata.
  Alias for warn/1 to maintain compatibility with modern Elixir Logger API.
  """
  def warning(message, metadata \\ []) do
    log(:warning, message, metadata)
  end

  @doc """
  Log an error message with optional metadata.
  """
  def error(message, metadata \\ []) do
    log(:error, message, metadata)
  end

  @doc """
  Set context for all logs within the given function.

  ## Examples

      ExLLM.Infrastructure.Logger.with_context(provider: :openai, operation: :chat) do
        ExLLM.Infrastructure.Logger.info("Starting request")
        # All logs in here will include provider and operation
      end
  """
  def with_context(context, fun) do
    old_context = Process.get(@context_key, %{})
    merged_context = Map.merge(old_context, Enum.into(context, %{}))

    Process.put(@context_key, merged_context)

    try do
      fun.()
    after
      Process.put(@context_key, old_context)
    end
  end

  @doc """
  Add context that persists for the rest of the process.
  """
  def put_context(context) do
    current = Process.get(@context_key, %{})
    Process.put(@context_key, Map.merge(current, Enum.into(context, %{})))
  end

  @doc """
  Clear all context.
  """
  def clear_context do
    Process.delete(@context_key)
  end

  # Structured logging for specific ExLLM events

  @doc """
  Log an API request with automatic redaction.
  """
  def log_request(provider, url, body, headers \\ []) do
    if should_log?(:requests) do
      metadata = [
        component: :request,
        provider: provider,
        url: redact_url(url),
        method: "POST",
        body: redact_body(body),
        headers: redact_headers(headers)
      ]

      info("API request", metadata)
    end
  end

  @doc """
  Log an API response.
  """
  def log_response(provider, response, duration_ms) do
    if should_log?(:responses) do
      metadata = [
        component: :response,
        provider: provider,
        duration_ms: duration_ms,
        status: get_status(response),
        model: get_model(response)
      ]

      # Add usage if available
      metadata =
        case get_usage(response) do
          nil -> metadata
          usage -> Keyword.put(metadata, :usage, usage)
        end

      info("API response", metadata)
    end
  end

  @doc """
  Log a streaming event.
  """
  def log_stream_event(provider, event, data \\ %{}) do
    if should_log?(:streaming) do
      metadata =
        [
          component: :streaming,
          provider: provider,
          event: event
        ] ++ Enum.into(data, [])

      debug("Stream event", metadata)
    end
  end

  @doc """
  Log a retry attempt.
  """
  def log_retry(provider, attempt, max_attempts, reason, delay_ms) do
    if should_log?(:retries) do
      metadata = [
        component: :retry,
        provider: provider,
        attempt: attempt,
        max_attempts: max_attempts,
        reason: inspect(reason),
        delay_ms: delay_ms
      ]

      level = if attempt == max_attempts, do: :warn, else: :info
      log(level, "Retry attempt #{attempt}/#{max_attempts}", metadata)
    end
  end

  @doc """
  Log a cache event.
  """
  def log_cache_event(event, key, data \\ %{}) do
    if should_log?(:cache) do
      metadata =
        [
          component: :cache,
          event: event,
          key: truncate_string(key, 50)
        ] ++ Enum.into(data, [])

      debug("Cache #{event}", metadata)
    end
  end

  @doc """
  Log a model event.
  """
  def log_model_event(provider, event, data \\ %{}) do
    if should_log?(:models) do
      metadata =
        [
          component: :models,
          provider: provider,
          event: event
        ] ++ Enum.into(data, [])

      info("Model #{event}", metadata)
    end
  end

  # Private implementation

  @doc """
  Log a message at the specified level.

  Compatible with Elixir's Logger.log/3 function.
  """
  @spec log(atom(), String.t(), keyword()) :: :ok
  def log(level, message, metadata \\ []) do
    if should_emit_log?(level) do
      # Get current context
      context = Process.get(@context_key, %{})

      # Merge context with metadata
      # Tag for filtering
      final_metadata =
        Enum.into(context, []) ++
          metadata ++
          [ex_llm: true]

      # Use Erlang's logger directly to avoid Dialyzer issues
      erlang_level = elixir_level_to_erlang(level)
      :logger.log(erlang_level, message, Map.new(final_metadata))
    end
  end

  defp should_emit_log?(level) do
    configured_level = Application.get_env(:ex_llm, :log_level, :info)
    level_value(level) >= level_value(configured_level)
  end

  defp should_log?(component) do
    components = Application.get_env(:ex_llm, :log_components, %{})
    Map.get(components, component, true)
  end

  defp level_value(:debug), do: 0
  defp level_value(:info), do: 1
  defp level_value(:warn), do: 2
  defp level_value(:warning), do: 2
  defp level_value(:error), do: 3
  defp level_value(:none), do: 4
  defp level_value(_), do: 1

  defp elixir_level_to_erlang(:debug), do: :debug
  defp elixir_level_to_erlang(:info), do: :info
  defp elixir_level_to_erlang(:warning), do: :warning
  defp elixir_level_to_erlang(:warn), do: :warning
  defp elixir_level_to_erlang(:error), do: :error

  # Redaction functions

  defp redact_url(url) do
    if should_redact?(:api_keys) do
      url
      |> String.replace(~r/api_key=[^&]+/, "api_key=***")
      |> String.replace(~r/key=[^&]+/, "key=***")
    else
      url
    end
  end

  defp redact_body(body) do
    if should_redact?(:content) do
      case body do
        %{"messages" => messages} = map ->
          %{map | "messages" => "[#{length(messages)} messages]"}

        %{"prompt" => _} = map ->
          %{map | "prompt" => "[redacted]"}

        _ ->
          body
      end
    else
      body
    end
  end

  defp redact_headers(headers) do
    if should_redact?(:api_keys) do
      Enum.map(headers, fn
        {"Authorization", _} -> {"Authorization", "***"}
        {"x-api-key", _} -> {"x-api-key", "***"}
        {"api-key", _} -> {"api-key", "***"}
        {k, v} -> {k, v}
      end)
    else
      headers
    end
  end

  defp should_redact?(type) do
    redaction = Application.get_env(:ex_llm, :log_redaction, %{})
    Map.get(redaction, type, true)
  end

  # Helper functions

  defp get_status(%{status: status}), do: status
  defp get_status(_), do: nil

  defp get_usage(%{usage: usage}), do: usage
  defp get_usage(_), do: nil

  defp get_model(%{model: model}), do: model
  defp get_model(_), do: nil

  defp truncate_string(str, max_length) when is_binary(str) do
    if String.length(str) > max_length do
      String.slice(str, 0, max_length) <> "..."
    else
      str
    end
  end

  defp truncate_string(other, _), do: inspect(other)
end
