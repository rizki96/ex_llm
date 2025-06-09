# ExLLM Quick Start Guide

This guide covers the most common ExLLM use cases to get you up and running quickly.

## Installation

Add ExLLM to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.4.1"}
  ]
end
```

Run `mix deps.get` to install.

## Configuration

### Using Environment Variables (Recommended)

```bash
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GROQ_API_KEY="gsk_..."
export MISTRAL_API_KEY="..."
export PERPLEXITY_API_KEY="pplx-..."
export XAI_API_KEY="xai-..."
```

### Using Static Configuration

```elixir
config = %{
  openai: %{api_key: "sk-..."},
  anthropic: %{api_key: "claude-..."}
}

{:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
```

## Basic Chat

### Simple Question/Answer

```elixir
# Using OpenAI
{:ok, response} = ExLLM.chat(:openai, [
  %{role: "user", content: "What is the capital of France?"}
])

IO.puts(response.content)
# => "The capital of France is Paris."
```

### Using Different Providers

```elixir
# Anthropic Claude
{:ok, response} = ExLLM.chat(:anthropic, messages)

# Groq (fast inference)
{:ok, response} = ExLLM.chat(:groq, messages)

# Mistral AI
{:ok, response} = ExLLM.chat(:mistral, messages)

# Perplexity (search-enhanced)
{:ok, response} = ExLLM.chat(:perplexity, messages)

# Ollama (local)
{:ok, response} = ExLLM.chat(:ollama, messages)

# LM Studio (local)
{:ok, response} = ExLLM.chat(:lmstudio, messages)

# Using provider/model syntax
{:ok, response} = ExLLM.chat("groq/llama-3.3-70b-versatile", messages)
```

## Common Options

### Temperature and Max Tokens

```elixir
{:ok, response} = ExLLM.chat(:openai, messages,
  temperature: 0.7,      # 0.0 = deterministic, 1.0 = creative
  max_tokens: 1000       # Maximum response length
)
```

### Choosing a Specific Model

```elixir
{:ok, response} = ExLLM.chat(:openai, messages,
  model: "gpt-4o-mini"  # Use a specific model
)
```

## Streaming Responses

Get responses as they're generated:

```elixir
{:ok, stream} = ExLLM.stream_chat(:openai, messages)

for chunk <- stream do
  # Print each chunk as it arrives
  if chunk.content, do: IO.write(chunk.content)
end
```

## Multi-turn Conversations

### Using Sessions

```elixir
# Create a session
session = ExLLM.new_session(:openai)

# First message
{:ok, {response1, session}} = ExLLM.chat_with_session(
  session, 
  "What's the weather like in Paris?"
)

# Follow-up (context is maintained)
{:ok, {response2, session}} = ExLLM.chat_with_session(
  session,
  "What about London?"
)

# Session tracks token usage
total_tokens = ExLLM.session_token_usage(session)
```

### Manual Message Management

```elixir
messages = [
  %{role: "system", content: "You are a helpful assistant."},
  %{role: "user", content: "Hello!"},
  %{role: "assistant", content: "Hi! How can I help you today?"},
  %{role: "user", content: "What's the weather?"}
]

{:ok, response} = ExLLM.chat(:openai, messages)
```

## Working with Images (Vision)

```elixir
# Create a vision message
{:ok, message} = ExLLM.vision_message(
  "What's in this image?",
  ["path/to/image.jpg"]
)

# Send to a vision-capable model
{:ok, response} = ExLLM.chat(:openai, [message],
  model: "gpt-4o"  # Vision-capable model
)
```

## Function Calling

Define tools the AI can use:

```elixir
functions = [
  %{
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
]

messages = [
  %{role: "user", content: "What's the weather in New York?"}
]

{:ok, response} = ExLLM.chat(:openai, messages,
  functions: functions,
  function_call: "auto"
)

# Check if the AI wants to call a function
case ExLLM.parse_function_calls(response, :openai) do
  {:ok, [function_call | _]} ->
    # AI wants to call get_weather with location: "New York"
    IO.inspect(function_call)
    
  {:ok, []} ->
    # Regular response, no function call
    IO.puts(response.content)
end
```

## Cost Tracking

ExLLM automatically tracks costs for all API calls:

```elixir
{:ok, response} = ExLLM.chat(:openai, messages)

# Cost information is included in the response
IO.inspect(response.cost)
# => %{
#      total_cost: 0.000261,
#      input_cost: 0.000036, 
#      output_cost: 0.000225,
#      currency: "USD"
#    }

# Format for display
IO.puts(ExLLM.format_cost(response.cost.total_cost))
# => "$0.026¢"
```

## Error Handling

```elixir
case ExLLM.chat(:openai, messages) do
  {:ok, response} ->
    IO.puts(response.content)
    
  {:error, %{type: :rate_limit}} ->
    IO.puts("Rate limit hit, please wait")
    
  {:error, %{type: :invalid_api_key}} ->
    IO.puts("Check your API key")
    
  {:error, error} ->
    IO.inspect(error)
end
```

## Response Caching (New!)

Cache provider responses for testing and development:

```elixir
# Enable response caching
export EX_LLM_CACHE_RESPONSES=true

# Make API calls - they'll be cached automatically
{:ok, response} = ExLLM.chat(:openai, messages)

# Later, use cached responses with mock adapter
ExLLM.ResponseCache.configure_mock_provider("openai")
{:ok, cached_response} = ExLLM.chat(:mock, messages)
# Returns the same response without making an API call!
```

## Finding the Right Model

### Check Provider Capabilities

```elixir
# Check if a provider supports a feature
if ExLLM.provider_supports?(:openai, :embeddings) do
  # OpenAI supports embeddings
end

# Find providers with specific features
providers = ExLLM.find_providers_with_features([:vision, :streaming])
# => [:openai, :anthropic, :gemini]
```

### Get Model Recommendations

```elixir
# Find best models for your needs
recommendations = ExLLM.recommend_models(
  features: [:vision, :function_calling],
  max_cost_per_1k_tokens: 1.0,
  min_context_window: 100_000
)

# Returns models sorted by suitability
for {provider, model, info} <- Enum.take(recommendations, 3) do
  IO.puts("#{provider}: #{model} (score: #{info.score})")
end
```

## Common Patterns

### Retry on Error

```elixir
# Automatic retry is enabled by default
{:ok, response} = ExLLM.chat(:openai, messages,
  retry: true,
  retry_count: 3,
  retry_delay: 1000  # Start with 1 second delay
)
```

### Using Local Models with Ollama

```elixir
# Make sure Ollama is running: ollama serve

# List available models
{:ok, models} = ExLLM.list_models(:ollama)

# Use a local model
{:ok, response} = ExLLM.chat(:ollama, messages,
  model: "llama3.2:3b"
)
```

### Working with JSON Responses

```elixir
{:ok, response} = ExLLM.chat(:openai, [
  %{role: "system", content: "Always respond with valid JSON"},
  %{role: "user", content: "List 3 colors with their hex codes"}
], json_mode: true)

# Parse the JSON response
{:ok, data} = Jason.decode(response.content)
```

## Next Steps

- Read the [User Guide](USER_GUIDE.md) for comprehensive documentation
- Explore the [example app](../examples/example_app.exs) for interactive demos
- Check the [API Reference](https://hexdocs.pm/ex_llm) for detailed function documentation
- See [Provider Capabilities](PROVIDER_CAPABILITIES.md) for provider-specific features