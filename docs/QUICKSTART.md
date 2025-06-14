# ExLLM Quick Start Guide

Get up and running with ExLLM in 5 minutes! This guide covers installation, basic configuration, and common usage patterns.

## Installation

Add ExLLM to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.7.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Configuration

### Environment Variables

Set API keys for the providers you want to use:

```bash
# Core providers
export ANTHROPIC_API_KEY="sk-ant-your-key"
export OPENAI_API_KEY="sk-your-key"
export GROQ_API_KEY="gsk_your-key"

# Additional providers (optional)
export GEMINI_API_KEY="your-gemini-key"
export MISTRAL_API_KEY="your-mistral-key"
export OPENROUTER_API_KEY="sk-or-your-key"
export PERPLEXITY_API_KEY="pplx-your-key"
```

### Application Configuration (Optional)

```elixir
# config/config.exs
config :ex_llm,
  # Default provider
  default_provider: :anthropic,
  
  # Cost tracking
  cost_tracking_enabled: true,
  
  # Test caching (speeds up tests 25x)
  test_cache: [
    enabled: true,
    cache_dir: "test/cache",
    ttl: 604_800_000  # 7 days in milliseconds
  ]
```

## Basic Usage

### Simple Chat Completion

```elixir
# Start with a basic chat
{:ok, response} = ExLLM.chat(:anthropic, [
  %{role: "user", content: "What is the capital of France?"}
])

IO.puts(response.content)
# => "The capital of France is Paris."

# Access additional metadata
IO.puts("Model: #{response.model}")
IO.puts("Cost: $#{response.cost}")
IO.puts("Tokens used: #{response.usage.total_tokens}")
```

### Different Providers

```elixir
# Try different providers
{:ok, response1} = ExLLM.chat(:openai, [
  %{role: "user", content: "Explain quantum computing briefly"}
])

{:ok, response2} = ExLLM.chat(:groq, [
  %{role: "user", content: "Write a haiku about coding"}
])

{:ok, response3} = ExLLM.chat(:gemini, [
  %{role: "user", content: "What's 2+2?"}
])
```

### Streaming Responses

```elixir
# Stream responses in real-time
ExLLM.chat_stream(:openai, [
  %{role: "user", content: "Write a short story about a robot"}
], fn chunk ->
  IO.write(chunk.delta)
end)
```

### Session Management

```elixir
# Maintain conversation context
{:ok, session} = ExLLM.Session.new(:anthropic)

# First message
{:ok, session, response1} = ExLLM.Session.chat(session, "Hi, I'm learning Elixir")
IO.puts(response1.content)

# Continue the conversation
{:ok, session, response2} = ExLLM.Session.chat(session, "What are GenServers?")
IO.puts(response2.content)

# Session automatically tracks conversation history
IO.puts("Messages in session: #{length(session.messages)}")
IO.puts("Total cost: $#{session.total_cost}")
```

## Advanced Features

### Multimodal (Vision)

```elixir
# Analyze images (with Gemini or OpenAI)
image_data = File.read!("image.jpg") |> Base.encode64()

{:ok, response} = ExLLM.chat(:gemini, [
  %{role: "user", content: [
    %{type: "text", text: "What's in this image?"},
    %{type: "image", image: %{
      data: image_data,
      media_type: "image/jpeg"
    }}
  ]}
])

IO.puts(response.content)
```

### Function Calling

```elixir
# Define tools
tools = [
  %{
    type: "function",
    function: %{
      name: "get_weather",
      description: "Get current weather for a location",
      parameters: %{
        type: "object",
        properties: %{
          location: %{type: "string", description: "City name"},
          unit: %{type: "string", enum: ["celsius", "fahrenheit"]}
        },
        required: ["location"]
      }
    }
  }
]

{:ok, response} = ExLLM.chat(:openai, [
  %{role: "user", content: "What's the weather in Paris?"}
], tools: tools)

# Handle function calls
case response.function_calls do
  [%{name: "get_weather", arguments: args}] ->
    # Call your weather API here
    weather_data = get_weather(args["location"])
    
    # Continue conversation with function result
    {:ok, final_response} = ExLLM.chat(:openai, [
      %{role: "user", content: "What's the weather in Paris?"},
      response.message,
      %{role: "function", name: "get_weather", content: Jason.encode!(weather_data)}
    ])
    
  _ ->
    IO.puts(response.content)
end
```

