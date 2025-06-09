# ExLLM

A unified Elixir client for Large Language Models with integrated cost tracking, providing a consistent interface across multiple LLM providers.

> ⚠️ **Alpha Quality Software**: This library is in early development. APIs may change without notice until version 1.0.0 is released. Use in production at your own risk.

## What's New in v0.4.1

- **Response Caching System** - Cache and replay real provider responses for testing
- **3 New Providers** - Added support for LM Studio, Mistral AI, and Perplexity
- **Enhanced Shared Modules** - Better error handling and response building across all providers
- **Improved Documentation** - Updated guides with all 14 supported providers

## Features

- **Unified API**: Single interface for multiple LLM providers
- **Streaming Support**: Real-time streaming responses with error recovery
- **Cost Tracking**: Automatic cost calculation for all API calls
- **Token Estimation**: Heuristic-based token counting for cost prediction
- **Context Management**: Automatic message truncation to fit model context windows
- **Session Management**: Built-in conversation state tracking and persistence
- **Structured Outputs**: Schema validation and retries via Instructor integration
- **Function Calling**: Unified interface for tool use across providers
- **Model Discovery**: Query and compare model capabilities across providers
- **Capability Normalization**: Automatic normalization of provider-specific feature names
- **Error Recovery**: Automatic retry with exponential backoff and stream resumption
- **Mock Testing**: Built-in mock adapter for testing without API calls
- **Response Caching**: Cache real provider responses for offline testing and cost reduction
- **Type Safety**: Comprehensive typespecs and structured data
- **Configurable**: Flexible configuration system with multiple providers
- **Extensible**: Easy to add new LLM providers via adapter pattern

## Supported Providers

- **Anthropic Claude** - Full support for all Claude models
  - claude-opus-4-20250514 (Claude 4 Opus - most capable)
  - claude-sonnet-4-20250514 (Claude 4 Sonnet - balanced)
  - claude-3-7-sonnet-20250219 (Claude 3.7 Sonnet)
  - claude-3-5-sonnet-20241022 (Claude 3.5 Sonnet)
  - claude-3-5-haiku-20241022 (Claude 3.5 Haiku - fastest)
  - claude-3-opus-20240229, claude-3-sonnet-20240229, claude-3-haiku-20240307

- **OpenAI** - Latest GPT models including reasoning models
  - gpt-4.1 series (gpt-4.1, gpt-4.1-mini, gpt-4.1-nano - default)
  - o1 reasoning models (o1-pro, o1, o1-mini, o1-preview)
  - gpt-4o series (gpt-4o, gpt-4o-mini, gpt-4o-latest)
  - gpt-4-turbo series
  - gpt-3.5-turbo models
  - Specialized models for audio, search, and extended output

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

- **Google Gemini** - Gemini models with multimodal support
  - gemini-2.5-pro series (experimental advanced models)
  - gemini-2.0-flash series (fast multimodal)
  - gemini-1.5-pro and gemini-1.5-flash (1M+ context)
  - gemini-pro and gemini-pro-vision
  - Specialized models for image generation and TTS

- **OpenRouter** - Access to 300+ models from multiple providers
  - Claude, GPT-4, Llama, PaLM, and many more
  - Unified API for different model architectures
  - Cost-effective access to premium models
  - Automatic model discovery

- **Groq** - Fast inference platform
  - Llama 4 Scout (17B), Llama 3.3 (70B), Llama 3.1 and 3 series
  - DeepSeek R1 Distill (default - 70B reasoning model)
  - QwQ-32B (reasoning model)
  - Mixtral 8x7B, Gemma series
  - Mistral Saba and specialized models
  - Optimized for ultra-low latency inference

- **X.AI** - Grok models with advanced capabilities
  - grok-beta (131K context)
  - grok-2 and grok-2-vision models
  - grok-3 models with reasoning support
  - Web search and tool use capabilities
  - Vision support on select models

- **LM Studio** - Local model server with OpenAI-compatible API
  - Any model loaded in LM Studio
  - Automatic model discovery
  - No API costs
  - OpenAI-compatible endpoints

