# Telemetry Migration Example

This document shows how to add telemetry instrumentation to existing ExLLM code.

## Example: Instrumenting the Main ExLLM Module

Here's how to add telemetry to the main `ExLLM.chat/3` function:

### Before (No Telemetry)

```elixir
defmodule ExLLM do
  def chat(model_or_config, messages, opts \\ []) do
    with {:ok, config} <- build_config(model_or_config, opts),
         {:ok, adapter} <- get_adapter(config.provider),
         {:ok, formatted_messages} <- format_messages(messages, adapter),
         {:ok, response} <- call_with_retry(adapter, config, formatted_messages, opts) do
      
      if Keyword.get(opts, :session) do
        update_session(opts[:session], formatted_messages, response)
      end
      
      {:ok, response}
    end
  end
end
```

### After (With Telemetry)

```elixir
defmodule ExLLM do
  import ExLLM.Telemetry.Instrumentation
  
  def chat(model_or_config, messages, opts \\ []) do
    # Extract metadata for telemetry
    metadata = build_telemetry_metadata(model_or_config, opts)
    
    instrument [:ex_llm, :chat, :call], metadata do
      with {:ok, config} <- build_config(model_or_config, opts),
           {:ok, adapter} <- get_adapter(config.provider),
           {:ok, formatted_messages} <- format_messages(messages, adapter),
           {:ok, response} <- call_with_retry(adapter, config, formatted_messages, opts) do
        
        # Emit session telemetry if applicable
        if session = Keyword.get(opts, :session) do
          instrument_session_update(session, formatted_messages, response)
        end
        
        # The instrument macro will automatically add usage data to telemetry
        {:ok, response}
      end
    end
  end
  
  defp build_telemetry_metadata(model_or_config, opts) do
    %{
      model: extract_model_name(model_or_config),
      provider: extract_provider(model_or_config),
      stream: Keyword.get(opts, :stream, false),
      session: not is_nil(Keyword.get(opts, :session)),
      circuit_breaker: Keyword.get(opts, :circuit_breaker, true)
    }
  end
  
  defp instrument_session_update(session, messages, response) do
    if usage = response[:usage] do
      ExLLM.Telemetry.Instrumentation.instrument_session_add_message(
        session.id,
        List.last(messages),
        usage.total_tokens
      )
    end
  end
end
```

## Example: Instrumenting HTTP Client

### Before

```elixir
defmodule ExLLM.Adapters.Shared.HTTPClient do
  def post_json(url, json_body, headers, opts \\ []) do
    body = Jason.encode!(json_body)
    
    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"} | headers
    ]
    
    request_opts = build_request_opts(opts)
    
    case HTTPoison.post(url, body, headers, request_opts) do
      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} when status in 200..299 ->
        Jason.decode(response_body, keys: :atoms)
        
      {:ok, %HTTPoison.Response{} = response} ->
        handle_error_response(response)
        
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_error, reason}}
    end
  end
end
```

### After

```elixir
defmodule ExLLM.Adapters.Shared.HTTPClient do
  import ExLLM.Telemetry.Instrumentation
  
  def post_json(url, json_body, headers, opts \\ []) do
    instrument_http :post, url, opts do
      body = Jason.encode!(json_body)
      
      headers = [
        {"content-type", "application/json"},
        {"accept", "application/json"} | headers
      ]
      
      request_opts = build_request_opts(opts)
      
      case HTTPoison.post(url, body, headers, request_opts) do
        {:ok, %HTTPoison.Response{status_code: status, body: response_body} = response} when status in 200..299 ->
          {:ok, %{status: status, body: response_body, response: Jason.decode!(response_body, keys: :atoms)}}
          
        {:ok, %HTTPoison.Response{} = response} ->
          handle_error_response(response)
          
        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, {:http_error, reason}}
      end
    end
  end
end
```

## Example: Instrumenting Provider Adapters

### Before

```elixir
defmodule ExLLM.Adapters.OpenAI do
  def call(model, messages, opts) do
    api_key = Keyword.get(opts, :api_key) || get_api_key()
    
    request_body = build_request_body(model, messages, opts)
    headers = build_headers(api_key)
    
    case HTTPClient.post_json(@api_url, request_body, headers) do
      {:ok, response} ->
        format_response(response)
      error ->
        error
    end
  end
end
```

### After

```elixir
defmodule ExLLM.Adapters.OpenAI do
  import ExLLM.Telemetry.Instrumentation
  
  def call(model, messages, opts) do
    instrument_provider :openai, model, opts do
      api_key = Keyword.get(opts, :api_key) || get_api_key()
      
      request_body = build_request_body(model, messages, opts)
      headers = build_headers(api_key)
      
      case HTTPClient.post_json(@api_url, request_body, headers) do
        {:ok, response} ->
          format_response(response)
        error ->
          error
      end
    end
  end
end
```

## Example: Instrumenting Cache Operations

### Before

```elixir
defmodule ExLLM.Cache do
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expiry}] ->
        if DateTime.compare(DateTime.utc_now(), expiry) == :lt do
          {:ok, value}
        else
          :ets.delete(@table, key)
          :error
        end
      [] ->
        :error
    end
  end
  
  def put(key, value, ttl) do
    expiry = DateTime.add(DateTime.utc_now(), ttl, :second)
    :ets.insert(@table, {key, value, expiry})
    :ok
  end
end
```

### After

