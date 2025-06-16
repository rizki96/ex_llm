# ExLLM Observability Guide

This guide covers the observability features in ExLLM, including telemetry events, metrics collection, and distributed tracing.

## Architecture Overview

ExLLM's observability is built on three layers:

1. **Core Telemetry Events** - Decoupled event emission using Elixir's `:telemetry`
2. **Metrics Collection** - Aggregation using `telemetry_metrics` 
3. **Distributed Tracing** - Optional OpenTelemetry integration

## Quick Start

### Basic Logging

Attach the default logger to see all events:

```elixir
# In your application start
ExLLM.Telemetry.attach_default_logger(:info)
```

### Metrics with Prometheus

1. Add dependencies:
```elixir
{:telemetry_metrics, "~> 0.6"},
{:telemetry_metrics_prometheus, "~> 1.0"}
```

2. Add to supervision tree:
```elixir
children = [
  {TelemetryMetricsPrometheus, 
    metrics: ExLLM.Telemetry.Metrics.metrics(),
    port: 9568}
]
```

3. Access metrics at http://localhost:9568/metrics

### Distributed Tracing with OpenTelemetry

1. Add dependencies:
```elixir
{:opentelemetry_api, "~> 1.2"},
{:opentelemetry, "~> 1.3"},
{:opentelemetry_exporter, "~> 1.6"}
```

2. Use instrumented functions:
```elixir
# Instead of ExLLM.chat(...)
ExLLM.Telemetry.OpenTelemetry.chat(model: "gpt-4", messages: messages)
```

## Telemetry Events

### Event Naming Convention

All events follow the pattern: `[:ex_llm, :component, :operation, :phase]`

Where:
- `component`: The module (e.g., `:chat`, `:provider`, `:cache`)
- `operation`: The specific operation (e.g., `:request`, `:truncation`)
- `phase`: Either `:start`, `:stop`, or `:exception`

### Core Events

#### Chat Operations
- `[:ex_llm, :chat, :start]` - Chat request started
- `[:ex_llm, :chat, :stop]` - Chat request completed
- `[:ex_llm, :chat, :exception]` - Chat request failed

Measurements:
- `duration` - Time in native units (use `System.convert_time_unit/3`)

Metadata:
- `provider` - The LLM provider
- `model` - The model used
- `input_tokens` - Tokens in the request
- `output_tokens` - Tokens in the response
- `total_tokens` - Total token count
- `cost_cents` - Cost in cents

#### Provider Operations
- `[:ex_llm, :provider, :request, :start/stop/exception]`
- `[:ex_llm, :provider, :auth, :refresh]`
- `[:ex_llm, :provider, :rate_limit]`

#### Cache Operations
- `[:ex_llm, :cache, :hit]` - Cache hit
- `[:ex_llm, :cache, :miss]` - Cache miss
- `[:ex_llm, :cache, :put]` - Item cached
- `[:ex_llm, :cache, :evicted]` - Item evicted

#### Cost Tracking
- `[:ex_llm, :cost, :calculated]` - Cost calculated
- `[:ex_llm, :cost, :threshold_exceeded]` - Cost threshold exceeded

### Custom Event Handlers

```elixir
:telemetry.attach(
  "my-handler",
  [:ex_llm, :chat, :stop],
  &MyApp.handle_chat_complete/4,
  nil
)

def handle_chat_complete(_event_name, measurements, metadata, _config) do
  duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
  Logger.info("Chat completed in #{duration_ms}ms", metadata)
  
  # Send to your metrics system
  StatsD.timing("llm.chat.duration", duration_ms, tags: ["model:#{metadata.model}"])
end
```

## Metrics Collection

### Using telemetry_metrics

ExLLM provides pre-defined metrics that work with any `telemetry_metrics` reporter:

```elixir
# Get all metrics
ExLLM.Telemetry.Metrics.metrics()

# Get basic metrics for development
ExLLM.Telemetry.Metrics.basic_metrics()

# Get cost-focused metrics
ExLLM.Telemetry.Metrics.cost_metrics()
```

### Available Metrics

- **Request Metrics**
  - `ex_llm.chat.requests.total` - Total chat requests
  - `ex_llm.chat.duration.milliseconds` - Request duration
  - `ex_llm.chat.errors.total` - Error count

- **Token Metrics**
  - `ex_llm.tokens.input.total` - Total input tokens
  - `ex_llm.tokens.output.total` - Total output tokens

- **Cost Metrics**
  - `ex_llm.cost.cents.total` - Total cost
  - `ex_llm.cost.threshold_exceeded.total` - Threshold violations

- **Cache Metrics**
  - `ex_llm.cache.hits.total` - Cache hits
  - `ex_llm.cache.misses.total` - Cache misses
  - `ex_llm.cache.size.bytes` - Cache size

### Reporter Examples

#### Console Reporter (Development)
```elixir
{Telemetry.Metrics.ConsoleReporter,
  metrics: ExLLM.Telemetry.Metrics.basic_metrics()}
```

#### StatsD Reporter
```elixir
{TelemetryMetricsStatsd,
  metrics: ExLLM.Telemetry.Metrics.metrics(),
  host: "localhost",
  port: 8125}
```