- **Mistral AI** - Mistral platform models
  - mistral-large-latest (flagship model)
  - pixtral-large-latest (128K context)
  - ministral-3b and ministral-8b (edge models)
  - codestral-latest (code generation)
  - mistral-small, mistral-embed

- **Perplexity** - Search-enhanced language models
  - sonar-reasoning (latest reasoning model)
  - sonar-pro and sonar (search-enhanced)
  - llama-3.1-sonar series
  - Various open-source models

- **Bumblebee** - Local model inference
  - microsoft/phi-2 (default)
  - meta-llama/Llama-2-7b-hf
  - mistralai/Mistral-7B-v0.1
  - EleutherAI/gpt-neo-1.3B
  - google/flan-t5-base

- **Mock Adapter** - For testing and development
  - Configurable responses
  - Error simulation
  - Request capture
  - Response caching integration
  - No API calls needed

## Installation

Add `ex_llm` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.4.1"},
    
    # Included dependencies (no need to add these manually):
    # - {:instructor, "~> 0.1.0"} - For structured outputs
    # - {:bumblebee, "~> 0.5"} - For local model support
    # - {:nx, "~> 0.7"} - For numerical computing
    
    # Optional hardware acceleration backends (choose one):
    {:exla, "~> 0.7", optional: true},
    
    # Optional: For Apple Silicon Metal acceleration
    # (not included in Hex package, add manually if needed)
    {:emlx, github: "elixir-nx/emlx", branch: "main", optional: true}
  ]
end
```

## Quick Start

📚 **[Quick Start Guide](docs/QUICKSTART.md)** - Get up and running in 5 minutes  
📖 **[User Guide](docs/USER_GUIDE.md)** - Comprehensive documentation of all features

### Configuration

Configure your LLM providers in `config/config.exs`:

```elixir
config :ex_llm,
  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY"),
    base_url: "https://api.anthropic.com"
  ],
  openai: [
    api_key: System.get_env("OPENAI_API_KEY"),
    base_url: "https://api.openai.com"
  ],
  xai: [
    api_key: System.get_env("XAI_API_KEY"),
    base_url: "https://api.x.ai"
  ],
  groq: [
    api_key: System.get_env("GROQ_API_KEY"),
    base_url: "https://api.groq.com"
  ],
  mistral: [
    api_key: System.get_env("MISTRAL_API_KEY"),
    base_url: "https://api.mistral.ai"
  ],
  perplexity: [
    api_key: System.get_env("PERPLEXITY_API_KEY"),
    base_url: "https://api.perplexity.ai"
  ],
  ollama: [
    base_url: "http://localhost:11434"
  ],
  lmstudio: [
    base_url: "http://localhost:1234"
  ],
  bedrock: [
    # AWS credentials (optional - uses credential chain by default)
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
    region: System.get_env("AWS_REGION") || "us-east-1",
    model: "nova-lite"  # Default model (cost-effective)
  ],
  gemini: [
    api_key: System.get_env("GEMINI_API_KEY"),
    base_url: "https://generativelanguage.googleapis.com"
  ],
  openrouter: [
    api_key: System.get_env("OPENROUTER_API_KEY"),
    base_url: "https://openrouter.ai/api/v1"
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

# Using Bumblebee for local models (no API costs!)
{:ok, response} = ExLLM.chat(:bumblebee, messages, model: "microsoft/phi-2")
IO.puts(response.content)

# Using LM Studio (local server)
{:ok, response} = ExLLM.chat(:lmstudio, messages)
IO.puts(response.content)

# Using Groq for ultra-fast inference
{:ok, response} = ExLLM.chat(:groq, messages, model: "deepseek-r1-distill-llama-70b")
IO.puts(response.content)

# Using Mistral AI
{:ok, response} = ExLLM.chat(:mistral, messages, model: "mistral-large-latest")
IO.puts(response.content)

# Using Perplexity for search-enhanced responses
{:ok, response} = ExLLM.chat(:perplexity, messages, model: "sonar-reasoning")
IO.puts(response.content)

# Using OpenRouter for access to many models
{:ok, response} = ExLLM.chat(:openrouter, messages, model: "openai/gpt-4o-mini")
IO.puts(response.content)

# Streaming chat with error recovery
ExLLM.stream_chat(:anthropic, messages, 
  stream_recovery: true,
  fn chunk ->
    IO.write(chunk.content)
  end
)

# Using mock adapter for testing
{:ok, response} = ExLLM.chat(:mock, messages, 
  mock_response: "This is a test response"
)

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
  temperature: 0.7,
  retry_count: 3,          # Automatic retry with exponential backoff
  retry_delay: 1000        # Initial retry delay in ms
]

