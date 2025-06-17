# Migration Guide: ExLLM v0.8.x to v0.9.0

This guide helps you migrate from ExLLM v0.8.x to the new pipeline architecture in v0.9.0.

> **Note**: Since ExLLM is pre-1.0.0, breaking changes are expected. This guide focuses on the most common migration patterns.

## Overview of Changes

### What's New
- Phoenix-style pipeline architecture with plugs
- Three-tier API: High-Level, Builder, and Pipeline
- Improved streaming with coordinator-based architecture
- Extensible plug system for custom functionality
- Better separation of concerns between LLM and HTTP layers

### What's Changed
- Core API functions now require messages as a list (not just string content)
- Streaming API has been unified and simplified
- Direct adapter calls are now discouraged in favor of pipeline execution
- Configuration is now handled through plugs

### What's Removed
- Direct adapter module access (use pipelines instead)
- Some internal modules that are now private to the pipeline

## API Migration

### Basic Chat Completion

**Old API (v0.8.x):**
```elixir
# String content was accepted
{:ok, response} = ExLLM.chat(:openai, "Hello, world!")

# Or with message list
{:ok, response} = ExLLM.chat(:openai, [
  %{role: "user", content: "Hello, world!"}
])
```

**New API (v0.9.0):**
```elixir
# Messages must be a list
messages = [%{role: "user", content: "Hello, world!"}]
{:ok, response} = ExLLM.chat(:openai, messages)

# Options are now passed as a map (3rd argument)
{:ok, response} = ExLLM.chat(:openai, messages, %{
  model: "gpt-4",
  temperature: 0.7
})
```

### Streaming

**Old API (v0.8.x):**
```elixir
# Various streaming functions
{:ok, stream_pid} = ExLLM.stream_chat(:openai, "Tell a story", fn chunk ->
  IO.write(chunk.content)
end)

# Or with ChatStream
{:ok, stream} = ExLLM.ChatStream.new(:openai, messages)
```

**New API (v0.9.0):**
```elixir
# Unified streaming API
ExLLM.stream(:openai, messages, %{stream: true}, fn chunk ->
  IO.write(chunk.content || "")
end)

# Note: chunk.content might be nil for metadata chunks
```

### Session Management

**Old API (v0.8.x):**
```elixir
{:ok, session} = ExLLM.new_session(:anthropic, 
  model: "claude-3-sonnet"
)
{:ok, session, response} = ExLLM.chat_with_session(session, "Hello")
```

**New API (v0.9.0):**
```elixir
{:ok, session} = ExLLM.Session.new(:anthropic, %{
  model: "claude-3-sonnet"
})
{:ok, session, response} = ExLLM.Session.chat(session, "Hello")
```

### Provider/Model Syntax

**Old API (v0.8.x):**
```elixir
{:ok, response} = ExLLM.chat("anthropic/claude-3-haiku", "Hello")
```

**New API (v0.9.0):**
```elixir
# Still supported, but messages must be a list
messages = [%{role: "user", content: "Hello"}]
{:ok, response} = ExLLM.chat("anthropic/claude-3-haiku", messages)
```

## Using the New Builder API

The builder API is new in v0.9.0 and provides a fluent interface:

```elixir
# Old style (still works)
{:ok, response} = ExLLM.chat(:openai, messages, %{
  model: "gpt-4",
  temperature: 0.7,
  max_tokens: 1000
})

# New builder style (recommended)
{:ok, response} = 
  ExLLM.build(:openai)
  |> ExLLM.with_messages(messages)
  |> ExLLM.with_model("gpt-4")
  |> ExLLM.with_temperature(0.7)
  |> ExLLM.with_max_tokens(1000)
  |> ExLLM.execute()
```

## Custom Extensions

### Adding Authentication

**Old approach (v0.8.x):**
```elixir
# Had to modify adapter or use middleware
# Complex and not standardized
```

**New approach (v0.9.0):**
```elixir
defmodule MyApp.Plugs.CustomAuth do
  use ExLLM.Plug
  
  @impl true
  def call(request, _opts) do
    token = get_auth_token()
    
    request
    |> ExLLM.Pipeline.Request.assign(:auth_token, token)
    |> ExLLM.Pipeline.Request.put_in([:config, :api_key], token)
  end
end

# Use it
{:ok, response} =
  ExLLM.build(:openai)
  |> ExLLM.with_messages(messages)
  |> ExLLM.prepend_plug(MyApp.Plugs.CustomAuth)
  |> ExLLM.execute()
```

### Adding Rate Limiting

```elixir
defmodule MyApp.Plugs.RateLimiter do
  use ExLLM.Plug
  
  @impl true
  def call(request, opts) do
    if under_rate_limit?(request.provider) do
      request
    else
      ExLLM.Pipeline.Request.halt_with_error(request, %{
        plug: __MODULE__,
        error: :rate_limited,
        message: "Rate limit exceeded"
      })
    end
  end
end
```

