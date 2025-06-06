defmodule ExLLM.DebugLogger do
  @moduledoc """
  Centralized debug logging for ExLLM.
  
  Provides configurable logging levels and structured logging for different
  components of the library. This helps with debugging while keeping
  production logs clean.
  
  ## Configuration
  
      config :ex_llm,
        debug_level: :info,  # :debug, :info, :warn, :error, :none
        log_requests: true,
        log_responses: true,
        log_streaming: false,
        log_retries: true,
        redact_api_keys: true,
        redact_content: false
  
  ## Usage
  
      alias ExLLM.DebugLogger
      
      DebugLogger.log_request(:openai, url, body)
      DebugLogger.log_response(:openai, response, duration_ms)
      DebugLogger.log_error(:anthropic, error, context)
  """
  
  require Logger
  
  @log_levels [:debug, :info, :warn, :error, :none]
  
  @doc """
  Log an outgoing API request.
  """
  def log_request(provider, url, body, headers \\ []) do
    if should_log?(:requests) do
      level = get_log_level()
      
      log_data = %{
        event: "api_request",
        provider: provider,
        url: redact_url(url),
        method: "POST",
        body: redact_body(body),
        headers: redact_headers(headers)
      }
      
      log(level, "ExLLM API Request", log_data)
    end
  end
  
  @doc """
  Log an API response.
  """
  def log_response(provider, response, duration_ms) do
    if should_log?(:responses) do
      level = get_log_level()
      
      log_data = %{
        event: "api_response",
        provider: provider,
        duration_ms: duration_ms,
        status: get_status(response),
        usage: get_usage(response),
        model: get_model(response)
      }
      
      # Add response preview if in debug mode
      if level == :debug do
        log_data = Map.put(log_data, :preview, get_preview(response))
      end
      
      log(level, "ExLLM API Response", log_data)
    end
  end
  
  @doc """
  Log streaming events.
  """
  def log_stream_event(provider, event, data \\ %{}) do
    if should_log?(:streaming) do
      log_data = Map.merge(%{
        event: "stream_#{event}",
        provider: provider
      }, data)
      
      log(:debug, "ExLLM Stream Event", log_data)
    end
  end
  
  @doc """
  Log retry attempts.
  """
  def log_retry(provider, attempt, max_attempts, reason, delay_ms) do
    if should_log?(:retries) do
      log_data = %{
        event: "retry_attempt",
        provider: provider,
        attempt: attempt,
        max_attempts: max_attempts,
        reason: inspect(reason),
        delay_ms: delay_ms
      }
      
      level = if attempt == max_attempts, do: :warn, else: :info
      log(level, "ExLLM Retry Attempt", log_data)
    end
  end
  
  @doc """
  Log errors with context.
  """
  def log_error(provider, error, context \\ %{}) do
    log_data = Map.merge(%{
      event: "error",
      provider: provider,
      error: inspect(error)
    }, context)
    
    log(:error, "ExLLM Error", log_data)
  end
  
  @doc """
  Log cache events.
  """
  def log_cache_event(event, key, data \\ %{}) do
    if should_log?(:cache) do
      log_data = Map.merge(%{
        event: "cache_#{event}",
        key: truncate_string(key, 50)
      }, data)
      
      log(:debug, "ExLLM Cache", log_data)
    end
  end
  
  @doc """
  Log model loading events.
  """
  def log_model_event(provider, event, data \\ %{}) do
    if should_log?(:models) do
      log_data = Map.merge(%{
        event: "model_#{event}",
        provider: provider
      }, data)
      
      log(:info, "ExLLM Model", log_data)
    end
  end
  
  @doc """
  Check if debug logging is enabled for a specific component.
  """
  def enabled?(component \\ :general) do
    level = get_log_level()
    level != :none && should_log?(component)
  end
  
  # Private functions
  
  defp log(level, message, metadata) do
    if should_emit_log?(level) do
      # Format metadata for better readability
      meta_string = format_metadata(metadata)
      
      case level do
        :debug -> Logger.debug("#{message} #{meta_string}")
        :info -> Logger.info("#{message} #{meta_string}")
        :warn -> Logger.warning("#{message} #{meta_string}")
        :error -> Logger.error("#{message} #{meta_string}")
        _ -> :ok
      end
    end
  end
  
  defp get_log_level do
    Application.get_env(:ex_llm, :debug_level, :info)
  end
  
  defp should_log?(component) do
    case component do
      :requests -> Application.get_env(:ex_llm, :log_requests, true)
      :responses -> Application.get_env(:ex_llm, :log_responses, true)
      :streaming -> Application.get_env(:ex_llm, :log_streaming, false)
      :retries -> Application.get_env(:ex_llm, :log_retries, true)
      :cache -> Application.get_env(:ex_llm, :log_cache, false)
      :models -> Application.get_env(:ex_llm, :log_models, true)
      _ -> true
    end
  end
  
  defp should_emit_log?(level) do
    configured_level = get_log_level()
    level_value(level) >= level_value(configured_level)
  end
  
  defp level_value(:debug), do: 0
  defp level_value(:info), do: 1
  defp level_value(:warn), do: 2
  defp level_value(:error), do: 3
  defp level_value(:none), do: 4
  defp level_value(_), do: 1
  
  defp format_metadata(metadata) do
    metadata
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
    |> Enum.join(" ")
    |> then(&"[#{&1}]")
  end
  
  defp redact_url(url) do
    if Application.get_env(:ex_llm, :redact_api_keys, true) do
      url
      |> String.replace(~r/api_key=[^&]+/, "api_key=***")
      |> String.replace(~r/key=[^&]+/, "key=***")
    else
      url
    end
  end
  
  defp redact_body(body) do
    if Application.get_env(:ex_llm, :redact_content, false) do
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
    if Application.get_env(:ex_llm, :redact_api_keys, true) do
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
  
  defp get_status(%{status: status}), do: status
  defp get_status(_), do: nil
  
  defp get_usage(%{usage: usage}), do: usage
  defp get_usage(_), do: nil
  
  defp get_model(%{model: model}), do: model
  defp get_model(_), do: nil
  
  defp get_preview(%{content: content}) when is_binary(content) do
    truncate_string(content, 100)
  end
  defp get_preview(_), do: nil
  
  defp truncate_string(str, max_length) when is_binary(str) do
    if String.length(str) > max_length do
      String.slice(str, 0, max_length) <> "..."
    else
      str
    end
  end
  defp truncate_string(other, _), do: inspect(other)
  
  @doc """
  Create a debug context for a request.
  
  This can be used to track requests across multiple log entries.
  """
  def create_context(provider, operation) do
    %{
      request_id: generate_request_id(),
      provider: provider,
      operation: operation,
      started_at: System.monotonic_time(:millisecond)
    }
  end
  
  @doc """
  Log with a context.
  """
  def log_with_context(level, message, context, additional_data \\ %{}) do
    duration = if context[:started_at] do
      System.monotonic_time(:millisecond) - context[:started_at]
    else
      nil
    end
    
    log_data = context
    |> Map.merge(additional_data)
    |> Map.put(:duration_ms, duration)
    |> Map.delete(:started_at)
    
    log(level, message, log_data)
  end
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end
end