### Model Discovery

```elixir
# List available models
{:ok, models} = ExLLM.list_models(:anthropic)

Enum.each(models, fn model ->
  IO.puts("#{model.id} - Context: #{model.context_window} tokens")
end)

# Get specific model info
{:ok, model} = ExLLM.get_model(:openai, "gpt-4o")
IO.puts("Supports streaming: #{model.capabilities.supports_streaming}")
IO.puts("Supports vision: #{model.capabilities.supports_vision}")
```

## Testing

### Fast Testing with Caching

ExLLM includes intelligent test caching for 25x faster integration tests:

```bash
# Run tests with automatic caching
mix test

# Test specific providers
mix test.anthropic
mix test.openai --include live_api

# Manage cache
mix ex_llm.cache stats
mix ex_llm.cache clean --older-than 7d
```

### Writing Tests

```elixir
defmodule MyAppTest do
  use ExUnit.Case
  
  # Tag for automatic caching
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag provider: :anthropic
  
  test "chat completion works" do
    {:ok, response} = ExLLM.chat(:anthropic, [
      %{role: "user", content: "Say hello"}
    ])
    
    assert response.content =~ "hello"
    assert response.cost > 0
  end
end
```

## Local Models

### Ollama

```bash
# Start Ollama
ollama serve

# Pull a model
ollama pull llama3.2
```

```elixir
# Use local Ollama models
{:ok, response} = ExLLM.chat(:ollama, [
  %{role: "user", content: "Hello!"}
], model: "llama3.2")
```

### LM Studio

```bash
# Start LM Studio server on localhost:1234
```

```elixir
# Use LM Studio models
{:ok, response} = ExLLM.chat(:lmstudio, [
  %{role: "user", content: "Hello!"}
])
```

### Bumblebee (Elixir Native)

```elixir
# Add to deps for local inference
{:exla, "~> 0.7"}  # For CPU/GPU acceleration

# Use Bumblebee models
{:ok, response} = ExLLM.chat(:bumblebee, [
  %{role: "user", content: "Hello!"}
], model: "microsoft/DialoGPT-medium")
```

## Error Handling

```elixir
case ExLLM.chat(:anthropic, messages) do
  {:ok, response} ->
    IO.puts(response.content)
    
  {:error, {:api_error, %{status: 401}}} ->
    IO.puts("Invalid API key")
    
  {:error, {:api_error, %{status: 429}}} ->
    IO.puts("Rate limited - try again later")
    
  {:error, {:api_error, %{status: 400, body: body}}} ->
    IO.puts("Bad request: #{inspect(body)}")
    
  {:error, {:network_error, reason}} ->
    IO.puts("Network error: #{reason}")
    
  {:error, reason} ->
    IO.puts("Other error: #{inspect(reason)}")
end
```

## Environment-Specific Configuration

### Development

```elixir
# config/dev.exs
config :ex_llm,
  log_level: :debug,
  log_components: [:http_client, :streaming],
  test_cache: [enabled: true]
```

### Test

```elixir
# config/test.exs
config :ex_llm,
  log_level: :warn,
  test_cache: [
    enabled: true,
    cache_dir: "test/cache",
    ttl: 604_800_000  # 7 days
  ]
```

### Production

```elixir
# config/prod.exs
config :ex_llm,
  log_level: :info,
  log_redaction: true,
  cost_tracking_enabled: true
```

## Next Steps

1. **Read the [User Guide](USER_GUIDE.md)** for comprehensive documentation
2. **Check [Provider Capabilities](PROVIDER_CAPABILITIES.md)** to compare features
3. **Review [Testing Guide](TESTING.md)** for advanced testing patterns
4. **Explore [Test Caching](test_caching.md)** for development speedups

## Common Issues

### "API key not found"
```bash
# Make sure you've set the environment variable
export ANTHROPIC_API_KEY="your-key"
```

### "Model not found"
```elixir
# Check available models
{:ok, models} = ExLLM.list_models(:anthropic)
```

### "Rate limited"
```elixir
# Use different providers or implement backoff
Process.sleep(1000)
{:ok, response} = ExLLM.chat(:groq, messages)  # Try Groq for speed
```

### Tests running slowly
```bash
# Enable test caching
export EX_LLM_TEST_CACHE_ENABLED=true
mix test --include live_api
```

That's it! You're now ready to build amazing applications with ExLLM. 🚀