{:ok, response} = ExLLM.chat(:anthropic, messages, options)

# Function calling
functions = [
  %{
    name: "get_weather",
    description: "Get the current weather for a location",
    parameters: %{
      type: "object",
      properties: %{
        location: %{type: "string", description: "City, State or Country"},
        unit: %{type: "string", enum: ["celsius", "fahrenheit"], description: "Temperature unit"}
      },
      required: ["location"]
    }
  }
]

{:ok, response} = ExLLM.chat(:anthropic, 
  [%{role: "user", content: "What's the weather in Paris, France?"}],
  functions: functions
)

# Parse and execute function calls
case ExLLM.parse_function_calls(response) do
  {:ok, [call | _]} ->
    # Execute the function
    result = get_weather(call.arguments.location, call.arguments[:unit] || "celsius")
    
    # Format the result for the conversation
    function_message = ExLLM.format_function_result(call.name, result)
    
  :none ->
    # No function calls in response
end

# Model discovery and recommendations
{:ok, models} = ExLLM.list_models(:anthropic)
Enum.each(models, &IO.puts(&1.name))

# Find models with specific capabilities
vision_models = ExLLM.find_models_with_features([:vision])
function_models = ExLLM.find_models_with_features([:function_calling, :streaming])

# Get model recommendations
recommended = ExLLM.recommend_models(%{
  provider: :anthropic,
  min_context_window: 100_000,
  required_features: [:function_calling],
  preferred_features: [:vision],
  max_cost_per_million_tokens: 15.0
})

# Compare models
comparison = ExLLM.compare_models([
  {:anthropic, "claude-3-5-sonnet-20241022"},
  {:openai, "gpt-4-turbo"},
  {:gemini, "gemini-pro"}
])

# Provider capabilities - find providers by features
{:ok, caps} = ExLLM.get_provider_capabilities(:openai)
IO.puts("Endpoints: #{Enum.join(caps.endpoints, ", ")}")
# => "Endpoints: chat, embeddings, images, audio, completions, fine_tuning, files"

# Find providers with specific features
providers = ExLLM.find_providers_with_features([:embeddings, :streaming])
# => [:openai, :ollama]

# Get provider recommendations
recommendations = ExLLM.recommend_providers(%{
  required_features: [:vision, :streaming],
  preferred_features: [:audio_input, :function_calling],
  prefer_local: false
})
# => [
#   %{provider: :openai, score: 0.95, matched_features: [...], missing_features: []},
#   %{provider: :anthropic, score: 0.80, matched_features: [...], missing_features: [:audio_input]}
# ]

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

### Function Calling

- `parse_function_calls/2` - Parse function calls from LLM response
- `execute_function/2` - Execute a function call with validation
- `format_function_result/2` - Format function result for conversation

### Model Capabilities

- `get_model_info/2` - Get complete capability information for a model
- `model_supports?/3` - Check if a model supports a specific feature
- `find_models_with_features/1` - Find models that support specific features
- `compare_models/1` - Compare capabilities across multiple models
- `recommend_models/1` - Get model recommendations based on requirements
- `models_by_capability/1` - Get models grouped by capability support
- `list_model_features/0` - List all trackable model features

### Provider Capabilities

- `get_provider_capabilities/1` - Get API-level capabilities for a provider
- `provider_supports?/2` - Check if a provider supports a feature/endpoint
- `find_providers_with_features/1` - Find providers that support specific features
- `compare_providers/1` - Compare capabilities across multiple providers
- `recommend_providers/1` - Get provider recommendations based on requirements
- `list_providers/0` - List all available providers
- `is_local_provider?/1` - Check if a provider runs locally
- `provider_requires_auth?/1` - Check if a provider requires authentication

