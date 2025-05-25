# ExLLM

A unified Elixir client for Large Language Models, providing a consistent interface across multiple LLM providers.

## Features

- **Unified API**: Single interface for multiple LLM providers
- **Streaming Support**: Real-time streaming responses via Server-Sent Events
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
# Simple chat completion
messages = [
  %{role: "user", content: "Hello, how are you?"}
]

{:ok, response} = ExLLM.chat(:anthropic, messages)
IO.puts(response.content)

# Streaming chat
ExLLM.stream_chat(:anthropic, messages, fn chunk ->
  IO.write(chunk.content)
end)
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
```

## API Reference

### Core Functions

- `chat/3` - Send messages and get a complete response
- `stream_chat/4` - Send messages and stream the response
- `configured?/1` - Check if a provider is properly configured
- `list_models/1` - Get available models for a provider

### Data Structures

#### LLMResponse

```elixir
%ExLLM.Types.LLMResponse{
  content: "Hello! I'm doing well, thank you for asking.",
  tokens_used: %{input: 12, output: 15},
  model: "claude-3-5-sonnet-20241022",
  finish_reason: "end_turn"
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

