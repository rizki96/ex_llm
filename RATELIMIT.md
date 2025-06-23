# ExLLM Rate Limiting System Design

## Overview

This document outlines the comprehensive design and implementation plan for adding rate limiting capabilities to the ExLLM library. The system addresses the need for preventing 429 rate limit errors across different LLM providers while maintaining high performance and providing flexible configuration options.

## Problem Statement

Different LLM providers have varying rate limits (e.g., Mistral has 1 request per second), and hitting these limits results in 429 errors that disrupt application flow. We need a robust rate limiting system that:

- Supports hierarchical configuration (provider-level defaults, API-level overrides)
- Handles multi-dimensional limits (requests/minute + tokens/minute)
- Integrates seamlessly with ExLLM's pipeline architecture
- Maintains sub-millisecond performance overhead
- Provides proactive delay rather than reactive retry

## Architecture Overview

### Consensus Analysis Results

After consulting with multiple AI models (Gemini Pro and OpenAI's o3), the consensus recommends:

**Architecture Decision: ETS-Based Token Bucket System**

**Points of Agreement:**
- Token bucket algorithm optimal for handling bursts and variable costs
- Multi-dimensional support needed for both request and token-based limits
- Hierarchical configuration with provider/API overrides
- Hybrid error strategy: proactive delay + reactive backoff as fallback
- Performance is critical - must not significantly impact request latency

**Key Architecture Choice:**
- **Primary**: ETS-based storage with atomic operations (chosen for performance)
- **Alternative**: GenServer per scope (simpler but higher latency)

**Rationale for ETS Approach:**
- Lower latency and memory usage
- Better concurrency with `:write_concurrency` and `:decentralized_counters`
- Proven in production (Ranch, Phoenix, Discord libraries)
- Scales to ~100k entries vs process table limits
- No message passing overhead

## System Architecture

```
ExLLM Rate Limiting System Architecture

┌─────────────────────────────────────────────────────────────┐
│                   ExLLM Pipeline                            │
├─────────────────────────────────────────────────────────────┤
│  Provider Request Pipeline:                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Validate    │─▶│ FetchConfig │─▶│ RateLimiter │─────┐   │
│  │ Provider    │  │             │  │    Plug     │     │   │
│  └─────────────┘  └─────────────┘  └─────────────┘     │   │
│                                           │             │   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────▼─────┐      │   │
│  │ Execute     │◀─│ Parse       │◀─│ Build Tesla│      │   │
│  │ Request     │  │ Response    │  │ Client     │      │   │
│  └─────────────┘  └─────────────┘  └───────────┘      │   │
└─────────────────────────────────────────────────────────────┘
                                           │
┌─────────────────────────────────────────▼────────────────────┐
│                Rate Limiter Core Engine                       │
├───────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │ Config      │  │ Cost        │  │ Token       │           │
│  │ Resolver    │─▶│ Calculator  │─▶│ Bucket      │           │
│  │             │  │             │  │ Engine      │           │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
│                                           │                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────▼─────┐           │
│  │ Error       │◀─│ Telemetry   │◀─│ ETS       │           │
│  │ Handler     │  │ Events      │  │ Storage   │           │
│  └─────────────┘  └─────────────┘  └───────────┘           │
└───────────────────────────────────────────────────────────────┘
```

## Module Structure

```
lib/ex_llm/rate_limiter/
├── rate_limiter.ex              # Main public API
├── storage/
│   ├── behavior.ex              # Storage behavior definition
│   ├── ets_storage.ex           # ETS-based implementation
│   └── memory_storage.ex        # In-memory fallback for testing
├── token_bucket.ex              # Token bucket algorithm implementation
├── config.ex                    # Configuration management
└── cost_calculator.ex           # Token/request cost calculation

lib/ex_llm/plugs/
└── rate_limiter.ex              # ExLLM pipeline plug

lib/ex_llm/middleware/
└── rate_limiter.ex              # Tesla middleware wrapper
```

## Configuration System

### Hierarchical Configuration Structure

```elixir
# config/runtime.exs
config :ex_llm, :rate_limiter,
  enabled: true,
  storage: ExLLM.RateLimiter.Storage.EtsStorage,
  default_limits: [
    requests: [limit: 10, period: :minute],
    tokens: [limit: 1000, period: :minute]
  ],
  providers: %{
    mistral: %{
      default: [
        requests: [limit: 1, period: :second],
        tokens: [limit: 1000, period: :minute]
      ],
      embeddings: [
        requests: [limit: 5, period: :second]
      ]
    },
    openai: %{
      default: [
        requests: [limit: 60, period: :minute],
        tokens: [limit: 90_000, period: :minute]
      ],
      chat: [
        tokens: [limit: 40_000, period: :minute]
      ]
    }
  }
```

### Environment Variable Overrides

```bash
# Override provider defaults
EX_LLM_RATE_LIMIT_MISTRAL_REQUESTS_PER_SECOND=2
EX_LLM_RATE_LIMIT_OPENAI_TOKENS_PER_MINUTE=100000

# Override specific API endpoints
EX_LLM_RATE_LIMIT_MISTRAL_CHAT_REQUESTS_PER_SECOND=1
```

### Configuration Resolution Logic

1. Check for API-specific config: `providers.mistral.chat.requests`
2. Fall back to provider default: `providers.mistral.default.requests`
3. Fall back to global default: `default_limits.requests`
4. Apply environment variable overrides at each level

## Core Components

### Token Bucket Algorithm

```elixir
defmodule ExLLM.RateLimiter.TokenBucket do
  @moduledoc """
  Token bucket algorithm with atomic ETS operations for thread safety.
  Supports variable costs and multi-dimensional limits.
  """
  
  @type bucket_key :: {provider :: atom(), api :: atom(), dimension :: atom()}
  @type bucket_state :: %{tokens: float(), last_refill: integer()}
  
  def consume(bucket_key, cost, limit_config) do
    now = System.system_time(:millisecond)
    
    case :ets.lookup(@table, bucket_key) do
      [{^bucket_key, state}] ->
        updated_state = refill_tokens(state, limit_config, now)
        attempt_consume(bucket_key, updated_state, cost, limit_config)
      
      [] ->
        # Initialize new bucket
        initial_state = %{tokens: limit_config.limit, last_refill: now}
        :ets.insert(@table, {bucket_key, initial_state})
        attempt_consume(bucket_key, initial_state, cost, limit_config)
    end
  end
  
  defp attempt_consume(bucket_key, state, cost, _config) do
    if state.tokens >= cost do
      new_state = %{state | tokens: state.tokens - cost}
      :ets.update_element(@table, bucket_key, {2, new_state})
      {:ok, new_state.tokens}
    else
      {:error, :rate_limited, state.tokens}
    end
  end
end
```

### ETS Storage Backend

```elixir
defmodule ExLLM.RateLimiter.Storage.EtsStorage do
  @behaviour ExLLM.RateLimiter.Storage
  
  @table :ex_llm_rate_limiter
  
  def init do
    :ets.new(@table, [
      :named_table, 
      :public, 
      :set,
      {:write_concurrency, true},
      {:decentralized_counters, true}
    ])
  end
  
  def get_state(key), do: :ets.lookup(@table, key)
  def put_state(key, state), do: :ets.insert(@table, {key, state})
  def update_state(key, updater), do: :ets.update_element(@table, key, updater)
end
```

### Pipeline Integration

```elixir
defmodule ExLLM.Plugs.RateLimiter do
  @behaviour ExLLM.Plug
  
  def call(%ExLLM.Pipeline.State{} = state, opts) do
    with {:ok, config} <- get_rate_limit_config(state.provider, state.api_type),
         cost <- calculate_request_cost(state, config),
         {:ok, _remaining} <- ExLLM.RateLimiter.consume(state.provider, state.api_type, cost) do
      state
    else
      {:error, :rate_limited, wait_time} ->
        handle_rate_limit(state, wait_time, opts)
    end
  end
  
  defp handle_rate_limit(state, wait_time, opts) do
    max_wait = Keyword.get(opts, :max_wait, 1000)
    
    if wait_time <= max_wait do
      Process.sleep(wait_time)
      call(state, opts)  # Retry after waiting
    else
      {:error, {:rate_limited, "Request would exceed maximum wait time"}}
    end
  end
end
```

## Error Handling Strategy

### Hybrid Proactive/Reactive Approach

```elixir
defmodule ExLLM.RateLimiter.ErrorHandler do
  @max_proactive_wait 2_000  # 2 seconds max proactive wait
  @retry_backoff_base 1_000   # 1 second base retry delay
  @max_retries 3
  
  def handle_rate_limit(request_state, wait_time, opts \\ []) do
    max_wait = Keyword.get(opts, :max_wait, @max_proactive_wait)
    strategy = Keyword.get(opts, :strategy, :hybrid)
    
    case strategy do
      :proactive -> handle_proactive_wait(request_state, wait_time, max_wait)
      :reactive -> handle_reactive_retry(request_state, opts)
      :hybrid -> handle_hybrid_approach(request_state, wait_time, max_wait, opts)
    end
  end
  
  defp handle_hybrid_approach(state, wait_time, max_wait, opts) do
    if wait_time <= max_wait do
      # Short wait - handle proactively
      Process.sleep(wait_time)
      ExLLM.RateLimiter.retry_request(state)
    else
      # Long wait - proceed and handle 429s reactively
      case ExLLM.Pipeline.proceed_without_limit_check(state) do
        {:error, {:api_error, %{status: 429}}} ->
          handle_reactive_retry(state, opts)
        result -> result
      end
    end
  end
end
```

## Implementation Roadmap

### Phase 1: Foundation

**Milestone 1.1: Core Token Bucket Engine**
- Deliverables:
  - `ExLLM.RateLimiter.TokenBucket` module with ETS storage
  - `ExLLM.RateLimiter.Storage.EtsStorage` implementation
  - Basic configuration structure in `ExLLM.RateLimiter.Config`
- Success Criteria:
  - Token bucket algorithm handles 1000 req/sec with <0.1ms overhead
  - ETS storage supports concurrent access from 100+ processes
  - Unit tests achieve 100% coverage for core algorithm

**Milestone 1.2: Configuration System**
- Deliverables:
  - Hierarchical configuration resolution (provider → API → default)
  - Environment variable override support
  - Configuration validation at startup
- Success Criteria:
  - Can configure Mistral 1 req/sec limit via config and env vars
  - Configuration hot-reloading works without restart
  - Invalid configurations fail with clear error messages

### Phase 2: Integration

**Milestone 2.1: Pipeline Plug**
- Deliverables:
  - `ExLLM.Plugs.RateLimiter` implementation
  - Cost calculation framework for tokens/requests
  - Integration with existing provider pipelines
- Success Criteria:
  - Rate limiter plug integrates without breaking existing tests
  - Mistral pipeline correctly delays requests exceeding 1/second
  - Token cost estimation within 20% accuracy for major providers

**Milestone 2.2: Error Handling**
- Deliverables:
  - Hybrid proactive/reactive error handling
  - Circuit breaker integration
  - Graceful degradation strategies
- Success Criteria:
  - Handles ETS table failures without crashing
  - Proactive delays work for waits <2 seconds
  - Reactive retry handles 429 errors with exponential backoff

### Phase 3: Production Readiness

**Milestone 3.1: Advanced Features**
- Deliverables:
  - Multi-dimensional rate limiting (requests + tokens)
  - Tesla middleware wrapper
  - Telemetry and observability
- Success Criteria:
  - OpenAI token-based limiting prevents quota exhaustion
  - Tesla middleware works for direct Tesla users
  - Metrics track rate limiter effectiveness and performance

**Milestone 3.2: Testing & Documentation**
- Deliverables:
  - Comprehensive test suite (unit, integration, performance)
  - RATELIMIT.md documentation
  - Configuration examples for each provider
- Success Criteria:
  - All tests pass including performance benchmarks
  - Documentation covers common use cases
  - Backward compatibility verified with existing configurations

## Dependency Graph

```
Critical Path Dependencies:

1. Token bucket algorithm → ETS storage → Pipeline integration
2. Configuration system → Error handling → Production features  
3. Testing infrastructure → All other components

Parallel Development:
- Configuration system (can develop alongside core engine)
- Error handling strategies (independent of storage implementation)
- Tesla middleware (wrapper around core functionality)
```

## Testing Strategy

### Unit Testing
- Token bucket algorithm correctness
- ETS storage thread safety under load
- Configuration hierarchy resolution
- Cost calculation accuracy

### Integration Testing
- Pipeline integration without breaking existing functionality
- Real provider testing with aggressive rate limits
- Multi-dimensional limiting validation

### Performance Testing
- Rate limiter overhead measurement (<1ms requirement)
- Concurrent access testing (100+ processes)
- Load testing under sustained high traffic

### Example Test Case

```elixir
@tag :integration
test "rate limiting with real provider pipeline" do
  # Configure aggressive rate limiting for testing
  Application.put_env(:ex_llm, :rate_limiter, 
    providers: %{
      mistral: %{
        default: [requests: [limit: 1, period: :second]]
      }
    }
  )
  
  messages = [%{role: "user", content: "Hello"}]
  
  # First request should succeed
  assert {:ok, _} = ExLLM.chat(:mistral, messages, max_tokens: 5)
  
  # Second immediate request should be delayed
  start_time = System.monotonic_time(:millisecond)
  assert {:ok, _} = ExLLM.chat(:mistral, messages, max_tokens: 5)
  end_time = System.monotonic_time(:millisecond)
  
  # Should have been delayed by ~1 second
  assert end_time - start_time >= 900  # Allow some variance
end
```

## Risk Mitigation

### Performance Risk
- Benchmark after each milestone
- Fallback to simpler algorithm if needed
- Performance monitoring via telemetry

### Integration Risk
- Test with each provider pipeline
- Maintain feature flags for rollback
- Gradual rollout per provider

### Complexity Risk
- Start with request-based limiting
- Add token support incrementally
- Comprehensive documentation and examples

## Success Metrics

- Zero 429 errors in normal operation with rate limiting enabled
- <1ms added latency per request (measured via telemetry)
- 99.9% availability of rate limiting functionality
- Successful deployment to production without rollback

## Future Considerations

### Clustering Support
- Current ETS implementation is node-local
- Future: Abstract storage behind behavior for Redis/Mnesia support
- Consider `:pg` sharded buckets for distributed scenarios

### Advanced Features
- Per-user rate limiting (beyond provider/API scope)
- Dynamic rate limit adjustment based on API responses
- Rate limit sharing across multiple application instances
- Integration with external rate limiting services

## Conclusion

This comprehensive rate limiting system will address the immediate need for Mistral's 1 request/second limitation while providing a robust, extensible foundation for all LLM providers in the ExLLM ecosystem. The ETS-based token bucket approach ensures high performance while the hierarchical configuration system provides the flexibility needed for diverse provider requirements.

The hybrid error handling strategy balances user experience (proactive delays for short waits) with system resilience (reactive retry for longer delays), ensuring robust operation across various rate limiting scenarios.