### Capability Normalization

ExLLM automatically normalizes different capability names used by various providers. This means you can use provider-specific terminology and ExLLM will understand it:

```elixir
# These all refer to the same capability (function calling)
ExLLM.provider_supports?(:openai, :function_calling)    # => true
ExLLM.provider_supports?(:anthropic, :tool_use)         # => true
ExLLM.provider_supports?(:openai, :tools)               # => true

# Find providers using any terminology
ExLLM.find_providers_with_features([:tool_use])         # Works!
ExLLM.find_providers_with_features([:function_calling]) # Also works!
```

Common normalizations:
- Function calling: `function_calling`, `tool_use`, `tools`, `functions`
- Image generation: `image_generation`, `images`, `dalle`, `text_to_image`
- Speech synthesis: `speech_synthesis`, `tts`, `text_to_speech`
- Embeddings: `embeddings`, `embed`, `embedding`, `text_embedding`
- Vision: `vision`, `image_understanding`, `visual_understanding`, `multimodal`

### Error Recovery

- `resume_stream/2` - Resume a previously interrupted stream
- `list_recoverable_streams/0` - List all recoverable streams

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

## Model Configuration

ExLLM uses external YAML configuration files for model metadata, pricing, and capabilities. This allows easy updates without code changes:

### External Configuration Structure

```yaml
# config/models/anthropic.yml
provider: anthropic
default_model: "claude-sonnet-4-20250514"
models:
  claude-3-5-sonnet-20241022:
    context_window: 200000
    pricing:
      input: 3.00    # per 1M tokens
      output: 15.00
    capabilities:
      - streaming
      - function_calling
      - vision
```

### Configuration Management

```elixir
# Get model pricing
pricing = ExLLM.ModelConfig.get_pricing(:anthropic, "claude-3-5-sonnet-20241022")

# Get context window
context = ExLLM.ModelConfig.get_context_window(:openai, "gpt-4o")

# Get default model for provider
default = ExLLM.ModelConfig.get_default_model(:openrouter)

# Configuration is cached for performance
# Updates require restart or cache refresh
```

## Cost Tracking

ExLLM automatically tracks costs for all API calls using the external pricing configuration:

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

ExLLM includes pricing data (as of January 2025) in external YAML files for all supported providers:
- **Anthropic**: Claude 3 series (Opus, Sonnet, Haiku), Claude 3.5, Claude 4
- **OpenAI**: GPT-4, GPT-4 Turbo, GPT-3.5 Turbo, GPT-4o series  
- **OpenRouter**: 300+ models with dynamic pricing
- **Google Gemini**: Pro, Ultra, Nano
- **AWS Bedrock**: Various models including Claude, Titan, Llama 2
- **Ollama**: Local models (free - $0.00)
- **Bumblebee**: Free ($0.00) - no API costs

Pricing data is stored in `config/models/*.yml` files and can be updated independently of code changes.

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

Instructor is included as a dependency of ExLLM, so no additional installation is needed.

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
- `:bumblebee` - Local Bumblebee models

### Error Handling

```elixir
case ExLLM.chat(:anthropic, messages, response_model: UserProfile) do
  {:ok, profile} ->
    # Successfully validated structure
    IO.inspect(profile)
    
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

### Logging

ExLLM provides a unified logging system with fine-grained control over what gets logged and how sensitive data is handled. 

📖 **[Read the full Logger User Guide](docs/LOGGER.md)** for detailed documentation.

```elixir
# Quick example
alias ExLLM.Logger

Logger.info("Starting chat completion")
Logger.with_context(provider: :openai, operation: :chat) do
  Logger.info("Sending request")
  # ... make API call ...
  Logger.info("Request completed", tokens: 150, duration_ms: 230)
end
```

Configure logging in your `config/config.exs`:

```elixir
config :ex_llm,
  log_level: :info,
  log_components: %{
    requests: true,
    responses: true,
    streaming: false,  # Can be noisy
    retries: true,
    cache: false,
    models: true
  },
  log_redaction: %{
    api_keys: true,    # Always recommended
    content: false     # Set true in production
  }
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

