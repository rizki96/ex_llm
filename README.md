# ExLLM

A unified Elixir client for Large Language Models with integrated cost tracking, providing a consistent interface across multiple LLM providers.

## Features

- **Unified API**: Single interface for multiple LLM providers
- **Streaming Support**: Real-time streaming responses via Server-Sent Events
- **Cost Tracking**: Automatic cost calculation for all API calls
- **Token Estimation**: Heuristic-based token counting for cost prediction
- **Context Management**: Automatic message truncation to fit model context windows
- **Configurable**: Flexible configuration system with multiple providers
- **Type Safety**: Comprehensive typespecs and structured data
- **Error Handling**: Consistent error patterns across all providers
- **Extensible**: Easy to add new LLM providers via adapter pattern

## Supported Providers

- **Anthropic Claude** (claude-3-5-sonnet-20241022, claude-3-5-haiku-20241022, etc.)
- **OpenAI** (coming soon)
- **Ollama** (coming soon)

## Installation

Add `ex_llm` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Configuration

Configure your LLM providers in `config/config.exs`:

```elixir
config :ex_llm,
  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY"),
    base_url: "https://api.anthropic.com"
  ]
```

### Basic Usage

```elixir
# Simple chat completion with automatic cost tracking
messages = [
  %{role: "user", content: "Hello, how are you?"}
]

{:ok, response} = ExLLM.chat(:anthropic, messages)
IO.puts(response.content)
IO.puts("Cost: #{ExLLM.format_cost(response.cost.total_cost)}")

# Streaming chat
ExLLM.stream_chat(:anthropic, messages, fn chunk ->
  IO.write(chunk.content)
end)

# Estimate tokens before making a request
tokens = ExLLM.estimate_tokens(messages)
IO.puts("Estimated tokens: #{tokens}")

# Calculate cost for specific usage
usage = %{input_tokens: 1000, output_tokens: 500}
cost = ExLLM.calculate_cost(:openai, "gpt-4", usage)
IO.puts("Total cost: #{ExLLM.format_cost(cost.total_cost)}")
```

### Advanced Usage

```elixir
# With custom options
options = [
  model: "claude-3-5-sonnet-20241022",
  max_tokens: 1000,
  temperature: 0.7
]

{:ok, response} = ExLLM.chat(:anthropic, messages, options)

# Check provider configuration
case ExLLM.configured?(:anthropic) do
  true -> IO.puts("Anthropic is ready!")
  false -> IO.puts("Please configure Anthropic API key")
end

# List available models
{:ok, models} = ExLLM.list_models(:anthropic)
Enum.each(models, &IO.puts(&1.name))

# Context management - automatically truncate long conversations
long_conversation = [
  %{role: "system", content: "You are a helpful assistant."},
  # ... many messages ...
  %{role: "user", content: "What's the weather?"}
]

# Automatically truncates to fit model's context window
{:ok, response} = ExLLM.chat(:anthropic, long_conversation,
  max_tokens: 4000,        # Max tokens for context
  strategy: :smart         # Preserve system messages and recent context
)
```

## API Reference

### Core Functions

- `chat/3` - Send messages and get a complete response
- `stream_chat/3` - Send messages and stream the response
- `configured?/2` - Check if a provider is properly configured
- `list_models/2` - Get available models for a provider
- `prepare_messages/2` - Prepare messages for context window
- `validate_context/2` - Validate messages fit within context window
- `context_window_size/2` - Get context window size for a model
- `context_stats/1` - Get statistics about message context usage

### Data Structures

#### LLMResponse

```elixir
%ExLLM.Types.LLMResponse{
  content: "Hello! I'm doing well, thank you for asking.",
  usage: %{input_tokens: 12, output_tokens: 15},
  model: "claude-3-5-sonnet-20241022",
  finish_reason: "end_turn",
  cost: %{
    total_cost: 0.000261,
    input_cost: 0.000036,
    output_cost: 0.000225,
    currency: "USD"
  }
}
```

#### StreamChunk

```elixir
%ExLLM.Types.StreamChunk{
  content: "Hello",
  delta: true,
  finish_reason: nil
}
```

#### Model

```elixir
%ExLLM.Types.Model{
  name: "claude-3-5-sonnet-20241022",
  provider: :anthropic,
  context_length: 200000,
  supports_streaming: true
}
```

## Cost Tracking

ExLLM automatically tracks costs for all API calls when usage data is available:

### Automatic Cost Calculation

```elixir
{:ok, response} = ExLLM.chat(:anthropic, messages)

# Access cost information
if response.cost do
  IO.puts("Input tokens: #{response.cost.input_tokens}")
  IO.puts("Output tokens: #{response.cost.output_tokens}") 
  IO.puts("Total cost: #{ExLLM.format_cost(response.cost.total_cost)}")
end
```

### Token Estimation

```elixir
# Estimate tokens before making a request
messages = [
  %{role: "system", content: "You are a helpful assistant."},
  %{role: "user", content: "Explain quantum computing in simple terms."}
]

estimated_tokens = ExLLM.estimate_tokens(messages)
# Use this to predict costs before making the actual API call
```

