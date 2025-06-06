# ExLLM User Guide

This comprehensive guide covers all features and capabilities of the ExLLM library.

## Table of Contents

1. [Installation and Setup](#installation-and-setup)
2. [Configuration](#configuration)
3. [Basic Usage](#basic-usage)
4. [Providers](#providers)
5. [Chat Completions](#chat-completions)
6. [Streaming](#streaming)
7. [Session Management](#session-management)
8. [Context Management](#context-management)
9. [Function Calling](#function-calling)
10. [Vision and Multimodal](#vision-and-multimodal)
11. [Embeddings](#embeddings)
12. [Structured Outputs](#structured-outputs)
13. [Cost Tracking](#cost-tracking)
14. [Error Handling and Retries](#error-handling-and-retries)
15. [Caching](#caching)
16. [Model Discovery](#model-discovery)
17. [Provider Capabilities](#provider-capabilities)
18. [Logging](#logging)
19. [Testing with Mock Adapter](#testing-with-mock-adapter)
20. [Advanced Topics](#advanced-topics)

## Installation and Setup

### Adding to Your Project

Add ExLLM to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.3.1"},
    # Optional: for structured outputs
    {:instructor, "~> 0.1.0"}
  ]
end
```

Run `mix deps.get` to install the dependencies.

### Optional Dependencies

- **Instructor**: Required for structured outputs with schema validation
- **Req**: HTTP client (automatically included)
- **Jason**: JSON parser (automatically included)

## Configuration

ExLLM supports multiple configuration methods to suit different use cases.

### Environment Variables

The simplest way to configure ExLLM:

```bash
# OpenAI
export OPENAI_API_KEY="sk-..."
export OPENAI_API_BASE="https://api.openai.com/v1"  # Optional custom endpoint

# Anthropic
export ANTHROPIC_API_KEY="sk-ant-..."

# Google Gemini
export GOOGLE_API_KEY="..."
# or
export GEMINI_API_KEY="..."

# Groq
export GROQ_API_KEY="gsk_..."

# OpenRouter
export OPENROUTER_API_KEY="sk-or-..."

# X.AI
export XAI_API_KEY="xai-..."

# AWS Bedrock
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"

# Ollama
export OLLAMA_API_BASE="http://localhost:11434"
```

### Static Configuration

For more control, use static configuration:

```elixir
config = %{
  openai: %{
    api_key: "sk-...",
    api_base: "https://api.openai.com/v1",
    default_model: "gpt-4o"
  },
  anthropic: %{
    api_key: "sk-ant-...",
    default_model: "claude-3-5-sonnet-20241022"
  }
}

{:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

# Use with config_provider option
{:ok, response} = ExLLM.chat(:openai, messages, config_provider: provider)
```

### Custom Configuration Provider

Implement your own configuration provider:

```elixir
defmodule MyApp.ConfigProvider do
  @behaviour ExLLM.ConfigProvider
  
  def get([:openai, :api_key]), do: fetch_from_vault("openai_key")
  def get([:anthropic, :api_key]), do: fetch_from_vault("anthropic_key")
  def get(_path), do: nil
  
  def get_all() do
    %{
      openai: %{api_key: fetch_from_vault("openai_key")},
      anthropic: %{api_key: fetch_from_vault("anthropic_key")}
    }
  end
end

# Use it
{:ok, response} = ExLLM.chat(:openai, messages, 
  config_provider: MyApp.ConfigProvider
)
```

## Basic Usage

### Simple Chat

```elixir
messages = [
  %{role: "user", content: "Hello, how are you?"}
]

{:ok, response} = ExLLM.chat(:openai, messages)
IO.puts(response.content)
```

### Provider/Model Syntax

```elixir
# Use provider/model string syntax
{:ok, response} = ExLLM.chat("anthropic/claude-3-haiku-20240307", messages)

# Equivalent to
{:ok, response} = ExLLM.chat(:anthropic, messages, 
  model: "claude-3-haiku-20240307"
)
```

### Response Structure

```elixir
%ExLLM.Types.LLMResponse{
  content: "I'm doing well, thank you!",
  model: "gpt-4o",
  finish_reason: "stop",
  usage: %{
    input_tokens: 12,
    output_tokens: 8,
    total_tokens: 20
  },
  cost: %{
    input_cost: 0.00006,
    output_cost: 0.00016,
    total_cost: 0.00022,
    currency: "USD"
  }
}
```

## Providers

### Supported Providers

ExLLM supports these providers out of the box:

- **:openai** - OpenAI GPT models
- **:anthropic** - Anthropic Claude models
- **:gemini** - Google Gemini models
- **:groq** - Groq fast inference
- **:ollama** - Local models via Ollama
- **:bedrock** - AWS Bedrock
- **:openrouter** - OpenRouter (300+ models)
- **:xai** - X.AI Grok models
- **:local** - Local models via Bumblebee
- **:mock** - Mock adapter for testing

### Checking Provider Configuration

```elixir
# Check if a provider is configured
if ExLLM.configured?(:openai) do
  {:ok, response} = ExLLM.chat(:openai, messages)
end

# Get default model for a provider
model = ExLLM.default_model(:anthropic)
# => "claude-3-5-sonnet-20241022"

# List available models
{:ok, models} = ExLLM.list_models(:openai)
for model <- models do
  IO.puts("#{model.id}: #{model.context_window} tokens")
end
```

## Chat Completions

### Basic Options

```elixir
{:ok, response} = ExLLM.chat(:openai, messages,
  model: "gpt-4o",           # Specific model
  temperature: 0.7,          # 0.0-1.0, higher = more creative
  max_tokens: 1000,          # Max response length
  top_p: 0.9,                # Nucleus sampling
  frequency_penalty: 0.5,    # Reduce repetition
  presence_penalty: 0.5,     # Encourage new topics
  stop: ["\n\n", "END"],     # Stop sequences
  seed: 12345                # Reproducible outputs
)
```

### System Messages

```elixir
messages = [
  %{role: "system", content: "You are a helpful coding assistant."},
  %{role: "user", content: "How do I read a file in Elixir?"}
]

{:ok, response} = ExLLM.chat(:openai, messages)
```

### Multi-turn Conversations

```elixir
conversation = [
  %{role: "user", content: "What's the capital of France?"},
  %{role: "assistant", content: "The capital of France is Paris."},
  %{role: "user", content: "What's the population?"}
]

{:ok, response} = ExLLM.chat(:openai, conversation)
```

## Streaming

### Basic Streaming

```elixir
{:ok, stream} = ExLLM.stream_chat(:openai, messages)

for chunk <- stream do
  case chunk do
    %{content: content} when content != nil ->
      IO.write(content)
      
    %{finish_reason: reason} when reason != nil ->
      IO.puts("\nFinished: #{reason}")
      
    _ ->
      # Other chunk types (role, etc.)
      :ok
  end
end
```

### Streaming with Callback

```elixir
{:ok, stream} = ExLLM.stream_chat(:openai, messages,
  on_chunk: fn chunk ->
    if chunk.content, do: IO.write(chunk.content)
  end
)

# Consume the stream
Enum.to_list(stream)
```

### Collecting Streamed Response

```elixir
{:ok, stream} = ExLLM.stream_chat(:openai, messages)

# Collect all chunks into a single response
full_content = 
  stream
  |> Enum.map(& &1.content)
  |> Enum.reject(&is_nil/1)
  |> Enum.join("")
```

### Stream Recovery

Enable automatic stream recovery for interrupted streams:

```elixir
{:ok, stream} = ExLLM.stream_chat(:openai, messages,
  stream_recovery: true,
  recovery_strategy: :exact  # :exact, :paragraph, or :summarize
)

# If stream is interrupted, you can resume
{:ok, resumed_stream} = ExLLM.resume_stream(recovery_id)
```

## Session Management

Sessions provide stateful conversation management with automatic token tracking.

### Creating and Using Sessions

```elixir
# Create a new session
session = ExLLM.new_session(:openai, name: "Customer Support")

# Chat with session (automatically manages message history)
{:ok, {response, session}} = ExLLM.chat_with_session(
  session,
  "What's the weather like?"
)

# Continue the conversation
{:ok, {response2, session}} = ExLLM.chat_with_session(
  session,
  "What should I wear?"
)

# Check token usage
total_tokens = ExLLM.session_token_usage(session)
IO.puts("Total tokens used: #{total_tokens}")
```

### Managing Session Messages

```elixir
# Add messages manually
session = ExLLM.add_session_message(session, "user", "Hello!")
session = ExLLM.add_session_message(session, "assistant", "Hi there!")

# Get message history
messages = ExLLM.get_session_messages(session)
recent_10 = ExLLM.get_session_messages(session, 10)

# Clear messages but keep session metadata
session = ExLLM.clear_session(session)
```

### Persisting Sessions

```elixir
# Save session to JSON
{:ok, json} = ExLLM.save_session(session)
File.write!("session.json", json)

# Load session from JSON
{:ok, json} = File.read("session.json")
{:ok, restored_session} = ExLLM.load_session(json)
```

### Session with Context

```elixir
# Create session with default context
session = ExLLM.new_session(:openai,
  name: "Tech Support",
  context: %{
    temperature: 0.3,
    system_message: "You are a technical support agent."
  }
)

# Context is automatically applied to all chats
{:ok, {response, session}} = ExLLM.chat_with_session(session, "Help!")
```

## Context Management

Automatically manage conversation context to fit within model limits.

### Context Window Validation

```elixir
# Check if messages fit in context window
case ExLLM.validate_context(messages, provider: :openai, model: "gpt-4") do
  {:ok, token_count} ->
    IO.puts("Messages use #{token_count} tokens")
    
  {:error, reason} ->
    IO.puts("Messages too large: #{reason}")
end

# Get context window size for a model
window_size = ExLLM.context_window_size(:anthropic, "claude-3-opus-20240229")
# => 200000
```

### Automatic Message Truncation

```elixir
# Prepare messages to fit in context window
truncated = ExLLM.prepare_messages(long_conversation,
  provider: :openai,
  model: "gpt-4",
  max_tokens: 4000,           # Reserve tokens for response
  strategy: :sliding_window,   # or :smart
  preserve_messages: 5         # Always keep last 5 messages
)
```

### Truncation Strategies

1. **:sliding_window** - Keep most recent messages
2. **:smart** - Preserve system messages and recent context

```elixir
# Smart truncation preserves important context
{:ok, response} = ExLLM.chat(:openai, very_long_conversation,
  strategy: :smart,
  preserve_messages: 10
)
```

### Context Statistics

```elixir
stats = ExLLM.context_stats(messages)
# => %{
#   message_count: 20,
#   total_tokens: 1500,
#   by_role: %{"user" => 10, "assistant" => 9, "system" => 1},
#   avg_tokens_per_message: 75
# }
```

## Function Calling

Enable AI models to call functions/tools in your application.

### Basic Function Calling

```elixir
# Define available functions
functions = [
  %{
    name: "get_weather",
    description: "Get current weather for a location",
    parameters: %{
      type: "object",
      properties: %{
        location: %{
          type: "string",
          description: "City and state, e.g. San Francisco, CA"
        },
        unit: %{
          type: "string",
          enum: ["celsius", "fahrenheit"],
          description: "Temperature unit"
        }
      },
      required: ["location"]
    }
  }
]

# Let the AI decide when to call functions
{:ok, response} = ExLLM.chat(:openai, 
  [%{role: "user", content: "What's the weather in NYC?"}],
  functions: functions,
  function_call: "auto"  # or "none" or %{name: "get_weather"}
)
```

### Handling Function Calls

```elixir
# Parse function calls from response
case ExLLM.parse_function_calls(response, :openai) do
  {:ok, [function_call | _]} ->
    # AI wants to call a function
    IO.inspect(function_call)
    # => %ExLLM.FunctionCalling.FunctionCall{
    #      name: "get_weather",
    #      arguments: %{"location" => "New York, NY"}
    #    }
    
    # Execute the function
    result = get_weather_impl(function_call.arguments["location"])
    
    # Format result for conversation
    function_message = ExLLM.format_function_result(
      %ExLLM.FunctionCalling.FunctionResult{
        name: "get_weather",
        result: result
      },
      :openai
    )
    
    # Continue conversation with function result
    messages = messages ++ [response_message, function_message]
    {:ok, final_response} = ExLLM.chat(:openai, messages)
    
  {:ok, []} ->
    # No function call, regular response
    IO.puts(response.content)
end
```

### Function Execution

```elixir
# Define functions with handlers
functions_with_handlers = [
  %{
    name: "calculate",
    description: "Perform mathematical calculations",
    parameters: %{
      type: "object",
      properties: %{
        expression: %{type: "string"}
      },
      required: ["expression"]
    },
    handler: fn args ->
      # Your implementation
      {result, _} = Code.eval_string(args["expression"])
      %{result: result}
    end
  }
]

# Execute function automatically
{:ok, result} = ExLLM.execute_function(function_call, functions_with_handlers)
```

### Provider-Specific Notes

Different providers use different terminology:
- OpenAI: "functions" and "function_call"
- Anthropic: "tools" and "tool_use"
- ExLLM normalizes these automatically

## Vision and Multimodal

Work with images and other media types.

### Basic Image Analysis

```elixir
# Create a vision message
{:ok, message} = ExLLM.vision_message(
  "What's in this image?",
  ["path/to/image.jpg"]
)

# Send to vision-capable model
{:ok, response} = ExLLM.chat(:openai, [message],
  model: "gpt-4o"  # or any vision model
)
```

### Multiple Images

```elixir
{:ok, message} = ExLLM.vision_message(
  "Compare these images",
  [
    "image1.jpg",
    "image2.jpg",
    "https://example.com/image3.png"  # URLs work too
  ],
  detail: :high  # :low, :high, or :auto
)
```

### Loading Images

```elixir
# Load image with options
{:ok, image_part} = ExLLM.load_image("photo.jpg",
  detail: :high,
  resize: {1024, 1024}  # Optional resizing
)

# Build custom message
message = %{
  role: "user",
  content: [
    %{type: "text", text: "Describe this image"},
    image_part
  ]
}
```

### Checking Vision Support

```elixir
# Check if provider/model supports vision
if ExLLM.supports_vision?(:anthropic, "claude-3-opus-20240229") do
  # This model supports vision
end

# Find all vision-capable models
vision_models = ExLLM.find_models_with_features([:vision])
```

### Text Extraction from Images

```elixir
# OCR-like functionality
{:ok, text} = ExLLM.extract_text_from_image(:openai, "document.png",
  model: "gpt-4o",
  prompt: "Extract all text, preserving formatting and layout"
)
```

### Image Analysis

```elixir
# Analyze multiple images
{:ok, analysis} = ExLLM.analyze_images(:anthropic,
  ["chart1.png", "chart2.png"],
  "Compare these charts and identify trends",
  model: "claude-3-5-sonnet-20241022"
)
```

## Embeddings

Generate vector embeddings for semantic search and similarity.

### Basic Embeddings

```elixir
# Generate embeddings for text
{:ok, response} = ExLLM.embeddings(:openai, 
  ["Hello world", "Goodbye world"]
)

# Response structure
%ExLLM.Types.EmbeddingResponse{
  embeddings: [
    [0.0123, -0.0456, ...],  # 1536 dimensions for text-embedding-3-small
    [0.0789, -0.0234, ...]
  ],
  model: "text-embedding-3-small",
  usage: %{total_tokens: 8}
}
```

### Embedding Options

```elixir
{:ok, response} = ExLLM.embeddings(:openai, texts,
  model: "text-embedding-3-large",
  dimensions: 256,  # Reduce dimensions (model-specific)
  encoding_format: "float"  # or "base64"
)
```

### Similarity Search

```elixir
# Calculate similarity between embeddings
similarity = ExLLM.cosine_similarity(embedding1, embedding2)
# => 0.87 (1.0 = identical, 0.0 = orthogonal, -1.0 = opposite)

# Find similar items
query_embedding = get_embedding("search query")
items = [
  %{id: 1, text: "Document 1", embedding: [...]},
  %{id: 2, text: "Document 2", embedding: [...]},
  # ...
]

results = ExLLM.find_similar(query_embedding, items,
  top_k: 10,
  threshold: 0.7  # Minimum similarity
)
# => [
#   %{item: %{id: 2, ...}, similarity: 0.92},
#   %{item: %{id: 5, ...}, similarity: 0.85},
#   ...
# ]
```

### Listing Embedding Models

```elixir
{:ok, models} = ExLLM.list_embedding_models(:openai)
for model <- models do
  IO.puts("#{model.name}: #{model.dimensions} dimensions")
end
```

### Caching Embeddings

```elixir
# Enable caching for embeddings
{:ok, response} = ExLLM.embeddings(:openai, texts,
  cache: true,
  cache_ttl: :timer.hours(24)
)
```

## Structured Outputs

Generate structured data with schema validation using Instructor integration.

### Basic Structured Output

```elixir
defmodule EmailClassification do
  use Ecto.Schema
  
  embedded_schema do
    field :category, Ecto.Enum, values: [:personal, :work, :spam]
    field :priority, Ecto.Enum, values: [:high, :medium, :low]
    field :summary, :string
  end
end

{:ok, result} = ExLLM.chat(:openai, 
  [%{role: "user", content: "Classify this email: Meeting tomorrow at 3pm"}],
  response_model: EmailClassification,
  max_retries: 3  # Retry on validation failure
)

IO.inspect(result)
# => %EmailClassification{
#      category: :work,
#      priority: :high,
#      summary: "Meeting scheduled for tomorrow"
#    }
```

### Complex Schemas

```elixir
defmodule ProductExtraction do
  use Ecto.Schema
  
  embedded_schema do
    field :name, :string
    field :price, :decimal
    field :currency, :string
    field :in_stock, :boolean
    
    embeds_many :features, Feature do
      field :name, :string
      field :value, :string
    end
  end
  
  def changeset(struct, params) do
    struct
    |> Ecto.Changeset.cast(params, [:name, :price, :currency, :in_stock])
    |> Ecto.Changeset.cast_embed(:features)
    |> Ecto.Changeset.validate_required([:name, :price])
    |> Ecto.Changeset.validate_number(:price, greater_than: 0)
  end
end

{:ok, product} = ExLLM.chat(:anthropic,
  [%{role: "user", content: "Extract product info from: iPhone 15 Pro, $999, 256GB storage, A17 chip"}],
  response_model: ProductExtraction
)
```

### Lists and Collections

```elixir
defmodule TodoList do
  use Ecto.Schema
  
  embedded_schema do
    embeds_many :todos, Todo do
      field :task, :string
      field :priority, Ecto.Enum, values: [:high, :medium, :low]
      field :completed, :boolean, default: false
    end
  end
end

{:ok, todo_list} = ExLLM.chat(:openai,
  [%{role: "user", content: "Create a todo list for launching a new feature"}],
  response_model: TodoList
)
```

## Cost Tracking

ExLLM automatically tracks API costs for all operations.

### Automatic Cost Tracking

```elixir
{:ok, response} = ExLLM.chat(:openai, messages)

# Cost is included in response
IO.inspect(response.cost)
# => %{
#   input_cost: 0.00003,
#   output_cost: 0.00006,
#   total_cost: 0.00009,
#   currency: "USD"
# }

# Format for display
IO.puts(ExLLM.format_cost(response.cost.total_cost))
# => "$0.009¢"
```

### Manual Cost Calculation

```elixir
usage = %{input_tokens: 1000, output_tokens: 500}
cost = ExLLM.calculate_cost(:openai, "gpt-4", usage)
# => %{
#   input_cost: 0.03,
#   output_cost: 0.06,
#   total_cost: 0.09,
#   currency: "USD",
#   per_million_input: 30.0,
#   per_million_output: 120.0
# }
```

### Token Estimation

```elixir
# Estimate tokens for text
tokens = ExLLM.estimate_tokens("Hello, world!")
# => 4

# Estimate for messages
tokens = ExLLM.estimate_tokens([
  %{role: "user", content: "Hi"},
  %{role: "assistant", content: "Hello!"}
])
# => 12
```

### Disabling Cost Tracking

```elixir
{:ok, response} = ExLLM.chat(:openai, messages,
  track_cost: false
)
# response.cost will be nil
```

## Error Handling and Retries

### Automatic Retries

Retries are enabled by default with exponential backoff:

```elixir
{:ok, response} = ExLLM.chat(:openai, messages,
  retry: true,           # Default: true
  retry_count: 3,        # Default: 3 attempts
  retry_delay: 1000,     # Default: 1 second initial delay
  retry_backoff: :exponential,  # or :linear
  retry_jitter: true     # Add randomness to prevent thundering herd
)
```

### Error Types

```elixir
case ExLLM.chat(:openai, messages) do
  {:ok, response} ->
    IO.puts(response.content)
    
  {:error, %ExLLM.Error{type: :rate_limit} = error} ->
    IO.puts("Rate limited. Retry after: #{error.retry_after}")
    
  {:error, %ExLLM.Error{type: :invalid_api_key}} ->
    IO.puts("Check your API key configuration")
    
  {:error, %ExLLM.Error{type: :context_length_exceeded}} ->
    IO.puts("Message too long for model")
    
  {:error, %ExLLM.Error{type: :timeout}} ->
    IO.puts("Request timed out")
    
  {:error, error} ->
    IO.inspect(error)
end
```

### Custom Retry Logic

```elixir
defmodule MyApp.RetryHandler do
  def with_custom_retry(provider, messages, opts \\ []) do
    Enum.reduce_while(1..5, nil, fn attempt, _acc ->
      case ExLLM.chat(provider, messages, Keyword.put(opts, :retry, false)) do
        {:ok, response} ->
          {:halt, {:ok, response}}
          
        {:error, %{type: :rate_limit} = error} ->
          wait_time = error[:retry_after] || :timer.seconds(attempt * 10)
          Process.sleep(wait_time)
          {:cont, nil}
          
        {:error, _} = error ->
          if attempt == 5 do
            {:halt, error}
          else
            Process.sleep(:timer.seconds(attempt))
            {:cont, nil}
          end
      end
    end)
  end
end
```

## Caching

Cache responses to reduce API calls and costs.

### Basic Caching

```elixir
# Enable caching globally
Application.put_env(:ex_llm, :cache_enabled, true)

# Or per request
{:ok, response} = ExLLM.chat(:openai, messages,
  cache: true,
  cache_ttl: :timer.minutes(15)  # Default: 15 minutes
)

# Same request will use cache
{:ok, cached_response} = ExLLM.chat(:openai, messages, cache: true)
```

### Cache Management

```elixir
# Clear specific cache entry
ExLLM.Cache.delete(cache_key)

# Clear all cache
ExLLM.Cache.clear()

# Get cache stats
stats = ExLLM.Cache.stats()
# => %{size: 42, hits: 100, misses: 20}
```

### Custom Cache Keys

```elixir
# Cache key is automatically generated from:
# - Provider
# - Messages
# - Relevant options (model, temperature, etc.)

# You can also use manual cache management
cache_key = ExLLM.Cache.generate_cache_key(:openai, messages, options)
```

## Model Discovery

### Finding Models

```elixir
# Get model information
{:ok, info} = ExLLM.get_model_info(:openai, "gpt-4o")
IO.inspect(info)
# => %ExLLM.ModelCapabilities.ModelInfo{
#   id: "gpt-4o",
#   context_window: 128000,
#   max_output_tokens: 16384,
#   capabilities: %{
#     vision: %{supported: true},
#     function_calling: %{supported: true},
#     streaming: %{supported: true},
#     ...
#   }
# }

# Check specific capability
if ExLLM.model_supports?(:openai, "gpt-4o", :vision) do
  # Model supports vision
end
```

### Model Recommendations

```elixir
# Get recommendations based on requirements
recommendations = ExLLM.recommend_models(
  features: [:vision, :function_calling],
  min_context_window: 100_000,
  max_cost_per_1k_tokens: 1.0,
  prefer_local: false,
  limit: 5
)

for {provider, model, info} <- recommendations do
  IO.puts("#{provider}/#{model}")
  IO.puts("  Score: #{info.score}")
  IO.puts("  Context: #{info.context_window}")
  IO.puts("  Cost: $#{info.cost_per_1k}/1k tokens")
end
```

### Finding Models by Feature

```elixir
# Find all models with specific features
models = ExLLM.find_models_with_features([:vision, :streaming])
# => [
#   {:openai, "gpt-4o"},
#   {:anthropic, "claude-3-opus-20240229"},
#   ...
# ]

# Group models by capability
grouped = ExLLM.models_by_capability(:vision)
# => %{
#   supported: [{:openai, "gpt-4o"}, ...],
#   not_supported: [{:openai, "gpt-3.5-turbo"}, ...]
# }
```

### Comparing Models

```elixir
comparison = ExLLM.compare_models([
  {:openai, "gpt-4o"},
  {:anthropic, "claude-3-5-sonnet-20241022"},
  {:gemini, "gemini-1.5-pro"}
])

# See feature support across models
IO.inspect(comparison.features[:vision])
# => [
#   %{model: "gpt-4o", supported: true, details: %{...}},
#   %{model: "claude-3-5-sonnet", supported: true, details: %{...}},
#   %{model: "gemini-1.5-pro", supported: true, details: %{...}}
# ]
```

## Provider Capabilities

### Capability Normalization

ExLLM automatically normalizes different provider terminologies:

```elixir
# These all work and refer to the same capability
ExLLM.provider_supports?(:openai, :function_calling)     # => true
ExLLM.provider_supports?(:anthropic, :tool_use)          # => true
ExLLM.provider_supports?(:openai, :tools)                # => true

# Find providers using any terminology
ExLLM.find_providers_with_features([:tool_use])          # Works!
ExLLM.find_providers_with_features([:function_calling])  # Also works!
```

### Provider Discovery

```elixir
# Get provider capabilities
{:ok, caps} = ExLLM.get_provider_capabilities(:openai)
IO.inspect(caps)
# => %ExLLM.ProviderCapabilities.ProviderInfo{
#   id: :openai,
#   name: "OpenAI",
#   endpoints: [:chat, :embeddings, :images, ...],
#   features: [:streaming, :function_calling, ...],
#   limitations: %{max_file_size: 512MB, ...}
# }

# Find providers by feature
providers = ExLLM.find_providers_with_features([:embeddings, :streaming])
# => [:openai, :gemini, :bedrock, ...]

# Check authentication requirements
if ExLLM.provider_requires_auth?(:openai) do
  # Provider needs API key
end

# Check if provider is local
if ExLLM.is_local_provider?(:ollama) do
  # No API costs
end
```

### Provider Recommendations

```elixir
recommendations = ExLLM.recommend_providers(%{
  required_features: [:vision, :streaming],
  preferred_features: [:embeddings, :function_calling],
  exclude_providers: [:mock],
  prefer_local: false,
  prefer_free: false
})

for %{provider: provider, score: score, matched_features: features} <- recommendations do
  IO.puts("#{provider}: #{Float.round(score, 2)}")
  IO.puts("  Features: #{Enum.join(features, ", ")}")
end
```

### Comparing Providers

```elixir
comparison = ExLLM.compare_providers([:openai, :anthropic, :gemini])

# See all features across providers
IO.puts("All features: #{Enum.join(comparison.features, ", ")}")

# Check specific provider capabilities
openai_features = comparison.comparison.openai.features
# => [:streaming, :function_calling, :embeddings, ...]
```

## Logging

ExLLM provides a unified logging system with security features.

### Basic Logging

```elixir
alias ExLLM.Logger

# Log at different levels
Logger.debug("Starting chat request")
Logger.info("Chat completed in #{duration}ms")
Logger.warning("Rate limit approaching")
Logger.error("API request failed", error: reason)
```

### Structured Logging

```elixir
# Log with metadata
Logger.info("Chat completed",
  provider: :openai,
  model: "gpt-4o",
  tokens: 150,
  duration_ms: 523
)

# Context-aware logging
Logger.with_context(request_id: "abc123") do
  Logger.info("Processing request")
  # All logs in this block include request_id
end
```

### Security Features

```elixir
# API keys are automatically redacted
Logger.info("Using API key", api_key: "sk-1234567890")
# Logs: "Using API key [api_key: REDACTED]"

# Configure content filtering
Application.put_env(:ex_llm, :log_redact_messages, true)
```

### Configuration

```elixir
# In config/config.exs
config :ex_llm,
  log_level: :info,                    # Minimum level to log
  log_redact_keys: true,               # Redact API keys
  log_redact_messages: false,          # Don't log message content
  log_include_metadata: true,          # Include structured metadata
  log_filter_components: [:cache]      # Don't log from cache component
```

See the [Logger User Guide](LOGGER.md) for complete documentation.

## Testing with Mock Adapter

The mock adapter helps you test LLM integrations without making real API calls.

### Basic Mocking

```elixir
# Start the mock adapter
{:ok, _} = ExLLM.Adapters.Mock.start_link()

# Configure mock response
{:ok, response} = ExLLM.chat(:mock, messages,
  mock_response: "This is a mock response"
)

assert response.content == "This is a mock response"
```

### Dynamic Responses

```elixir
# Use a handler function
{:ok, response} = ExLLM.chat(:mock, messages,
  mock_handler: fn messages, _options ->
    last_message = List.last(messages)
    %ExLLM.Types.LLMResponse{
      content: "You said: #{last_message.content}",
      model: "mock-model",
      usage: %{input_tokens: 10, output_tokens: 20}
    }
  end
)
```

### Simulating Errors

```elixir
# Simulate specific errors
{:error, error} = ExLLM.chat(:mock, messages,
  mock_error: %ExLLM.Error{
    type: :rate_limit,
    message: "Rate limit exceeded",
    retry_after: 60
  }
)
```

### Streaming Mocks

```elixir
{:ok, stream} = ExLLM.stream_chat(:mock, messages,
  mock_chunks: [
    %{content: "Hello"},
    %{content: " world"},
    %{content: "!", finish_reason: "stop"}
  ],
  chunk_delay: 100  # Milliseconds between chunks
)

for chunk <- stream do
  IO.write(chunk.content || "")
end
```

### Request Capture

```elixir
# Capture requests for assertions
ExLLM.Adapters.Mock.clear_requests()

{:ok, _} = ExLLM.chat(:mock, messages,
  capture_requests: true,
  mock_response: "OK"
)

requests = ExLLM.Adapters.Mock.get_requests()
assert length(requests) == 1
assert List.first(requests).messages == messages
```

## Advanced Topics

### Custom Adapters

Create your own adapter for unsupported providers:

```elixir
defmodule MyApp.CustomAdapter do
  @behaviour ExLLM.Adapter
  
  @impl true
  def configured?(options) do
    # Check if adapter is properly configured
    config = get_config(options)
    config[:api_key] != nil
  end
  
  @impl true
  def default_model() do
    "custom-model-v1"
  end
  
  @impl true
  def chat(messages, options) do
    # Implement chat logic
    # Return {:ok, %ExLLM.Types.LLMResponse{}} or {:error, reason}
  end
  
  @impl true
  def stream_chat(messages, options) do
    # Return {:ok, stream} where stream yields StreamChunk structs
  end
  
  # Optional callbacks
  @impl true
  def list_models(options) do
    # Return {:ok, [%ExLLM.Types.Model{}]}
  end
  
  @impl true
  def embeddings(inputs, options) do
    # Return {:ok, %ExLLM.Types.EmbeddingResponse{}}
  end
end
```

### Stream Processing

Advanced stream handling:

```elixir
defmodule StreamProcessor do
  def process_with_buffer(provider, messages, opts) do
    {:ok, stream} = ExLLM.stream_chat(provider, messages, opts)
    
    stream
    |> Stream.scan("", fn chunk, buffer ->
      case chunk do
        %{content: nil} -> buffer
        %{content: text} -> buffer <> text
      end
    end)
    |> Stream.each(fn buffer ->
      # Process complete sentences
      if String.ends_with?(buffer, ".") do
        IO.puts("\nComplete: #{buffer}")
      end
    end)
    |> Stream.run()
  end
end
```

### Token Budget Management

Manage token usage across multiple requests:

```elixir
defmodule TokenBudget do
  use GenServer
  
  def init(budget) do
    {:ok, %{budget: budget, used: 0}}
  end
  
  def track_usage(pid, tokens) do
    GenServer.call(pid, {:track, tokens})
  end
  
  def handle_call({:track, tokens}, _from, state) do
    new_used = state.used + tokens
    if new_used <= state.budget do
      {:reply, :ok, %{state | used: new_used}}
    else
      {:reply, {:error, :budget_exceeded}, state}
    end
  end
end

# Use with ExLLM
{:ok, budget} = GenServer.start_link(TokenBudget, 10_000)

{:ok, response} = ExLLM.chat(:openai, messages)
:ok = TokenBudget.track_usage(budget, response.usage.total_tokens)
```

### Multi-Provider Routing

Route requests to different providers based on criteria:

```elixir
defmodule ProviderRouter do
  def route_request(messages, requirements) do
    cond do
      # Use local for development
      Mix.env() == :dev ->
        ExLLM.chat(:ollama, messages)
        
      # Use Groq for speed-critical requests
      requirements[:max_latency_ms] < 1000 ->
        ExLLM.chat(:groq, messages)
        
      # Use OpenAI for complex reasoning
      requirements[:complexity] == :high ->
        ExLLM.chat(:openai, messages, model: "gpt-4o")
        
      # Default to Anthropic
      true ->
        ExLLM.chat(:anthropic, messages)
    end
  end
end
```

### Batch Processing

Process multiple requests efficiently:

```elixir
defmodule BatchProcessor do
  def process_batch(items, opts \\ []) do
    # Use Task.async_stream for parallel processing
    items
    |> Task.async_stream(
      fn item ->
        ExLLM.chat(opts[:provider] || :openai, [
          %{role: "user", content: item}
        ])
      end,
      max_concurrency: opts[:concurrency] || 5,
      timeout: opts[:timeout] || 30_000
    )
    |> Enum.map(fn
      {:ok, {:ok, response}} -> {:ok, response}
      {:ok, {:error, reason}} -> {:error, reason}
      {:exit, reason} -> {:error, {:timeout, reason}}
    end)
  end
end
```

### Custom Configuration Management

Implement advanced configuration strategies:

```elixir
defmodule ConfigManager do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Load from multiple sources
    config = %{}
    |> load_from_env()
    |> load_from_file()
    |> load_from_vault()
    |> validate_config()
    
    {:ok, config}
  end
  
  def get_config(provider) do
    GenServer.call(__MODULE__, {:get, provider})
  end
  
  defp load_from_vault(config) do
    # Fetch from HashiCorp Vault, AWS Secrets Manager, etc.
    Map.merge(config, fetch_secrets())
  end
end
```

## Best Practices

1. **Always handle errors** - LLM APIs can fail for various reasons
2. **Use streaming for long responses** - Better user experience
3. **Enable caching for repeated queries** - Save costs
4. **Monitor token usage** - Stay within budget
5. **Use appropriate models** - Don't use GPT-4 for simple tasks
6. **Implement fallbacks** - Have backup providers ready
7. **Test with mocks** - Don't make API calls in tests
8. **Use context management** - Handle long conversations properly
9. **Track costs** - Monitor spending across providers
10. **Follow rate limits** - Respect provider limitations

## Troubleshooting

### Common Issues

1. **"API key not found"**
   - Check environment variables
   - Verify configuration provider is started
   - Use `ExLLM.configured?/1` to debug

2. **"Context length exceeded"**
   - Use context management strategies
   - Choose models with larger context windows
   - Truncate conversation history

3. **"Rate limit exceeded"**
   - Enable automatic retry
   - Implement backoff strategies
   - Consider multiple API keys

4. **"Stream interrupted"**
   - Enable stream recovery
   - Implement reconnection logic
   - Check network stability

5. **"Invalid response format"**
   - Check provider documentation
   - Verify model capabilities
   - Use appropriate options

### Debug Mode

Enable debug logging:

```elixir
# In config
config :ex_llm, :log_level, :debug

# Or at runtime
Logger.configure(level: :debug)
```

### Getting Help

- Check the [API documentation](https://hexdocs.pm/ex_llm)
- Review [example applications](../examples/)
- Open an issue on [GitHub](https://github.com/azmaveth/ex_llm)
- Read provider-specific documentation

## Additional Resources

- [Quick Start Guide](QUICKSTART.md) - Get started quickly
- [Provider Capabilities](PROVIDER_CAPABILITIES.md) - Detailed provider information
- [Logger Guide](LOGGER.md) - Logging system documentation
- [API Reference](https://hexdocs.pm/ex_llm) - Complete API documentation