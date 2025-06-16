# Circuit Breaker Migration Guide

This guide helps you migrate from direct retry functions to the new circuit breaker-enhanced retry system in ExLLM.

## Overview

Starting with ExLLM v0.8.0, we've integrated a comprehensive circuit breaker pattern into the retry system. This provides better resilience, automatic failure detection, and improved performance under degraded conditions.

## Key Benefits of Migration

1. **Automatic Failure Detection**: Circuit breakers detect persistent failures and prevent unnecessary retries
2. **Resource Protection**: Bulkhead pattern limits concurrent requests to protect system resources
3. **Observability**: Built-in telemetry and metrics for monitoring system health
4. **Adaptive Behavior**: Automatic threshold adjustment based on error patterns
5. **Performance**: Fail-fast behavior reduces latency during outages

## Migration Steps

### Step 1: Update Configuration

Add circuit breaker configuration to your `config.exs`:

```elixir
# config/config.exs
config :ex_llm, :circuit_breaker,
  enabled: true,
  default_options: [
    failure_threshold: 5,
    success_threshold: 2,
    reset_timeout: 30_000,
    timeout: 15_000,
    bulkhead: [
      max_concurrent: 10,
      max_queued: 50,
      queue_timeout: 5_000
    ]
  ]

# Enable metrics (optional but recommended)
config :ex_llm, :circuit_breaker_metrics,
  enabled: true,
  backends: [:prometheus]
```

### Step 2: Replace Direct Retry Calls

#### Before (Direct Retry):
```elixir
# Old approach - direct retry functions
result = ExLLM.Retry.with_retry(fn ->
  ExLLM.chat(model: "gpt-4", messages: messages)
end, max_attempts: 3, initial_delay: 1000)

# Custom retry configuration
result = ExLLM.Retry.with_retry(
  fn -> external_api_call() end,
  max_attempts: 5,
  initial_delay: 500,
  max_delay: 10_000,
  jitter: true
)
```

#### After (Circuit Breaker):
```elixir
# New approach - circuit breaker automatically applied
result = ExLLM.chat(
  model: "gpt-4", 
  messages: messages,
  circuit_breaker: true  # Enabled by default if configured
)

# Custom circuit breaker configuration
result = ExLLM.CircuitBreaker.with_circuit("external_api", fn ->
  external_api_call()
end, [
  failure_threshold: 5,
  timeout: 10_000,
  bulkhead: [max_concurrent: 5]
])
```

### Step 3: Update Error Handling

#### Before:
```elixir
case ExLLM.Retry.with_retry(fn -> api_call() end) do
  {:ok, result} -> 
    process_result(result)
  {:error, :max_attempts_reached} -> 
    handle_failure()
  {:error, reason} -> 
    handle_error(reason)
end
```

#### After:
```elixir
case ExLLM.CircuitBreaker.with_circuit("api_service", fn -> api_call() end) do
  {:ok, result} -> 
    process_result(result)
  {:error, :circuit_open} -> 
    # Circuit is open, service is unavailable
    handle_circuit_open()
  {:error, :bulkhead_full} ->
    # Too many concurrent requests
    handle_overload()
  {:error, reason} -> 
    handle_error(reason)
end
```

### Step 4: Add Monitoring

Set up monitoring for circuit breaker health:

```elixir
# Add telemetry handlers
:telemetry.attach(
  "my-app-circuit-breaker",
  [
    [:ex_llm, :circuit_breaker, :state_change],
    [:ex_llm, :circuit_breaker, :call_rejected]
  ],
  &MyApp.Telemetry.handle_circuit_breaker_event/4,
  nil
)

# Monitor circuit health
{:ok, health} = ExLLM.CircuitBreaker.HealthCheck.check_circuit("api_service")
Logger.info("Circuit health: #{health.health_score}/100")

# Get dashboard data
{:ok, dashboard} = ExLLM.CircuitBreaker.Metrics.Dashboard.get_dashboard_data()
```

### Step 5: Provider-Specific Configuration

Configure circuit breakers per provider:

```elixir
# Provider-specific settings
config :ex_llm, :circuit_breaker,
  providers: [
    anthropic: [
      failure_threshold: 3,
      reset_timeout: 60_000
    ],
    openai: [
      failure_threshold: 5,
      reset_timeout: 30_000,
      bulkhead: [max_concurrent: 20]
    ],
    groq: [
      failure_threshold: 10,  # Higher threshold for faster service
      timeout: 5_000
    ]
  ]
```

## Advanced Migration Patterns

### Gradual Migration

Enable circuit breakers gradually:

```elixir
defmodule MyApp.LLM do
  @circuit_breaker_enabled Application.compile_env(:my_app, :use_circuit_breaker, false)
  
  def chat(opts) do
    if @circuit_breaker_enabled do
      # New circuit breaker approach
      ExLLM.chat(opts)
    else
      # Legacy retry approach
      ExLLM.Retry.with_retry(fn ->
        ExLLM.chat(Keyword.put(opts, :circuit_breaker, false))
      end)
    end
  end
end
```

### Custom Circuit Configurations

Create named circuits for different use cases:

```elixir
# Initialize custom circuits
ExLLM.CircuitBreaker.init_circuit("high_priority", 
  failure_threshold: 2,
  reset_timeout: 10_000
)

ExLLM.CircuitBreaker.init_circuit("batch_processing",
  failure_threshold: 10,
  timeout: 60_000,
  bulkhead: [max_concurrent: 5]
)

# Use named circuits
result = ExLLM.CircuitBreaker.with_circuit("high_priority", fn ->
  critical_api_call()
end)
```

### Fallback Strategies

Implement fallbacks when circuits are open:

```elixir
defmodule MyApp.AIService do
  def get_completion(prompt) do
    primary_result = ExLLM.CircuitBreaker.with_circuit("openai", fn ->
      ExLLM.chat(model: "gpt-4", messages: [%{role: "user", content: prompt}])
    end)
    
    case primary_result do
      {:ok, response} -> 
        {:ok, response}
      {:error, :circuit_open} ->
        # Fallback to alternative provider
        ExLLM.CircuitBreaker.with_circuit("anthropic", fn ->
          ExLLM.chat(model: "claude-3", messages: [%{role: "user", content: prompt}])
        end)
      error -> 
        error
    end
  end
end
```

## Testing Your Migration

### Unit Tests

Update tests to handle circuit breaker states:

```elixir
defmodule MyApp.AIServiceTest do
  use ExUnit.Case
  
  setup do
    # Reset circuit breakers before each test
    ExLLM.CircuitBreaker.reset_all()
    :ok
  end
  
  test "handles circuit open state" do
    # Force circuit to open
    circuit_name = "test_service"
    ExLLM.CircuitBreaker.init_circuit(circuit_name, failure_threshold: 1)
    
    # Trigger failure to open circuit
    ExLLM.CircuitBreaker.with_circuit(circuit_name, fn ->
      {:error, :timeout}
    end)
    
    # Verify circuit is open
    result = ExLLM.CircuitBreaker.with_circuit(circuit_name, fn ->
      {:ok, "should not execute"}
    end)
    
    assert result == {:error, :circuit_open}
  end
end
```

### Integration Tests

Test circuit breaker behavior with real services:

```elixir
test "circuit breaker protects against service failures" do
  # Configure aggressive circuit breaker for testing
  ExLLM.CircuitBreaker.init_circuit("integration_test",
    failure_threshold: 2,
    reset_timeout: 1_000
  )
  
  # Simulate service degradation
  results = for _ <- 1..5 do
    ExLLM.CircuitBreaker.with_circuit("integration_test", fn ->
      # This would be your actual API call
      simulate_flaky_service()
    end)
  end
  
  # Verify circuit opened after failures
  open_results = Enum.filter(results, fn
    {:error, :circuit_open} -> true
    _ -> false
  end)
  
  assert length(open_results) > 0
end
```

## Rollback Plan

If you need to temporarily disable circuit breakers:

```elixir
# Disable globally
config :ex_llm, :circuit_breaker, enabled: false

# Disable per-call
result = ExLLM.chat(
  model: "gpt-4",
  messages: messages,
  circuit_breaker: false
)

# Use legacy retry directly
result = ExLLM.Retry.with_retry(fn ->
  ExLLM.chat(model: "gpt-4", messages: messages, circuit_breaker: false)
end)
```

## Deprecation Timeline

- **v0.8.0**: Circuit breaker support added, direct retry functions deprecated
- **v0.9.0**: Warning logs added when using direct retry functions
- **v1.0.0**: Direct retry functions removed, circuit breaker becomes mandatory

## Getting Help

- **Documentation**: See the [Circuit Breaker Guide](../circuit_breaker_guide.md)
- **Examples**: Check `examples/circuit_breaker_example.exs`
- **Metrics**: Use the dashboard helpers for monitoring
- **Support**: Open an issue on GitHub for migration questions

## Summary

The circuit breaker integration provides a more robust and production-ready retry system. While migration requires some code changes, the benefits include:

1. Automatic failure detection and recovery
2. Better resource utilization with bulkhead pattern
3. Comprehensive observability and metrics
4. Adaptive behavior based on error patterns
5. Protection against cascading failures

Start with updating your configuration, then gradually migrate your retry calls to use circuit breakers. Use the monitoring tools to verify the system is working as expected.