### Cost Comparison

```elixir
# Compare costs across different providers
usage = %{input_tokens: 1000, output_tokens: 2000}

providers = [
  {:openai, "gpt-4"},
  {:openai, "gpt-3.5-turbo"},
  {:anthropic, "claude-3-5-sonnet-20241022"},
  {:anthropic, "claude-3-haiku-20240307"}
]

Enum.each(providers, fn {provider, model} ->
  cost = ExLLM.calculate_cost(provider, model, usage)
  unless cost[:error] do
    IO.puts("#{provider}/#{model}: #{ExLLM.format_cost(cost.total_cost)}")
  end
end)
```

### Supported Pricing

ExLLM includes up-to-date pricing (as of January 2025) for:
- OpenAI: GPT-4, GPT-4 Turbo, GPT-3.5 Turbo, GPT-4o series
- Anthropic: Claude 3 series (Opus, Sonnet, Haiku), Claude 3.5, Claude 4
- Google Gemini: Pro, Ultra, Nano
- AWS Bedrock: Various models including Claude, Titan, Llama 2
- Ollama: Local models (free - $0.00)

## Context Management

ExLLM automatically manages context windows to ensure your messages fit within model limits:

### Automatic Context Truncation

```elixir
# Long conversation that might exceed context window
messages = [
  %{role: "system", content: "You are a helpful assistant."},
  # ... hundreds of messages ...
  %{role: "user", content: "What's my current task?"}
]

# ExLLM automatically truncates to fit the model's context window
{:ok, response} = ExLLM.chat(:anthropic, messages)
```

### Context Window Validation

```elixir
# Check if messages fit within context window
case ExLLM.validate_context(messages, model: "gpt-3.5-turbo") do
  {:ok, token_count} ->
    IO.puts("Messages use #{token_count} tokens")
  {:error, {:context_too_large, %{tokens: tokens, max_tokens: max}}} ->
    IO.puts("Messages too large: #{tokens} tokens (max: #{max})")
end
```

### Context Strategies

```elixir
# Sliding window (default) - keeps most recent messages
{:ok, response} = ExLLM.chat(:anthropic, messages,
  max_tokens: 4000,
  strategy: :sliding_window
)

# Smart strategy - preserves system messages and recent context
{:ok, response} = ExLLM.chat(:anthropic, messages,
  max_tokens: 4000,
  strategy: :smart,
  preserve_messages: 10  # Always keep last 10 messages
)
```

### Context Statistics

```elixir
# Get detailed statistics about your messages
stats = ExLLM.context_stats(messages)
IO.inspect(stats)
# %{
#   message_count: 150,
#   total_tokens: 45000,
#   by_role: %{"system" => 1, "user" => 75, "assistant" => 74},
#   avg_tokens_per_message: 300
# }

# Check context window sizes
IO.puts(ExLLM.context_window_size(:anthropic, "claude-3-5-sonnet-20241022"))
# => 200000
```

## Configuration

ExLLM supports multiple configuration providers:

### Environment Variables (Default)

```elixir
# Uses ExLLM.ConfigProvider.Default
# Reads from application config and environment variables
```

### Static Configuration

```elixir
config = %{
  anthropic: [
    api_key: "your-api-key",
    base_url: "https://api.anthropic.com"
  ]
}

ExLLM.set_config_provider({ExLLM.ConfigProvider.Static, config})
```

### Custom Configuration Provider

```elixir
defmodule MyConfigProvider do
  @behaviour ExLLM.ConfigProvider

  @impl true
  def get_config(provider, key) do
    # Your custom logic here
  end

  @impl true
  def has_config?(provider) do
    # Your custom logic here
  end
end

ExLLM.set_config_provider(MyConfigProvider)
```

## Error Handling

ExLLM uses consistent error patterns:

```elixir
case ExLLM.chat(:anthropic, messages) do
  {:ok, response} ->
    # Success
    IO.puts(response.content)

  {:error, {:config_error, reason}} ->
    # Configuration issue
    IO.puts("Config error: #{reason}")

  {:error, {:api_error, %{status: status, body: body}}} ->
    # API error
    IO.puts("API error #{status}: #{body}")

  {:error, {:network_error, reason}} ->
    # Network issue
    IO.puts("Network error: #{reason}")

  {:error, {:parse_error, reason}} ->
    # Response parsing issue
    IO.puts("Parse error: #{reason}")
end
```

## Adding New Providers

To add a new LLM provider, implement the `ExLLM.Adapter` behaviour:

```elixir
defmodule ExLLM.Adapters.MyProvider do
  @behaviour ExLLM.Adapter

  @impl true
  def chat(messages, options) do
    # Implement chat completion
  end

  @impl true
  def stream_chat(messages, options, callback) do
    # Implement streaming chat
  end

  @impl true
  def configured?() do
    # Check if provider is configured
  end

  @impl true
  def list_models() do
    # Return available models
  end
end
```

Then register it in the main ExLLM module.

## Testing

Run the test suite:

```bash
mix test
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run `mix format` and `mix credo`
6. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