#### Custom Reporter
```elixir
defmodule MyReporter do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  def init(opts) do
    metrics = Keyword.fetch!(opts, :metrics)
    groups = Enum.group_by(metrics, & &1.event_name)
    
    for {event, metrics} <- groups do
      :telemetry.attach(
        {__MODULE__, event, self()},
        event,
        &__MODULE__.handle_event/4,
        {self(), metrics}
      )
    end
    
    {:ok, %{}}
  end
  
  def handle_event(_event_name, measurements, metadata, {pid, metrics}) do
    # Process metrics and send to your backend
  end
end
```

## Distributed Tracing

### OpenTelemetry Integration

The OpenTelemetry integration provides:
- Automatic span creation
- Context propagation across processes
- Integration with APM tools

#### Direct Instrumentation

Use the instrumented functions for best performance:

```elixir
# These create proper OpenTelemetry spans
ExLLM.Telemetry.OpenTelemetry.chat(model: "gpt-4", messages: messages)
ExLLM.Telemetry.OpenTelemetry.stream_chat(model: "gpt-4", messages: messages)
ExLLM.Telemetry.OpenTelemetry.embed(model: "text-embedding-ada-002", input: text)
```

#### Manual Instrumentation

For custom operations:

```elixir
import ExLLM.Telemetry.OpenTelemetry

with_span "custom_operation", %{custom: "attribute"} do
  # Your code here
  result = ExLLM.chat(...)
  # Span automatically ended
  result
end
```

#### Context Propagation

When spawning async tasks:

```elixir
# In a traced function
otel_ctx = OpenTelemetry.Ctx.get_current()

Task.async(fn ->
  # Maintain trace context in the new process
  ExLLM.Telemetry.OpenTelemetry.with_context(otel_ctx, fn ->
    ExLLM.chat(...)  # This will be part of the same trace
  end)
end)
```

### Configuration

Configure OpenTelemetry in your runtime.exs:

```elixir
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: "http://localhost:4318"
```

### Integration with APM Tools

#### Jaeger
```elixir
config :opentelemetry_exporter,
  otlp_endpoint: "http://localhost:14268/api/traces"
```

#### Honeycomb
```elixir
config :opentelemetry_exporter,
  otlp_endpoint: "https://api.honeycomb.io:443",
  otlp_headers: [{"x-honeycomb-team", System.get_env("HONEYCOMB_API_KEY")}]
```

#### DataDog
```elixir
config :opentelemetry_exporter,
  otlp_endpoint: "http://localhost:4318",
  otlp_headers: [{"DD_API_KEY", System.get_env("DD_API_KEY")}]
```

## Instrumentation Patterns

### Adding Telemetry to Your Code

Use the `ExLLM.Telemetry.span/3` helper:

```elixir
defmodule MyApp.LLMService do
  def analyze_text(text) do
    metadata = %{
      operation: "analyze_text",
      text_length: String.length(text)
    }
    
    ExLLM.Telemetry.span [:myapp, :llm, :analyze], metadata do
      # This automatically emits start/stop/exception events
      ExLLM.chat(
        model: "gpt-4",
        messages: [%{role: "user", content: text}]
      )
    end
  end
end
```

### Cache Instrumentation

```elixir
def get_from_cache(key) do
  case Cache.get(key) do
    {:ok, value} ->
      ExLLM.Telemetry.emit_cache_hit(key)
      {:ok, value}
      
    :error ->
      ExLLM.Telemetry.emit_cache_miss(key)
      :error
  end
end
```

### Cost Monitoring

```elixir
def track_cost(response, threshold) do
  if cost = get_in(response, [:cost, :total_cents]) do
    ExLLM.Telemetry.emit_cost_calculated(
      response.provider,
      response.model,
      cost
    )
    
    if cost > threshold do
      ExLLM.Telemetry.emit_cost_threshold_exceeded(cost, threshold)
    end
  end
end
```

## Performance Considerations

1. **Event Emission**: Telemetry events are synchronous but very fast (microseconds)
2. **Sampling**: For high-volume operations, consider sampling
3. **Async Handlers**: Keep telemetry handlers fast or make them async
4. **Metric Aggregation**: Use `telemetry_metrics` reporters for efficient aggregation

## Debugging Tips

1. **Enable Debug Logging**:
   ```elixir
   ExLLM.Telemetry.attach_default_logger(:debug)
   ```

2. **List Attached Handlers**:
   ```elixir
   :telemetry.list_handlers([:ex_llm, :chat, :stop])
   ```

3. **Test Events Manually**:
   ```elixir
   :telemetry.execute(
     [:ex_llm, :chat, :stop],
     %{duration: 1000},
     %{model: "gpt-4", provider: :openai}
   )
   ```

## Security Considerations

1. **Sensitive Data**: Don't include sensitive data in telemetry metadata
2. **PII**: Avoid logging personally identifiable information
3. **API Keys**: Never include API keys in events
4. **Sampling**: Consider sampling for cost-sensitive operations

## Migration from Custom Metrics

If you're migrating from a custom metrics solution:

1. Replace custom counters with telemetry events
2. Use `telemetry_metrics` for aggregation
3. Update dashboards to use new metric names
4. Run both systems in parallel during migration