```elixir
defmodule ExLLM.Cache do
  import ExLLM.Telemetry.Instrumentation
  
  def get(key) do
    instrument_cache_lookup key, fn ->
      case :ets.lookup(@table, key) do
        [{^key, value, expiry}] ->
          if DateTime.compare(DateTime.utc_now(), expiry) == :lt do
            {:ok, value}
          else
            :ets.delete(@table, key)
            :telemetry.execute([:ex_llm, :cache, :ttl, :expired], %{}, %{key: key})
            :error
          end
        [] ->
          :error
      end
    end
  end
  
  def put(key, value, ttl) do
    instrument_cache_store key, value, ttl, fn ->
      expiry = DateTime.add(DateTime.utc_now(), ttl, :second)
      :ets.insert(@table, {key, value, expiry})
      :ok
    end
  end
end
```

## Example: Instrumenting Context Management

### Before

```elixir
defmodule ExLLM.Context do
  def ensure_fits(messages, model_config, strategy) do
    total_tokens = calculate_tokens(messages, model_config)
    
    if total_tokens <= model_config.max_tokens do
      {:ok, messages}
    else
      truncated = apply_truncation_strategy(messages, model_config, strategy)
      {:ok, truncated}
    end
  end
end
```

### After

```elixir
defmodule ExLLM.Context do
  import ExLLM.Telemetry.Instrumentation
  
  def ensure_fits(messages, model_config, strategy) do
    instrument [:ex_llm, :context, :truncation], %{strategy: strategy} do
      total_tokens = calculate_tokens(messages, model_config)
      
      if total_tokens <= model_config.max_tokens do
        {:ok, messages}
      else
        # Emit window exceeded event
        :telemetry.execute(
          [:ex_llm, :context, :window, :exceeded],
          %{},
          %{
            tokens: total_tokens,
            max_tokens: model_config.max_tokens,
            exceeded_by: total_tokens - model_config.max_tokens
          }
        )
        
        messages_before = length(messages)
        truncated = apply_truncation_strategy(messages, model_config, strategy)
        messages_after = length(truncated)
        tokens_after = calculate_tokens(truncated, model_config)
        
        # Emit truncation metrics
        instrument_context_truncation(
          messages_before,
          messages_after,
          total_tokens - tokens_after
        )
        
        {:ok, truncated}
      end
    end
  end
end
```

## Setting Up Telemetry Handlers

Add to your application startup:

```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    # Attach ExLLM telemetry handlers
    ExLLM.Telemetry.attach_default_handlers()
    
    # Attach custom handlers
    :telemetry.attach_many(
      "myapp-llm-handler",
      [
        [:ex_llm, :chat, :call, :stop],
        [:ex_llm, :provider, :request, :stop],
        [:ex_llm, :cost, :threshold, :exceeded]
      ],
      &MyApp.Telemetry.handle_llm_event/4,
      nil
    )
    
    # Start your supervision tree
    Supervisor.start_link(children, opts)
  end
end
```

## Custom Handler Example

```elixir
defmodule MyApp.Telemetry do
  require Logger
  
  def handle_llm_event([:ex_llm, :chat, :call, :stop], measurements, metadata, _config) do
    # Log response times
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.info("LLM chat completed in #{duration_ms}ms for model #{metadata.model}")
    
    # Send to monitoring system
    StatsD.timing("llm.chat.duration", duration_ms, tags: ["model:#{metadata.model}"])
    
    # Track token usage
    if tokens = metadata[:tokens] do
      StatsD.gauge("llm.tokens.used", tokens, tags: ["model:#{metadata.model}"])
    end
  end
  
  def handle_llm_event([:ex_llm, :cost, :threshold, :exceeded], measurements, metadata, _config) do
    # Alert on cost overruns
    Logger.warning("LLM cost threshold exceeded! Cost: $#{measurements.cost / 100}")
    
    # Could send alerts via email/Slack/PagerDuty
    AlertManager.send_cost_alert(measurements.cost, metadata.threshold)
  end
  
  def handle_llm_event([:ex_llm, :provider, :request, :stop], measurements, metadata, _config) do
    # Track provider-specific metrics
    if metadata.success do
      StatsD.increment("llm.provider.success", tags: ["provider:#{metadata.provider}"])
    else
      StatsD.increment("llm.provider.failure", tags: ["provider:#{metadata.provider}"])
    end
  end
end
```

## Dashboard Integration

Use the telemetry data for monitoring dashboards:

```elixir
defmodule MyApp.LLMDashboard do
  def get_metrics do
    # Get aggregated metrics
    all_metrics = ExLLM.Telemetry.get_metrics()
    
    # Get specific dashboard data
    dashboard = ExLLM.Telemetry.dashboard_data(time_window: 3_600_000)  # 1 hour
    
    # Format for your dashboard tool (Grafana, DataDog, etc.)
    %{
      summary: %{
        total_calls: dashboard.components.chat.total_calls,
        avg_response_time: dashboard.components.chat.avg_duration_ms,
        cache_hit_rate: dashboard.components.cache.hit_rate,
        total_cost: dashboard.components.costs.total / 100  # Convert to dollars
      },
      providers: dashboard.components.providers,
      alerts: dashboard.alerts
    }
  end
end
```

## Benefits of Telemetry

1. **Performance Monitoring**: Track response times, throughput, and bottlenecks
2. **Cost Management**: Monitor API costs and set alerts for budget overruns
3. **Error Tracking**: Identify error patterns and provider-specific issues
4. **Cache Efficiency**: Optimize cache configuration based on hit rates
5. **Capacity Planning**: Understand usage patterns and resource needs
6. **SLA Monitoring**: Track availability and response times against targets
7. **Debugging**: Detailed traces for troubleshooting issues