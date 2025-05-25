# ExLLM

A unified Elixir client for Large Language Models with integrated cost tracking, providing a consistent interface across multiple LLM providers.

> ⚠️ **Alpha Quality Software**: This library is in early development. APIs may change without notice until version 1.0.0 is released. Use in production at your own risk.

## Features

- **Unified API**: Single interface for multiple LLM providers
- **Streaming Support**: Real-time streaming responses via Server-Sent Events
- **Cost Tracking**: Automatic cost calculation for all API calls
- **Token Estimation**: Heuristic-based token counting for cost prediction
- **Context Management**: Automatic message truncation to fit model context windows
- **Session Management**: Built-in conversation state tracking and persistence
- **Structured Outputs**: Schema validation and retries via instructor_ex integration
- **Configurable**: Flexible configuration system with multiple providers
- **Type Safety**: Comprehensive typespecs and structured data
- **Error Handling**: Consistent error patterns across all providers
- **Extensible**: Easy to add new LLM providers via adapter pattern

## Supported Providers

- **Anthropic Claude** - Full support for all Claude models
  - claude-3-5-sonnet-20241022
  - claude-3-5-haiku-20241022
  - claude-3-opus-20240229
  - claude-3-sonnet-20240229
  - claude-3-haiku-20240307
  - claude-sonnet-4-20250514

- **OpenAI** - GPT-4 and GPT-3.5 models
  - gpt-4-turbo
  - gpt-4
  - gpt-4-32k
  - gpt-3.5-turbo
  - gpt-3.5-turbo-16k

- **Ollama** - Local model runner
  - Any model available in your Ollama installation
  - Automatic model discovery
  - No API costs

- **AWS Bedrock** - Multi-provider access with comprehensive model support
  - **Anthropic Claude**: All Claude 4, 3.7, 3.5, 3, and 2.x models
  - **Amazon Nova**: Micro, Lite (default), Pro, Premier
  - **Amazon Titan**: Lite, Express text models
  - **Meta Llama**: Llama 4 (Maverick, Scout), Llama 3.3, 3.2, and 2 series
  - **Cohere**: Command, Command Light, Command R, Command R+
  - **AI21 Labs**: Jamba 1.5 (Large, Mini), Jamba Instruct, Jurassic 2
  - **Mistral**: Pixtral Large 2025-02, Mistral 7B, Mixtral 8x7B
  - **Writer**: Palmyra X4, Palmyra X5
  - **DeepSeek**: DeepSeek R1

- **Google Gemini** - Gemini models
  - gemini-pro
  - gemini-pro-vision
  - gemini-ultra
  - gemini-nano

- **Local Models** via Bumblebee/EXLA
  - microsoft/phi-2 (default)
  - meta-llama/Llama-2-7b-hf
  - mistralai/Mistral-7B-v0.1
  - EleutherAI/gpt-neo-1.3B
  - google/flan-t5-base

## Installation

