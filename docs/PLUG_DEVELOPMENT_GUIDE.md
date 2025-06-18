# ExLLM Plug Development Guide

This guide covers how to create custom plugs for the ExLLM pipeline architecture. If you're familiar with Phoenix plugs, ExLLM plugs follow similar patterns but are designed specifically for LLM operations.

## Table of Contents

- [Overview](#overview)
- [Basic Plug Structure](#basic-plug-structure)
- [Request Lifecycle](#request-lifecycle)
- [Creating Your First Plug](#creating-your-first-plug)
- [Testing Plugs](#testing-plugs)
- [Common Patterns](#common-patterns)
- [Best Practices](#best-practices)
- [Advanced Topics](#advanced-topics)

## Overview

ExLLM plugs are modules that implement the `ExLLM.Plug` behavior. They transform an `ExLLM.Pipeline.Request` struct as it flows through the pipeline. Each plug can:

- Modify request data (messages, configuration, etc.)
- Add metadata and assigns for inter-plug communication
- Make HTTP requests to LLM providers
- Handle errors and halt the pipeline
- Perform side effects (logging, metrics, etc.)

## Basic Plug Structure

Every ExLLM plug must implement two functions:

```elixir
defmodule MyApp.Plugs.CustomPlug do
  @moduledoc """
  Description of what your plug does.
  """
  
  use ExLLM.Plug
  
  @impl true
  def init(opts) do
    # Validate and transform options passed to the plug
    # This runs at compile time for static plugs
    Keyword.validate!(opts, [:required_option, :optional_option])
  end
  
  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, opts) do
    # Transform the request
    # This runs for each request at runtime
    request
  end
end
```

## Request Lifecycle

The `ExLLM.Pipeline.Request` struct flows through the pipeline:

```elixir
%ExLLM.Pipeline.Request{
  # Core data
  id: "unique-request-id",
  provider: :openai,
  messages: [%{role: "user", content: "Hello"}],
  options: %{model: "gpt-4", temperature: 0.7},
  
  # Pipeline state
  halted: false,
  state: :pending,  # :pending -> :executing -> :completed | :error
  
  # Configuration and HTTP
  config: %{},          # Merged configuration
  tesla_client: nil,    # HTTP client (set by BuildTeslaClient)
  provider_request: %{}, # Formatted request body
  response: nil,        # Raw HTTP response
  result: nil,          # Parsed LLM response
  
  # Communication between plugs
  assigns: %{},         # Public inter-plug data
  private: %{},         # Internal/private data
  metadata: %{},        # Request metadata (timing, tokens, cost)
  errors: [],           # List of errors
  
  # Streaming (if applicable)
  stream_pid: nil,
  stream_ref: nil
}
```

## Creating Your First Plug

Let's create a simple logging plug:

```elixir
defmodule MyApp.Plugs.RequestLogger do
  @moduledoc """
  Logs request information for debugging and monitoring.
  """
  
  use ExLLM.Plug
  require Logger
  
  @impl true
  def init(opts) do
    Keyword.validate!(opts, [
      :level,      # Log level (:debug, :info, :warn)
      :include,    # What to include in logs (list of atoms)
      :exclude     # What to exclude from logs (list of atoms)
    ])
  end
  
  @impl true
  def call(%Request{} = request, opts) do
    level = Keyword.get(opts, :level, :info)
    include = Keyword.get(opts, :include, [:provider, :model, :message_count])
    exclude = Keyword.get(opts, :exclude, [])
    
    # Build log data
    log_data = build_log_data(request, include, exclude)
    
    # Log the request
    Logger.log(level, "ExLLM Request", log_data)
    
    # Add logging metadata
    request
    |> Request.put_metadata(:logged_at, DateTime.utc_now())
    |> Request.put_metadata(:log_level, level)
  end
  
  defp build_log_data(request, include, exclude) do
    %{
      request_id: request.id,
      provider: request.provider,
      model: request.config[:model],
      message_count: length(request.messages),
      state: request.state,
      has_errors: length(request.errors) > 0
    }
    |> Map.take(include)
    |> Map.drop(exclude)
  end
end
```

### Using the Plug

```elixir
# In a pipeline
pipeline = [
  ExLLM.Plugs.ValidateProvider,
  {MyApp.Plugs.RequestLogger, level: :debug, include: [:provider, :model]},
  ExLLM.Plugs.FetchConfig,
  # ... other plugs
]

# Or in provider pipeline definitions
defp custom_chat_pipeline do
  [
    ExLLM.Plugs.ValidateProvider,
    ExLLM.Plugs.FetchConfig,
    MyApp.Plugs.RequestLogger,
    ExLLM.Plugs.BuildTeslaClient,
    ExLLM.Plugs.ExecuteRequest,
    ExLLM.Plugs.ParseResponse
  ]
end
```

## Testing Plugs

ExLLM provides comprehensive testing utilities:

```elixir
defmodule MyApp.Plugs.RequestLoggerTest do
  use ExUnit.Case, async: true
  use ExLLM.PlugTest
  
  import ExUnit.CaptureLog
  alias MyApp.Plugs.RequestLogger
  
  test "logs request information" do
    request = build_request(
      provider: :openai,
      options: %{model: "gpt-4"}
    )
    
    log_output = capture_log(fn ->
      run_plug(request, RequestLogger, level: :info)
    end)
    
    assert log_output =~ "ExLLM Request"
    assert log_output =~ "openai"
    assert log_output =~ "gpt-4"
  end
  
  test "adds metadata to request" do
    request = build_request()
    result = run_plug(request, RequestLogger)
    
    assert_metadata(result, :log_level, :info)
    assert Map.has_key?(result.metadata, :logged_at)
  end
  
  test "respects include/exclude options" do
    request = build_request(provider: :anthropic)
    
    log_output = capture_log(fn ->
      run_plug(request, RequestLogger, 
        include: [:provider],
        exclude: [:model]
      )
    end)
    
    assert log_output =~ "anthropic"
    refute log_output =~ "model"
  end
end
```

## Common Patterns

### Configuration Plug

```elixir
defmodule MyApp.Plugs.SetDefaults do
  use ExLLM.Plug
  
  @impl true
  def call(%Request{} = request, opts) do
    defaults = Keyword.get(opts, :defaults, %{})
    
    # Merge defaults with existing options (options take precedence)
    updated_options = Map.merge(defaults, request.options)
    
    %{request | options: updated_options}
  end
end

# Usage
{MyApp.Plugs.SetDefaults, defaults: %{temperature: 0.7, max_tokens: 1000}}
```

### Conditional Plug

```elixir
defmodule MyApp.Plugs.ConditionalAuth do
  use ExLLM.Plug
  
  @impl true
  def call(%Request{} = request, opts) do
    condition = Keyword.get(opts, :when, fn _ -> true end)
    
    if condition.(request) do
      # Apply authentication
      add_auth_headers(request)
    else
      # Skip authentication
      request
    end
  end
  
  defp add_auth_headers(request) do
    # Add custom auth headers
    Request.assign(request, :custom_auth, true)
  end
end

# Usage
{MyApp.Plugs.ConditionalAuth, when: &(&1.provider == :custom_provider)}
```

### Error Handling Plug

```elixir
defmodule MyApp.Plugs.ErrorRecovery do
  use ExLLM.Plug
  
  @impl true
  def call(%Request{state: :error} = request, opts) do
    strategy = Keyword.get(opts, :strategy, :halt)
    
    case strategy do
      :halt ->
        # Keep the error state (default behavior)
        request
        
      :retry ->
        # Clear errors and reset to pending
        %{request | errors: [], state: :pending, halted: false}
        
      :fallback ->
        # Switch to fallback provider
        fallback_provider = Keyword.get(opts, :fallback_provider, :mock)
        %{request | provider: fallback_provider, errors: [], state: :pending}
    end
  end
  
  def call(%Request{} = request, _opts) do
    # No error, pass through
    request
  end
end
```

### Caching Plug

```elixir
defmodule MyApp.Plugs.CustomCache do
  use ExLLM.Plug
  
  @impl true
  def init(opts) do
    Keyword.validate!(opts, [:ttl, :key_fn, :store])
  end
  
  @impl true
  def call(%Request{} = request, opts) do
    ttl = Keyword.get(opts, :ttl, 300)  # 5 minutes default
    key_fn = Keyword.get(opts, :key_fn, &default_cache_key/1)
    store = Keyword.get(opts, :store, MyApp.Cache)
    
    cache_key = key_fn.(request)
    
    case store.get(cache_key) do
      {:ok, cached_result} ->
        # Cache hit
        request
        |> Map.put(:result, cached_result)
        |> Request.put_state(:completed)
        |> Request.assign(:cache_hit, true)
        
      {:error, :not_found} ->
        # Cache miss - add cache storage for later plugs
        request
        |> Request.assign(:cache_key, cache_key)
        |> Request.assign(:cache_ttl, ttl)
        |> Request.assign(:cache_store, store)
    end
  end
  
  defp default_cache_key(request) do
    # Create cache key from provider, messages, and config
    :crypto.hash(:sha256, :erlang.term_to_binary({
      request.provider,
      request.messages,
      request.config
    }))
    |> Base.encode16(case: :lower)
  end
end
```

## Best Practices

### 1. **Single Responsibility**
Each plug should have one clear purpose:

```elixir
# Good: Single purpose
defmodule MyApp.Plugs.ValidateApiKey do
  # Only validates API key
end

# Bad: Multiple responsibilities
defmodule MyApp.Plugs.ValidateAndLogAndCache do
  # Does too many things
end
```

### 2. **Immutable Transformations**
Always return a new request struct:

```elixir
# Good: Immutable transformation
def call(%Request{} = request, _opts) do
  %{request | state: :completed}
end

# Bad: Mutation (won't work anyway in Elixir)
def call(%Request{} = request, _opts) do
  request.state = :completed  # This doesn't work
  request
end
```

### 3. **Proper Error Handling**
Use `Request.halt_with_error/2` for terminal errors:

```elixir
def call(%Request{} = request, _opts) do
  case validate_something(request) do
    :ok ->
      request
      
    {:error, reason} ->
      Request.halt_with_error(request, %{
        plug: __MODULE__,
        error: :validation_failed,
        message: "Validation failed: #{reason}"
      })
  end
end
```

### 4. **Option Validation**
Always validate options in `init/1`:

```elixir
@impl true
def init(opts) do
  # Validate required and optional options
  Keyword.validate!(opts, [
    :required_option,
    optional_option: :default_value
  ])
end
```

### 5. **Documentation**
Document your plugs thoroughly:

```elixir
defmodule MyApp.Plugs.CustomPlug do
  @moduledoc """
  Brief description of what the plug does.
  
  ## Options
  
    * `:option1` - Description of option1 (required)
    * `:option2` - Description of option2 (default: `value`)
    
  ## Examples
  
      # Basic usage
      plug MyApp.Plugs.CustomPlug
      
      # With options
      plug MyApp.Plugs.CustomPlug, option1: "value", option2: :custom
      
  ## Assigns Set
  
    * `:assign_name` - Description of what this assign contains
    
  ## Metadata Set
  
    * `:metadata_key` - Description of metadata
  """
```

## Advanced Topics

### Provider-Specific Plugs

Create plugs that only run for certain providers:

```elixir
defmodule MyApp.Plugs.OpenAISpecific do
  use ExLLM.Plug
  
  @impl true
  def call(%Request{provider: :openai} = request, opts) do
    # OpenAI-specific logic
    apply_openai_customizations(request, opts)
  end
  
  def call(%Request{} = request, _opts) do
    # Other providers - pass through unchanged
    request
  end
end
```

### Streaming Plugs

Handle streaming responses:

```elixir
defmodule MyApp.Plugs.StreamHandler do
  use ExLLM.Plug
  
  @impl true
  def call(%Request{options: %{stream: true}} = request, opts) do
    callback = Keyword.get(opts, :callback)
    
    request
    |> Request.assign(:stream_callback, callback)
    |> Request.put_state(:streaming)
  end
  
  def call(%Request{} = request, _opts) do
    # Not streaming
    request
  end
end
```

### Pipeline Composition

Create reusable pipeline segments:

```elixir
defmodule MyApp.Pipelines.Common do
  def auth_pipeline do
    [
      MyApp.Plugs.ValidateApiKey,
      MyApp.Plugs.CheckRateLimit,
      MyApp.Plugs.LogRequest
    ]
  end
  
  def post_processing_pipeline do
    [
      MyApp.Plugs.ExtractMetadata,
      MyApp.Plugs.CalculateCost,
      MyApp.Plugs.SaveToDatabase
    ]
  end
end

# Use in provider pipelines
defp custom_chat_pipeline do
  MyApp.Pipelines.Common.auth_pipeline() ++
  [
    ExLLM.Plugs.BuildTeslaClient,
    ExLLM.Plugs.ExecuteRequest,
    ExLLM.Plugs.ParseResponse
  ] ++
  MyApp.Pipelines.Common.post_processing_pipeline()
end
```

### Integration with External Services

```elixir
defmodule MyApp.Plugs.ExternalService do
  use ExLLM.Plug
  
  @impl true
  def call(%Request{} = request, opts) do
    service_url = Keyword.get(opts, :service_url)
    
    # Make external API call
    case HTTPoison.post(service_url, Jason.encode!(request.messages)) do
      {:ok, %{status_code: 200, body: body}} ->
        enriched_data = Jason.decode!(body)
        Request.assign(request, :external_data, enriched_data)
        
      {:error, reason} ->
        # Log error but don't halt pipeline
        Logger.warning("External service failed: #{inspect(reason)}")
        request
    end
  end
end
```

This guide should get you started with creating powerful, reusable plugs for the ExLLM pipeline architecture. Remember to test your plugs thoroughly and follow Elixir conventions for the best developer experience.