## Direct Adapter Usage

**Old approach (v0.8.x):**
```elixir
# Direct adapter calls were possible
{:ok, response} = ExLLM.Adapters.OpenAI.chat(messages, config)
```

**New approach (v0.9.0):**
```elixir
# Use pipelines instead
request = ExLLM.Pipeline.Request.new(:openai, messages, config)
{:ok, response} = ExLLM.run(request)

# Or for complete control
custom_pipeline = [
  ExLLM.Plugs.ValidateProvider,
  ExLLM.Plugs.FetchConfig,
  # ... your custom plugs
]
{:ok, response} = ExLLM.run(request, custom_pipeline)
```

## Error Handling

Error handling remains similar but with more context:

**Old API (v0.8.x):**
```elixir
case ExLLM.chat(:openai, "Hello") do
  {:ok, response} -> response.content
  {:error, reason} -> handle_error(reason)
end
```

**New API (v0.9.0):**
```elixir
case ExLLM.chat(:openai, messages) do
  {:ok, response} -> 
    response.content
    
  {:error, %{plug: plug, error: error, message: message}} ->
    # Pipeline errors include which plug failed
    Logger.error("Pipeline error in #{plug}: #{error} - #{message}")
    
  {:error, reason} ->
    # Other errors
    handle_error(reason)
end
```

## Configuration Changes

### API Keys and Settings

Configuration remains largely the same:

```elixir
# Environment variables (unchanged)
export OPENAI_API_KEY="sk-..."

# Application config (unchanged)
config :ex_llm,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  default_model: "gpt-4"
```

### Custom Configuration

You can now inject configuration through plugs:

```elixir
defmodule MyApp.Plugs.ConfigOverride do
  use ExLLM.Plug
  
  @impl true
  def call(request, _opts) do
    custom_config = load_custom_config(request.provider)
    
    %{request | config: Map.merge(request.config, custom_config)}
  end
end
```

## Testing

### Mock Adapter

The mock adapter works the same but with pipeline support:

```elixir
# Old style still works
{:ok, response} = ExLLM.chat(:mock, messages, %{
  mock_response: "Test response"
})

# New pipeline style
pipeline = [
  ExLLM.Plugs.ValidateProvider,
  ExLLM.Plugs.FetchConfig,
  ExLLM.Plugs.Providers.MockHandler
]

request = ExLLM.Pipeline.Request.new(:mock, messages, %{
  mock_response: "Test response"
})

{:ok, response} = ExLLM.run(request, pipeline)
```

## Common Migration Patterns

### 1. Simple Chat Application

```elixir
# Old
defmodule MyApp.ChatBot do
  def ask(question) do
    {:ok, response} = ExLLM.chat(:openai, question)
    response.content
  end
end

# New
defmodule MyApp.ChatBot do
  def ask(question) do
    messages = [%{role: "user", content: question}]
    {:ok, response} = ExLLM.chat(:openai, messages)
    response.content
  end
end
```

### 2. Streaming Chat Interface

```elixir
# Old
defmodule MyApp.StreamingChat do
  def stream_response(prompt, callback) do
    ExLLM.stream_chat(:openai, prompt, callback)
  end
end

# New
defmodule MyApp.StreamingChat do
  def stream_response(prompt, callback) do
    messages = [%{role: "user", content: prompt}]
    ExLLM.stream(:openai, messages, %{stream: true}, callback)
  end
end
```

### 3. Custom Provider Integration

```elixir
# Old - Required creating a new adapter module
# New - Create a pipeline with custom plugs

defmodule MyApp.CustomProvider do
  def chat(messages, opts) do
    pipeline = [
      ExLLM.Plugs.ValidateProvider,
      MyApp.Plugs.CustomAuth,
      ExLLM.Plugs.FetchConfig,
      MyApp.Plugs.CustomPrepareRequest,
      ExLLM.Plugs.BuildTeslaClient,
      ExLLM.Plugs.ExecuteRequest,
      MyApp.Plugs.CustomParseResponse
    ]
    
    request = ExLLM.Pipeline.Request.new(:custom, messages, opts)
    ExLLM.run(request, pipeline)
  end
end
```

## Gradual Migration Strategy

1. **Update message format**: Ensure all calls use message lists
2. **Update streaming calls**: Switch to the new `stream/4` function
3. **Test thoroughly**: The high-level API is mostly compatible
4. **Adopt builder API**: Gradually move to the builder pattern
5. **Create custom plugs**: Replace any adapter customizations with plugs

## Need Help?

- Review the [Pipeline Architecture Guide](PIPELINE_ARCHITECTURE.md)
- Check the updated [API Reference](API_REFERENCE.md)
- See examples in the [User Guide](USER_GUIDE.md)

## Summary

The v0.9.0 release brings a more flexible and extensible architecture while maintaining ease of use. Most applications will only need minor updates to work with the new version. The pipeline architecture opens up new possibilities for customization and extension that were difficult or impossible in previous versions.