Add `ex_llm` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.2.0"},
    
    # Optional: For local model support
    {:bumblebee, "~> 0.5", optional: true},
    {:nx, "~> 0.7", optional: true},
    {:exla, "~> 0.7", optional: true}
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
  ],
  bedrock: [
    # AWS credentials (optional - uses credential chain by default)
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
    region: System.get_env("AWS_REGION") || "us-east-1",
    model: "nova-lite"  # Default model (cost-effective)
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

# Using local models (no API costs!)
{:ok, response} = ExLLM.chat(:local, messages, model: "microsoft/phi-2")
IO.puts(response.content)

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

### Session Management

```elixir
# Create a new conversation session
session = ExLLM.new_session(:anthropic, name: "Customer Support")

# Chat with automatic session tracking
{:ok, {response, session}} = ExLLM.chat_with_session(session, "Hello!")
IO.puts(response.content)

# Continue the conversation
{:ok, {response, session}} = ExLLM.chat_with_session(session, "What can you help me with?")

# Session automatically tracks:
# - Message history
# - Token usage
# - Conversation context

# Review session details
messages = ExLLM.get_session_messages(session)
total_tokens = ExLLM.session_token_usage(session)
IO.puts("Total tokens used: #{total_tokens}")

# Save session for later
{:ok, json} = ExLLM.save_session(session)
File.write!("session.json", json)

# Load session later
{:ok, session} = ExLLM.load_session(File.read!("session.json"))
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

### Session Functions

- `new_session/2` - Create a new conversation session
- `chat_with_session/3` - Chat with automatic session tracking
- `add_session_message/4` - Add a message to a session
- `get_session_messages/2` - Retrieve messages from a session
- `session_token_usage/1` - Get total token usage for a session
- `clear_session/1` - Clear messages while preserving metadata
- `save_session/1` - Serialize session to JSON
- `load_session/1` - Load session from JSON

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

ExLLM includes pricing data (as of January 2025) for all supported providers:
- **Anthropic**: Claude 3 series (Opus, Sonnet, Haiku), Claude 3.5, Claude 4
- **OpenAI**: GPT-4, GPT-4 Turbo, GPT-3.5 Turbo, GPT-4o series
- **Google Gemini**: Pro, Ultra, Nano
- **AWS Bedrock**: Various models including Claude, Titan, Llama 2
- **Ollama**: Local models (free - $0.00)
- **Local Models**: Free ($0.00) - no API costs

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

## Session Management

ExLLM includes built-in session management for maintaining conversation state:

### Creating and Using Sessions

```elixir
# Create a new session
session = ExLLM.new_session(:anthropic, name: "My Chat")

# Chat with automatic session tracking
{:ok, {response, updated_session}} = ExLLM.chat_with_session(session, "Hello!")

# Continue the conversation
{:ok, {response2, session2}} = ExLLM.chat_with_session(updated_session, "What's 2+2?")

# Access session messages
messages = ExLLM.get_session_messages(session2)
# => [%{role: "user", content: "Hello!"}, %{role: "assistant", content: "..."}, ...]
```

### Session Persistence

```elixir
# Save session to disk
{:ok, path} = ExLLM.save_session(session, "/path/to/sessions")

# Load session from disk
{:ok, loaded_session} = ExLLM.load_session("/path/to/sessions/session_id.json")

# Export session as markdown
{:ok, markdown} = ExLLM.export_session_markdown(session)
File.write!("conversation.md", markdown)
```

### Session Information

```elixir
# Get session metadata
info = ExLLM.session_info(session)
# => %{
#   id: "123...",
#   name: "My Chat",
#   created_at: ~U[2025-01-24 10:00:00Z],
#   message_count: 10,
#   total_tokens: 1500
# }

# Get token usage for session
tokens = ExLLM.session_token_usage(session)
# => 1500

# Clear session messages
clean_session = ExLLM.clear_session(session)
```

## Structured Outputs

ExLLM integrates with [instructor_ex](https://github.com/thmsmlr/instructor_ex) to provide structured output validation. This allows you to define expected response structures using Ecto schemas and automatically validate LLM responses.

### Installation

Add the optional instructor dependency:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.2.0"},
    {:instructor, "~> 0.1.0"}  # Optional: for structured outputs
  ]
end
```

### Basic Usage

```elixir
# Define your schema
defmodule EmailClassification do
  use Ecto.Schema
  use Instructor.Validator

  @llm_doc "Classification of an email as spam or not spam"
  
  @primary_key false
  embedded_schema do
    field :classification, Ecto.Enum, values: [:spam, :not_spam]
    field :confidence, :float
    field :reason, :string
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:classification, :confidence, :reason])
    |> Ecto.Changeset.validate_number(:confidence, 
        greater_than_or_equal_to: 0.0,
        less_than_or_equal_to: 1.0
      )
  end
end

# Use with ExLLM
messages = [%{role: "user", content: "Is this spam? 'You won a million dollars!'"}]

{:ok, result} = ExLLM.chat(:anthropic, messages,
  response_model: EmailClassification,
  max_retries: 3  # Automatically retry on validation errors
)

IO.inspect(result)
# %EmailClassification{
#   classification: :spam,
#   confidence: 0.95,
#   reason: "Classic lottery scam pattern"
# }
```

### With Simple Type Specifications

```elixir
# Define expected structure without Ecto
response_model = %{
  name: :string,
  age: :integer,
  email: :string,
  tags: {:array, :string}
}

messages = [%{role: "user", content: "Extract: John Doe, 30 years old, john@example.com, likes elixir and coding"}]

{:ok, result} = ExLLM.chat(:anthropic, messages,
  response_model: response_model
)

IO.inspect(result)
# %{
#   name: "John Doe",
#   age: 30,
#   email: "john@example.com",
#   tags: ["elixir", "coding"]
# }
```

### Advanced Example

```elixir
defmodule UserProfile do
  use Ecto.Schema
  use Instructor.Validator

  @llm_doc """
  User profile extraction from text.
  Extract all available information about the user.
  """

  embedded_schema do
    field :name, :string
    field :email, :string
    field :age, :integer
    field :location, :string
    embeds_many :interests, Interest do
      field :name, :string
      field :level, Ecto.Enum, values: [:beginner, :intermediate, :expert]
    end
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:name])
    |> Ecto.Changeset.validate_format(:email, ~r/@/)
    |> Ecto.Changeset.validate_number(:age, greater_than: 0, less_than: 150)
  end
end

# Complex extraction with nested structures
text = """
Hi, I'm Jane Smith, a 28-year-old software engineer from Seattle.
You can reach me at jane.smith@tech.com. I'm an expert in Elixir,
intermediate in Python, and just starting to learn Rust.
"""

{:ok, profile} = ExLLM.chat(:anthropic, 
  [%{role: "user", content: "Extract user profile: #{text}"}],
  response_model: UserProfile,
  max_retries: 3
)
```

### Using the Instructor Module Directly

```elixir
# Direct usage of ExLLM.Instructor
{:ok, result} = ExLLM.Instructor.chat(:anthropic, messages,
  response_model: EmailClassification,
  max_retries: 3,
  temperature: 0.1  # Lower temperature for more consistent structure
)

# Parse an existing response
{:ok, response} = ExLLM.chat(:anthropic, messages)
{:ok, structured} = ExLLM.Instructor.parse_response(response, UserProfile)

# Check if instructor is available
if ExLLM.Instructor.available?() do
  # Use structured outputs
else
  # Fall back to regular parsing
end
```

### Supported Providers

Structured outputs work with providers that have instructor adapters:
- `:anthropic` - Anthropic Claude
- `:openai` - OpenAI GPT models
- `:ollama` - Local Ollama models
- `:gemini` - Google Gemini
- `:bedrock` - AWS Bedrock models
- `:local` - Local Bumblebee models

### Error Handling

```elixir
case ExLLM.chat(:anthropic, messages, response_model: UserProfile) do
  {:ok, profile} ->
    # Successfully validated structure
    IO.inspect(profile)
    
  {:error, :instructor_not_available} ->
    # Instructor library not installed
    IO.puts("Please install instructor to use structured outputs")
    
  {:error, {:validation_failed, errors}} ->
    # Validation failed after retries
    IO.inspect(errors)
    
  {:error, reason} ->
    # Other error
    IO.inspect(reason)
end
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

## Local Model Support

ExLLM supports running models locally using Bumblebee and EXLA/EMLX backends. This enables on-device inference without API calls or costs.

### Setup

1. Add optional dependencies to your `mix.exs`:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.2.0"},
    {:bumblebee, "~> 0.5"},
    {:nx, "~> 0.7"},
    {:exla, "~> 0.7"}  # or {:emlx, "~> 0.1"} for Apple Silicon
  ]
end
```

2. Configure EXLA backend (optional - auto-detected by default):

```elixir
# For CUDA GPUs
config :nx, :default_backend, {EXLA.Backend, client: :cuda}

# For Apple Silicon
config :nx, :default_backend, EMLX.Backend
```

### Available Models

- **microsoft/phi-2** - Phi-2 (2.7B parameters) - Default
- **meta-llama/Llama-2-7b-hf** - Llama 2 (7B)
- **mistralai/Mistral-7B-v0.1** - Mistral (7B)
- **EleutherAI/gpt-neo-1.3B** - GPT-Neo (1.3B)
- **google/flan-t5-base** - Flan-T5 Base

### Usage

```elixir
# Start the model loader (happens automatically on first use)
{:ok, _} = ExLLM.Local.ModelLoader.start_link()

# Use a local model
messages = [
  %{role: "user", content: "Explain quantum computing in simple terms"}
]

{:ok, response} = ExLLM.chat(:local, messages, model: "microsoft/phi-2")
IO.puts(response.content)

# Stream responses
{:ok, stream} = ExLLM.stream_chat(:local, messages)
for chunk <- stream do
  IO.write(chunk.content)
end

# List available models
{:ok, models} = ExLLM.list_models(:local)
Enum.each(models, fn model ->
  IO.puts("#{model.name} - Context: #{model.context_window} tokens")
end)

# Check acceleration info
info = ExLLM.Local.EXLAConfig.acceleration_info()
IO.puts("Running on: #{info.name}")
```

### Hardware Acceleration

ExLLM automatically detects and uses available hardware acceleration:

- **Apple Silicon** - Uses Metal via EMLX
- **NVIDIA GPUs** - Uses CUDA via EXLA
- **AMD GPUs** - Uses ROCm via EXLA
- **CPUs** - Optimized multi-threaded inference

### Performance Tips

1. **First Load**: Models are downloaded from HuggingFace on first use and cached locally
2. **Memory**: Ensure you have enough RAM/VRAM for your chosen model
3. **Batch Size**: Automatically optimized based on available memory
4. **Mixed Precision**: Enabled by default for better performance

### Model Loading

```elixir
# Pre-load a model
{:ok, _} = ExLLM.Local.ModelLoader.load_model("microsoft/phi-2")

# Load from local path
{:ok, _} = ExLLM.Local.ModelLoader.load_model("/path/to/model")

# Unload to free memory
:ok = ExLLM.Local.ModelLoader.unload_model("microsoft/phi-2")

# List loaded models
loaded = ExLLM.Local.ModelLoader.list_loaded_models()
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

## Requirements

- Elixir ~> 1.14
- Erlang/OTP ~> 25.0
- For local models (optional):
  - Bumblebee ~> 0.5
  - Nx ~> 0.7
  - EXLA ~> 0.7 (for GPU acceleration)
  - EMLX ~> 0.1 (for Apple Silicon)

## Development

### Setup

```bash
# Clone the repository
git clone https://github.com/azmaveth/ex_llm.git
cd ex_llm

# Install dependencies
mix deps.get
mix deps.compile

# Run tests
mix test

# Run quality checks
mix format --check-formatted
mix credo
mix dialyzer
```

### Testing

```bash
# Run all tests
mix test

# Run specific test files
mix test test/ex_llm_test.exs

# Run only integration tests
mix test test/*_integration_test.exs

# Run tests with coverage
mix test --cover
```

### Documentation

```bash
# Generate docs
mix docs

# Open in browser
open doc/index.html
```

## Roadmap

Visit the [GitHub repository](https://github.com/azmaveth/ex_llm) to see the detailed roadmap and progress tracking.

### Recently Completed ✅
- [x] OpenAI adapter implementation
- [x] Ollama adapter implementation
- [x] AWS Bedrock adapter with multi-provider support
- [x] Google Gemini adapter
- [x] Structured outputs via Instructor integration
- [x] Comprehensive cost tracking across all providers

### Near-term Goals
- [ ] Function calling support for compatible models
- [ ] Vision/multimodal support for compatible models
- [ ] Embeddings API support
- [ ] Enhanced streaming with token-level callbacks
- [ ] Response caching with configurable TTL
- [ ] Request retry logic with exponential backoff

### Long-term Vision
- Become the go-to LLM client library for Elixir
- Support all major LLM providers
- Provide best-in-class developer experience
- Maintain comprehensive documentation

## Contributing

We welcome contributions! Please see our contributing guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass (`mix test`)
6. Format your code (`mix format`)
7. Run linter (`mix credo`)
8. Commit your changes (`git commit -m 'feat: add amazing feature'`)
9. Push to the branch (`git push origin feature/amazing-feature`)
10. Open a Pull Request

### Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` for new features
- `fix:` for bug fixes
- `docs:` for documentation changes
- `chore:` for maintenance tasks
- `test:` for test additions/changes

## Acknowledgments

- Built with [Req](https://github.com/wojtekmach/req) for HTTP client functionality
- Local model support via [Bumblebee](https://github.com/elixir-nx/bumblebee)
- Structured outputs via [Instructor](https://github.com/thmsmlr/instructor_ex)
- Inspired by the need for a unified LLM interface in Elixir

## License

MIT License - see [LICENSE](LICENSE) for details.