## Error Recovery and Retries

ExLLM includes automatic error recovery and retry mechanisms:

### Automatic Retries

```elixir
# Configure retry behavior
options = [
  retry_count: 3,              # Number of retry attempts
  retry_delay: 1000,           # Initial delay in milliseconds
  retry_backoff: :exponential, # Backoff strategy
  retry_jitter: true           # Add jitter to prevent thundering herd
]

{:ok, response} = ExLLM.chat(:anthropic, messages, options)

# Provider-specific retry policies
ExLLM.Retry.with_retry(fn ->
  ExLLM.chat(:anthropic, messages)
end, 
  max_attempts: 5,
  initial_delay: 500,
  max_delay: 30_000,
  should_retry: fn error ->
    # Custom retry logic
    case error do
      {:api_error, %{status: 429}} -> true  # Rate limit
      {:api_error, %{status: 503}} -> true  # Service unavailable
      {:network_error, _} -> true           # Network issues
      _ -> false
    end
  end
)
```

### Stream Recovery

```elixir
# Enable automatic stream recovery
{:ok, stream_id} = ExLLM.stream_chat(:anthropic, messages,
  stream_recovery: true,
  recovery_strategy: :paragraph,  # :exact, :paragraph, or :summarize
  fn chunk ->
    IO.write(chunk.content)
  end
)

# If stream is interrupted, resume from where it left off
case ExLLM.resume_stream(stream_id) do
  {:ok, resumed_stream} ->
    for chunk <- resumed_stream do
      IO.write(chunk.content)
    end
  {:error, :not_found} ->
    # Stream not recoverable
end

# List recoverable streams
recoverable = ExLLM.list_recoverable_streams()
```

## Mock Adapter for Testing

The mock adapter allows you to test your LLM interactions without making real API calls:

### Basic Mock Usage

```elixir
# Configure static mock response
{:ok, response} = ExLLM.chat(:mock, messages,
  mock_response: "This is a mock response"
)

# Configure mock with usage data
{:ok, response} = ExLLM.chat(:mock, messages,
  mock_response: %{
    content: "Mock response with usage",
    usage: %{input_tokens: 10, output_tokens: 20},
    model: "mock-model"
  }
)

# Mock streaming responses
ExLLM.stream_chat(:mock, messages,
  mock_chunks: ["Hello", " from", " mock", " adapter!"],
  chunk_delay: 100,  # Delay between chunks in ms
  fn chunk ->
    IO.write(chunk.content)
  end
)
```

### Advanced Mock Configuration

```elixir
# Dynamic mock responses based on input
mock_handler = fn messages ->
  last_message = List.last(messages)
  cond do
    String.contains?(last_message.content, "weather") ->
      "It's sunny and 72°F"
    String.contains?(last_message.content, "hello") ->
      "Hello! How can I help you?"
    true ->
      "I don't understand"
  end
end

{:ok, response} = ExLLM.chat(:mock, messages,
  mock_handler: mock_handler
)

# Simulate errors
{:error, {:api_error, %{status: 429, body: "Rate limit exceeded"}}} = 
  ExLLM.chat(:mock, messages,
    mock_error: {:api_error, %{status: 429, body: "Rate limit exceeded"}}
  )

# Capture requests for assertions
{:ok, response} = ExLLM.chat(:mock, messages,
  capture_requests: true,
  mock_response: "Test response"
)

# Access captured requests
captured = ExLLM.Adapters.Mock.get_captured_requests()
assert length(captured) == 1
assert List.first(captured).messages == messages
```

### Testing with Mock Adapter

```elixir
defmodule MyApp.LLMClientTest do
  use ExUnit.Case

  setup do
    # Clear any previous captures
    ExLLM.Adapters.Mock.clear_captured_requests()
    :ok
  end

  test "handles weather queries" do
    messages = [%{role: "user", content: "What's the weather?"}]
    
    {:ok, response} = ExLLM.chat(:mock, messages,
      mock_response: "It's sunny today!",
      capture_requests: true
    )
    
    assert response.content == "It's sunny today!"
    
    # Verify the request
    [request] = ExLLM.Adapters.Mock.get_captured_requests()
    assert request.provider == :mock
    assert request.messages == messages
  end

  test "simulates API errors" do
    messages = [%{role: "user", content: "Hello"}]
    
    {:error, error} = ExLLM.chat(:mock, messages,
      mock_error: {:network_error, :timeout}
    )
    
    assert error == {:network_error, :timeout}
  end
end
```

