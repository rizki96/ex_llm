# Streaming Metrics Guide

The ExLLM streaming infrastructure includes a dedicated metrics middleware (`MetricsPlug`) that provides comprehensive performance monitoring and reporting capabilities for streaming operations.

## Overview

The `MetricsPlug` middleware separates metrics collection from core streaming logic, providing:

- **Real-time performance tracking** - Monitor bytes, chunks, timing, and throughput
- **Error monitoring** - Track streaming errors and recovery attempts  
- **Configurable callbacks** - Integrate with your monitoring systems
- **Zero overhead when disabled** - No performance impact when not needed
- **Provider-aware metrics** - Compare performance across different LLM providers

## Basic Usage

### Enabling Metrics

```elixir
# Create a streaming client with metrics enabled
client = ExLLM.Providers.Shared.Streaming.Engine.client(
  provider: :openai,
  api_key: "sk-...",
  enable_metrics: true,
  metrics_callback: &handle_metrics/1
)

# Start streaming
{:ok, stream_id} = Engine.stream(
  client,
  "/chat/completions", 
  request_body,
  callback: &handle_chunk/1,
  parse_chunk: &parse_chunk/1
)
```

### Handling Metrics

```elixir
def handle_metrics(metrics) do
  IO.inspect(metrics, label: "Streaming Metrics")
  
  # Send to monitoring system
  Telemetry.execute(
    [:ex_llm, :streaming, :metrics],
    %{
      bytes_received: metrics.bytes_received,
      chunks_received: metrics.chunks_received,
      duration_ms: metrics.duration_ms
    },
    %{
      provider: metrics.provider,
      stream_id: metrics.stream_id,
      status: metrics.status
    }
  )
end
```

## Configuration Options

### Client Options

When creating a streaming client:

```elixir
Engine.client(
  # Core options
  provider: :openai,
  api_key: "sk-...",
  
  # Metrics options
  enable_metrics: true,              # Enable metrics collection
  metrics_callback: &my_callback/1,  # Function to receive metrics
  metrics_interval: 1000,            # Reporting interval in ms (default: 1000)
  include_raw_chunks: false          # Include raw chunk data (default: false)
)
```

### Runtime Options

Override metrics configuration per request:

```elixir
Engine.stream(
  client,
  path,
  body,
  # Override metrics settings for this request
  opts: [
    enabled: true,
    callback: &special_metrics_handler/1,
    interval: 500,
    include_raw_data: true
  ]
)
```

## Metrics Structure

The metrics callback receives a map with the following structure:

```elixir
%{
  # Identification
  stream_id: "stream_123_456789",
  provider: :openai,
  
  # Timing
  start_time: 1234567890,      # Unix timestamp in ms
  current_time: 1234567900,    # Unix timestamp in ms  
  duration_ms: 10000,          # Total duration
  
  # Data volume
  bytes_received: 45678,       # Total bytes
  chunks_received: 123,        # Total chunks
  
  # Throughput
  bytes_per_second: 4567.8,    # Calculated rate
  chunks_per_second: 12.3,     # Calculated rate
  avg_chunk_size: 371.4,       # Average bytes per chunk
  
  # Errors
  error_count: 0,              # Number of errors
  last_error: nil,             # Last error details
  
  # Status
  status: :streaming,          # :streaming | :completed | :error
  
  # Optional
  raw_chunks: [...]            # If include_raw_data is true
}
```

## Usage Patterns

### Periodic Progress Updates

Monitor long-running streams with periodic updates:

```elixir
client = Engine.client(
  provider: :openai,
  api_key: api_key,
  enable_metrics: true,
  metrics_interval: 1000,  # Report every second
  metrics_callback: fn metrics ->
    if metrics.status == :streaming do
      IO.puts("Progress: #{metrics.chunks_received} chunks received")
    end
  end
)
```

### Performance Monitoring

Track streaming performance across providers:

```elixir
defmodule StreamingMonitor do
  use GenServer
  
  def handle_metrics(metrics) do
    GenServer.cast(__MODULE__, {:metrics, metrics})
  end
  
  def handle_cast({:metrics, metrics}, state) do
    # Store metrics by provider
    provider_metrics = Map.get(state, metrics.provider, [])
    updated = Map.put(state, metrics.provider, [metrics | provider_metrics])
    
    # Log performance issues
    if metrics.bytes_per_second < 1000 do
      Logger.warning("Slow streaming detected for #{metrics.provider}")
    end
    
    {:noreply, updated}
  end
end
```

### Error Detection

Monitor for streaming errors:

```elixir
metrics_callback = fn metrics ->
  case metrics.status do
    :error ->
      Logger.error("Stream failed: #{inspect(metrics.last_error)}")
      # Trigger alerts
      
    :completed when metrics.error_count > 0 ->
      Logger.warning("Stream completed with #{metrics.error_count} errors")
      
    _ ->
      :ok
  end
end
```

### Detailed Analysis

Collect raw chunks for analysis:

```elixir
client = Engine.client(
  provider: :anthropic,
  api_key: api_key,
  enable_metrics: true,
  include_raw_chunks: true,
  metrics_callback: fn metrics ->
    if metrics.status == :completed && metrics[:raw_chunks] do
      # Analyze chunk patterns
      chunk_sizes = Enum.map(metrics.raw_chunks, fn chunk ->
        byte_size(chunk.content || "")
      end)
      
      IO.puts("Chunk distribution:")
      IO.puts("  Count: #{length(chunk_sizes)}")
      IO.puts("  Min: #{Enum.min(chunk_sizes)} bytes")
      IO.puts("  Max: #{Enum.max(chunk_sizes)} bytes")
      IO.puts("  Std Dev: #{calculate_std_dev(chunk_sizes)}")
    end
  end
)
```

## Integration Examples

### With Telemetry

```elixir
defmodule MyApp.StreamingTelemetry do
  def attach_handlers do
    :telemetry.attach_many(
      "streaming-metrics",
      [
        [:ex_llm, :streaming, :start],
        [:ex_llm, :streaming, :complete],
        [:ex_llm, :streaming, :error]
      ],
      &handle_event/4,
      nil
    )
  end
  
  def emit_from_metrics(metrics) do
    measurements = %{
      duration_ms: metrics.duration_ms,
      bytes_received: metrics.bytes_received,
      chunks_received: metrics.chunks_received,
      bytes_per_second: metrics.bytes_per_second
    }
    
    metadata = %{
      stream_id: metrics.stream_id,
      provider: metrics.provider,
      status: metrics.status,
      error_count: metrics.error_count
    }
    
    event = case metrics.status do
      :streaming -> [:ex_llm, :streaming, :progress]
      :completed -> [:ex_llm, :streaming, :complete]
      :error -> [:ex_llm, :streaming, :error]
    end
    
    :telemetry.execute(event, measurements, metadata)
  end
end
```

### With Phoenix LiveView

```elixir
defmodule MyAppWeb.StreamingLive do
  use MyAppWeb, :live_view
  
  def mount(_params, _session, socket) do
    {:ok, assign(socket, streaming_metrics: %{})}
  end
  
  def handle_info({:streaming_metrics, metrics}, socket) do
    {:noreply, assign(socket, streaming_metrics: metrics)}
  end
  
  def render(assigns) do
    ~H"""
    <div class="streaming-status">
      <h3>Streaming Status</h3>
      <%= if @streaming_metrics[:status] == :streaming do %>
        <div class="progress">
          <p>Chunks: <%= @streaming_metrics[:chunks_received] %></p>
          <p>Speed: <%= @streaming_metrics[:chunks_per_second] %> chunks/sec</p>
          <p>Data: <%= format_bytes(@streaming_metrics[:bytes_received]) %></p>
        </div>
      <% end %>
    </div>
    """
  end
  
  defp stream_with_metrics(socket) do
    client = Engine.client(
      provider: :openai,
      api_key: "...",
      enable_metrics: true,
      metrics_callback: fn metrics ->
        send(self(), {:streaming_metrics, metrics})
      end
    )
    
    # Start streaming...
  end
end
```

### With Prometheus

```elixir
defmodule MyApp.PrometheusExporter do
  use Prometheus.PlugExporter
  
  def setup do
    Gauge.declare(
      name: :streaming_bytes_per_second,
      labels: [:provider],
      help: "Streaming throughput in bytes per second"
    )
    
    Counter.declare(
      name: :streaming_chunks_total,
      labels: [:provider, :status],
      help: "Total streaming chunks by provider and status"
    )
    
    Histogram.declare(
      name: :streaming_duration_ms,
      labels: [:provider],
      buckets: [100, 500, 1000, 5000, 10000, 30000],
      help: "Streaming request duration"
    )
  end
  
  def export_metrics(metrics) do
    Gauge.set(
      [name: :streaming_bytes_per_second, labels: [metrics.provider]], 
      metrics.bytes_per_second
    )
    
    if metrics.status == :completed do
      Counter.inc(
        [name: :streaming_chunks_total, labels: [metrics.provider, :success]], 
        metrics.chunks_received
      )
      
      Histogram.observe(
        [name: :streaming_duration_ms, labels: [metrics.provider]], 
        metrics.duration_ms
      )
    end
  end
end
```

## Performance Considerations

1. **Overhead**: When enabled, MetricsPlug adds minimal overhead (< 1% in most cases)
2. **Memory**: Raw chunk storage can consume memory for large streams
3. **Callbacks**: Keep metrics callbacks fast to avoid blocking the stream
4. **Intervals**: Shorter intervals provide more granular data but increase callback frequency

## Best Practices

1. **Production Monitoring**: Always enable metrics in production for observability
2. **Sampling**: For high-volume streams, consider sampling metrics instead of tracking every stream
3. **Alerting**: Set up alerts for slow streams or high error rates
4. **Dashboards**: Create provider-specific dashboards to compare performance
5. **Debugging**: Use `include_raw_chunks` sparingly and only for debugging