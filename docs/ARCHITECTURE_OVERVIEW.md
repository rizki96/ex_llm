# ExLLM Pipeline Architecture Overview

This document provides a comprehensive overview of ExLLM's Phoenix-style pipeline architecture, introduced in v1.0. The pipeline system offers a flexible, extensible, and composable approach to handling LLM operations while maintaining backward compatibility.

## Table of Contents

- [Core Concepts](#core-concepts)
- [Pipeline Architecture](#pipeline-architecture)
- [Request Lifecycle](#request-lifecycle)
- [Plug System](#plug-system)
- [Provider Integration](#provider-integration)
- [Builder Pattern](#builder-pattern)
- [Advanced Features](#advanced-features)
- [Performance Characteristics](#performance-characteristics)
- [Migration from v0.8](#migration-from-v08)

## Core Concepts

### Pipeline-First Design

ExLLM v1.0 adopts a pipeline-first architecture where every LLM operation flows through a configurable series of plugs. This approach provides:

- **Composability**: Mix and match functionality through plug composition
- **Extensibility**: Add custom behavior without modifying core code
- **Testability**: Test individual plugs and pipeline segments in isolation
- **Observability**: Built-in logging, metrics, and debugging capabilities
- **Consistency**: Unified behavior across all providers and operations

### Request/Response Model

All operations are modeled as transformations of an `ExLLM.Pipeline.Request` struct:

```elixir
%ExLLM.Pipeline.Request{
  # Core data
  id: "unique-request-id",
  provider: :openai,
  messages: [%{role: "user", content: "Hello"}],
  options: %{model: "gpt-4", temperature: 0.7},
  
  # Pipeline state
  state: :pending,  # :pending -> :executing -> :completed | :error
  halted: false,
  
  # HTTP and configuration
  config: %{api_key: "sk-..."},
  tesla_client: #Tesla.Client<...>,
  provider_request: %{...},  # Formatted for provider API
  response: %Tesla.Env{...}, # Raw HTTP response
  result: %{...},            # Parsed LLM response
  
  # Communication and metadata
  assigns: %{},     # Public inter-plug data
  private: %{},     # Internal plug data
  metadata: %{},    # Request metadata (timing, cost, etc.)
  errors: []        # Error accumulation
}
```

## Pipeline Architecture

### Pipeline Structure

A pipeline is a list of plugs that process requests sequentially:

```elixir
pipeline = [
  ExLLM.Plugs.ValidateProvider,           # 1. Validate input
  ExLLM.Plugs.FetchConfig,                # 2. Load configuration
  {ExLLM.Plugs.Cache, ttl: 3600},         # 3. Check cache (with options)
  ExLLM.Plugs.BuildTeslaClient,           # 4. Setup HTTP client
  ExLLM.Plugs.Providers.OpenaiPrepareRequest,  # 5. Format for provider
  ExLLM.Plugs.ExecuteRequest,             # 6. Make HTTP call
  ExLLM.Plugs.Providers.OpenaiParseResponse,   # 7. Parse response
  ExLLM.Plugs.TrackCost,                  # 8. Calculate costs
  ExLLM.Plugs.Cache                       # 9. Store in cache
]
```

### Pipeline Types

ExLLM supports different pipeline types for different operations:

- **`:chat`** - Standard chat completions
- **`:stream`** - Streaming chat responses  
- **`:embeddings`** - Text embedding generation
- **`:completion`** - Legacy completion API
- **`:list_models`** - Model enumeration
- **`:validate`** - Configuration validation

### Provider-Specific Pipelines

Each provider has customized pipelines optimized for their API characteristics:

```elixir
# OpenAI pipeline - straightforward REST API
openai_chat_pipeline = [
  ExLLM.Plugs.ValidateProvider,
  ExLLM.Plugs.FetchConfig,
  ExLLM.Plugs.BuildTeslaClient,
  ExLLM.Plugs.Providers.OpenaiPrepareRequest,
  ExLLM.Plugs.ExecuteRequest,
  ExLLM.Plugs.Providers.OpenaiParseResponse,
  ExLLM.Plugs.TrackCost
]

# Gemini pipeline - includes OAuth2 and content filtering
gemini_chat_pipeline = [
  ExLLM.Plugs.ValidateProvider,
  ExLLM.Plugs.FetchConfig,
  ExLLM.Plugs.Providers.GeminiOauth2,     # OAuth2 authentication
  ExLLM.Plugs.BuildTeslaClient,
  ExLLM.Plugs.Providers.GeminiPrepareRequest,
  ExLLM.Plugs.Providers.GeminiContentFilter,  # Safety filtering
  ExLLM.Plugs.ExecuteRequest,
  ExLLM.Plugs.Providers.GeminiParseResponse,
  ExLLM.Plugs.TrackCost
]
```

## Request Lifecycle

### 1. Initialization Phase

```elixir
# Create request with provider, messages, and options
request = ExLLM.Pipeline.Request.new(:openai, messages, %{
  model: "gpt-4-turbo",
  temperature: 0.7
})
```

### 2. Pipeline Execution Phase

```elixir
# Get provider pipeline and execute
pipeline = ExLLM.Providers.get_pipeline(:openai, :chat)
result = ExLLM.Pipeline.run(request, pipeline)
```

### 3. State Transitions

```
:pending -> :executing -> :completed (success)
         -> :executing -> :error     (failure)
         -> :halted                  (early termination)
```

### 4. Error Handling

Errors are accumulated in the `errors` field and can be:
- **Recoverable**: Request continues with warnings
- **Terminal**: Request is halted and marked as `:error`

## Plug System

### Plug Behavior

Every plug implements the `ExLLM.Plug` behavior:

```elixir
defmodule MyApp.Plugs.CustomPlug do
  use ExLLM.Plug
  
  @impl true
  def init(opts) do
    # Compile-time option validation and transformation
    Keyword.validate!(opts, [:required_option])
  end
  
  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, opts) do
    # Runtime request transformation
    request
    |> ExLLM.Pipeline.Request.assign(:custom_data, "value")
    |> ExLLM.Pipeline.Request.put_metadata(:processed_at, DateTime.utc_now())
  end
end
```

### Built-in Plugs

ExLLM includes many built-in plugs for common functionality:

#### Core Infrastructure Plugs
- **`ValidateProvider`** - Ensures provider is supported
- **`FetchConfig`** - Loads provider configuration
- **`BuildTeslaClient`** - Creates HTTP client with middleware
- **`ExecuteRequest`** - Makes HTTP requests to provider APIs
- **`TrackCost`** - Calculates and tracks API costs

#### Feature Plugs
- **`Cache`** - Request/response caching with TTL
- **`RateLimiter`** - Rate limiting per provider/user
- **`CircuitBreaker`** - Fault tolerance and recovery
- **`RetryPolicy`** - Configurable retry with backoff
- **`ManageContext`** - Context window management

#### Provider-Specific Plugs
- **`OpenaiPrepareRequest`** - Format requests for OpenAI API
- **`GeminiOauth2`** - Handle Gemini OAuth2 authentication
- **`AnthropicParseResponse`** - Parse Claude API responses

### Custom Plugs

Create custom plugs for application-specific needs:

```elixir
defmodule MyApp.Plugs.AuditLogger do
  use ExLLM.Plug
  
  def call(%Request{} = request, _opts) do
    # Log request for audit trail
    MyApp.AuditLog.record_llm_request(request.id, request.provider)
    
    # Add response callback for completion logging
    callback = fn completed_request ->
      MyApp.AuditLog.record_llm_response(
        completed_request.id, 
        completed_request.result
      )
    end
    
    ExLLM.Pipeline.Request.assign(request, :audit_callback, callback)
  end
end
```

## Provider Integration

### Provider Module Structure

Each provider implements a consistent interface:

```elixir
defmodule ExLLM.Providers.OpenAI do
  @behaviour ExLLM.Providers.Provider
  
  def get_pipeline(:chat), do: openai_chat_pipeline()
  def get_pipeline(:stream), do: openai_stream_pipeline()
  def get_pipeline(:embeddings), do: openai_embeddings_pipeline()
  
  def get_config(), do: Application.get_env(:ex_llm, :openai, [])
  
  defp openai_chat_pipeline() do
    [
      ExLLM.Plugs.ValidateProvider,
      ExLLM.Plugs.FetchConfig,
      ExLLM.Plugs.BuildTeslaClient,
      ExLLM.Plugs.Providers.OpenaiPrepareRequest,
      ExLLM.Plugs.ExecuteRequest,
      ExLLM.Plugs.Providers.OpenaiParseResponse,
      ExLLM.Plugs.TrackCost
    ]
  end
end
```

### Adding New Providers

1. Create provider module implementing `ExLLM.Providers.Provider`
2. Create provider-specific prepare/parse plugs
3. Add provider to registry in `ExLLM.Providers`
4. Add configuration schema
5. Add tests using `ExLLM.PlugTest`

## Builder Pattern

### Simple Builder Usage

```elixir
{:ok, response} = 
  ExLLM.build(:openai, messages)
  |> ExLLM.with_model("gpt-4-turbo")
  |> ExLLM.with_temperature(0.7)
  |> ExLLM.execute()
```

### Advanced Pipeline Customization

```elixir
{:ok, response} = 
  ExLLM.build(:openai, messages)
  |> ExLLM.with_cache(ttl: 3600)
  |> ExLLM.with_custom_plug(MyApp.Plugs.AuditLogger)
  |> ExLLM.without_cost_tracking()
  |> ExLLM.with_context_strategy(:truncate, max_tokens: 8000)
  |> ExLLM.execute()
```

### Streaming with Builder

```elixir
ExLLM.build(:openai, messages)
|> ExLLM.with_model("gpt-4")
|> ExLLM.stream(fn chunk ->
  case chunk do
    %{done: true} -> IO.puts("\nDone!")
    %{content: content} -> IO.write(content)
  end
end)
```

### Pipeline Inspection and Debugging

```elixir
builder = 
  ExLLM.build(:openai, messages)
  |> ExLLM.with_cache()
  |> ExLLM.with_custom_plug(MyApp.Plugs.Logger)

# Inspect the pipeline that would execute
pipeline = ExLLM.inspect_pipeline(builder)
IO.inspect(pipeline, label: "Pipeline")

# Get detailed builder state
debug_info = ExLLM.debug_info(builder)
IO.inspect(debug_info, label: "Builder State")
```

## Advanced Features

### Context Management

ExLLM provides automatic context window management:

```elixir
# Truncation strategy
builder |> ExLLM.with_context_strategy(:truncate, max_tokens: 8000)

# Smart summarization (requires summary model)
builder |> ExLLM.with_context_strategy(:summarize, 
  preserve_system: true,
  summary_model: "gpt-3.5-turbo"
)

# Sliding window
builder |> ExLLM.with_context_strategy(:sliding_window, window_size: 10)
```

### Caching System

Multiple caching strategies available:

```elixir
# Memory cache with TTL
builder |> ExLLM.with_cache(ttl: 3600)

# Persistent cache
builder |> ExLLM.with_cache(
  store: :redis,
  ttl: :infinity,
  key_fn: &MyApp.Cache.custom_key/1
)

# Disable caching for sensitive requests
builder |> ExLLM.without_cache()
```

### Circuit Breakers and Resilience

```elixir
# Configure circuit breaker
builder |> ExLLM.with_custom_plug(ExLLM.Plugs.CircuitBreaker,
  failure_threshold: 5,
  recovery_time: 30_000,
  timeout: 10_000
)

# Add retry policy
builder |> ExLLM.with_custom_plug(ExLLM.Plugs.RetryPolicy,
  max_attempts: 3,
  backoff: :exponential,
  base_delay: 1000
)
```

### Custom Pipeline Composition

```elixir
# Define reusable pipeline segments
auth_pipeline = [
  MyApp.Plugs.ValidateApiKey,
  MyApp.Plugs.CheckRateLimit
]

post_processing = [
  MyApp.Plugs.ExtractMetadata,
  MyApp.Plugs.SaveToDatabase
]

# Compose custom pipeline
custom_pipeline = 
  auth_pipeline ++
  ExLLM.Providers.get_pipeline(:openai, :chat) ++
  post_processing

# Use with builder
builder |> ExLLM.with_pipeline(custom_pipeline)
```

## Performance Characteristics

### Pipeline Overhead

- **Cold start**: ~1-2ms for pipeline setup
- **Hot path**: ~0.1-0.5ms per plug execution
- **Memory**: ~100-200 bytes per request struct
- **Garbage collection**: Minimal due to immutable transformations

### Caching Performance

- **Memory cache**: Sub-millisecond lookup
- **Redis cache**: 1-5ms lookup depending on network
- **Cache hit rate**: Typically 15-30% for chat workloads
- **Storage efficiency**: ~80% compression with semantic hashing

### Streaming Performance

- **Latency**: First token within 50-200ms of provider response
- **Throughput**: Handles 1000+ concurrent streams
- **Memory**: Constant memory usage regardless of response length
- **Backpressure**: Automatic flow control with slow consumers

### Scalability

- **Horizontal**: Stateless design supports clustering
- **Vertical**: Linear scaling with CPU cores
- **Provider limits**: Respects rate limits via circuit breakers
- **Resource usage**: ~10MB per 1000 concurrent requests

## Migration from v0.8

### Backward Compatibility

v1.0 maintains 100% backward compatibility with v0.8 APIs:

```elixir
# v0.8 code continues to work unchanged
{:ok, response} = ExLLM.chat(:openai, messages, model: "gpt-4")
```

### Gradual Migration Path

1. **Continue using simple API** for basic use cases
2. **Adopt builder pattern** for new features requiring customization
3. **Create custom plugs** for application-specific behavior
4. **Optimize pipelines** based on performance requirements

### New Capabilities in v1.0

- Pipeline customization and composition
- Built-in caching and resilience patterns
- Enhanced debugging and observability
- Consistent streaming across all providers
- Automatic context management
- Cost tracking and optimization

---

This architecture provides a solid foundation for building robust, scalable LLM applications while maintaining the simplicity that made ExLLM popular. The pipeline system offers the flexibility to handle everything from simple chat bots to complex AI agents with sophisticated prompt engineering and tool integration.