## Local Model Support

ExLLM supports running models locally using Bumblebee and EXLA/EMLX backends. This enables on-device inference without API calls or costs.

### Setup

1. ExLLM includes Bumblebee and Nx dependencies. For hardware acceleration, add one of these optional backends to your `mix.exs`:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.4.1"},
    # For CUDA/ROCm GPUs:
    {:exla, "~> 0.7"}
    # OR for Apple Silicon Metal acceleration:
    # {:emlx, github: "elixir-nx/emlx", branch: "main"}
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

{:ok, response} = ExLLM.chat(:bumblebee, messages, model: "microsoft/phi-2")
IO.puts(response.content)

# Stream responses
{:ok, stream} = ExLLM.stream_chat(:bumblebee, messages)
for chunk <- stream do
  IO.write(chunk.content)
end

# List available models
{:ok, models} = ExLLM.list_models(:bumblebee)
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

#### User Guides

- [Quick Start Guide](docs/QUICKSTART.md) - Get started with the most common use cases
- [User Guide](docs/USER_GUIDE.md) - Comprehensive documentation of all features
- [Logger User Guide](docs/LOGGER.md) - Comprehensive guide to ExLLM's unified logging system
- [Provider Capabilities Guide](docs/PROVIDER_CAPABILITIES.md) - How to find and update provider capabilities

## Roadmap

Visit the [GitHub repository](https://github.com/azmaveth/ex_llm) to see the detailed roadmap and progress tracking.

### Recently Completed ✅
- [x] OpenAI adapter implementation
- [x] Ollama adapter implementation
- [x] AWS Bedrock adapter with multi-provider support
- [x] Google Gemini adapter
- [x] Structured outputs via Instructor integration
- [x] Comprehensive cost tracking across all providers
- [x] Function calling support for compatible models
- [x] Request retry logic with exponential backoff
- [x] Enhanced streaming error recovery
- [x] Mock adapter for testing
- [x] Model capability discovery and recommendations

### Near-term Goals
- [ ] Vision/multimodal support for compatible models
- [ ] Embeddings API support
- [ ] Enhanced streaming with token-level callbacks
- [ ] Response caching with configurable TTL
- [ ] Fine-tuning management
- [ ] Batch API support
- [ ] Prompt template management
- [ ] Usage analytics and reporting

### Long-term Vision
- Become the go-to LLM client library for Elixir
- Support all major LLM providers
- Provide best-in-class developer experience
- Maintain comprehensive documentation
- Build a thriving ecosystem of extensions

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

## Future Provider Support

ExLLM includes pre-configured model data for 49 additional providers, ready for implementation:

**Major Cloud Providers**: Azure, Vertex AI, Databricks, Sagemaker, Watsonx, Snowflake

**AI Companies**: Mistral AI, Cohere, Together AI, Replicate, Perplexity, DeepSeek, XAI

**Inference Platforms**: Fireworks AI, DeepInfra, Anyscale, Cloudflare, NScale, SambaNova

**Specialized**: AI21, NLP Cloud, Aleph Alpha, Voyage (embeddings), Assembly AI (audio)

All model configurations including pricing, context windows, and capabilities are already available in `config/models/`.

## Acknowledgments

- Built with [Req](https://github.com/wojtekmach/req) for HTTP client functionality
- Local model support via [Bumblebee](https://github.com/elixir-nx/bumblebee)
- Structured outputs via [Instructor](https://github.com/thmsmlr/instructor_ex)
- Model configuration data synced from [LiteLLM](https://github.com/BerriAI/litellm)
- Inspired by the need for a unified LLM interface in Elixir

## License

MIT License - see [LICENSE](LICENSE) for details.

