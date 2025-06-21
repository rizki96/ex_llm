# ExLLM Unified API Guide

This guide provides comprehensive documentation for ExLLM's unified API, which offers a consistent interface across all supported LLM providers.

## Table of Contents

1. [Overview](#overview)
2. [Core Concepts](#core-concepts)
3. [Chat Completions](#chat-completions)
4. [Embeddings](#embeddings)
5. [Assistants](#assistants)
6. [Knowledge Bases](#knowledge-bases)
7. [File Management](#file-management)
8. [Fine-Tuning](#fine-tuning)
9. [Provider Capabilities](#provider-capabilities)
10. [Error Handling](#error-handling)
11. [Best Practices](#best-practices)

## Overview

ExLLM's unified API provides a single, consistent interface for interacting with multiple LLM providers. This means you can switch between providers with minimal code changes, while still accessing provider-specific features when needed.

### Key Benefits

- **Provider Agnostic**: Write code once, use with any provider
- **Automatic Capability Detection**: ExLLM handles provider limitations gracefully
- **Consistent Error Handling**: Standardized error responses across providers
- **Type Safety**: Comprehensive typespecs for all functions
- **Smart Defaults**: Sensible defaults for each provider

## Core Concepts

### Provider Selection

All ExLLM functions accept a provider atom as the first argument:

```elixir
# Supported providers
:openai        # OpenAI GPT models
:anthropic     # Anthropic Claude models
:gemini        # Google Gemini models
:groq          # Groq fast inference
:mistral       # Mistral AI models
:openrouter    # OpenRouter (300+ models)
:perplexity    # Perplexity online models
:ollama        # Local Ollama models
:lmstudio      # Local LM Studio
:bedrock       # AWS Bedrock
:bumblebee     # Local Bumblebee models
```

### Standard Options

Most functions accept these common options:

```elixir
# Model selection
model: "gpt-4"  # Override default model

# Generation parameters
temperature: 0.7      # Randomness (0.0-2.0)
max_tokens: 1000     # Maximum response length
top_p: 0.9          # Nucleus sampling
frequency_penalty: 0.0  # Reduce repetition
presence_penalty: 0.0   # Encourage diversity

# Advanced options
stream: true         # Enable streaming responses
timeout: 30_000     # Request timeout in ms
api_key: "..."      # Override API key
base_url: "..."     # Override base URL
```

## Chat Completions

The most common use case - generating text responses from conversations.

### Basic Chat

```elixir
# Simple message
{:ok, response} = ExLLM.chat(:openai, "Hello, how are you?")
IO.puts(response.content)

# With message history
messages = [
  %{role: "system", content: "You are a helpful assistant."},
  %{role: "user", content: "What is the capital of France?"}
]
{:ok, response} = ExLLM.chat(:anthropic, messages)
```

### Advanced Chat Options

```elixir
# With all options
{:ok, response} = ExLLM.chat(:openai, messages,
  model: "gpt-4-turbo",
  temperature: 0.3,
  max_tokens: 2000,
  system: "You are an expert programmer.",
  tools: [weather_tool()],
  response_format: %{type: "json_object"}
)

# Access response details
IO.puts(response.content)       # The generated text
IO.inspect(response.usage)      # Token usage
IO.inspect(response.cost)       # Cost calculation
IO.inspect(response.tool_calls) # Function calls
```

### Streaming Responses

```elixir
# Stream with callback
ExLLM.stream(:openai, messages, fn chunk ->
  IO.write(chunk.content)
end)

# Stream to enumerable
stream = ExLLM.stream(:anthropic, messages)
Enum.each(stream, fn chunk ->
  # Process each chunk
  process_chunk(chunk)
end)
```

### Function Calling

```elixir
# Define tools
tools = [
  %{
    type: "function",
    function: %{
      name: "get_weather",
      description: "Get current weather",
      parameters: %{
        type: "object",
        properties: %{
          location: %{type: "string"}
        },
        required: ["location"]
      }
    }
  }
]

# Chat with tools
{:ok, response} = ExLLM.chat(:openai, "What's the weather in Paris?",
  tools: tools,
  tool_choice: "auto"
)

# Handle tool calls
case response.tool_calls do
  [%{function: %{name: "get_weather", arguments: args}}] ->
    weather = get_actual_weather(args["location"])
    # Continue conversation with tool result
    ExLLM.chat(:openai, messages ++ [tool_response(weather)])
  _ ->
    response.content
end
```

## Embeddings

Generate and work with text embeddings for semantic search and similarity.

### Generate Embeddings

```elixir
# Single text
{:ok, response} = ExLLM.embeddings(:openai, "Hello world")
embedding = hd(response.embeddings)  # [0.123, -0.456, ...]

# Multiple texts
texts = ["First document", "Second document", "Third document"]
{:ok, response} = ExLLM.embeddings(:openai, texts)
embeddings = response.embeddings  # List of embedding vectors

# With options
{:ok, response} = ExLLM.embeddings(:openai, text,
  model: "text-embedding-3-large",
  dimensions: 1536  # OpenAI supports dimension reduction
)
```

### Similarity Search

```elixir
# Find similar items
items = [
  {"Document about cats", [0.1, 0.2, ...]},
  {"Document about dogs", [0.3, 0.4, ...]},
  {"Document about birds", [0.5, 0.6, ...]}
]

results = ExLLM.find_similar(query_embedding, items,
  top_k: 5,
  threshold: 0.7,
  metric: :cosine  # :cosine, :euclidean, :dot_product
)

# Results format
[
  %{item: {"Document about cats", [...]}, similarity: 0.95},
  %{item: {"Document about dogs", [...]}, similarity: 0.82}
]
```

### Embedding Index

```elixir
# Create searchable index
documents = [
  "Machine learning is fascinating",
  "Deep learning transforms AI",
  "Neural networks power modern AI"
]

{:ok, index} = ExLLM.Embeddings.create_index(:openai, documents)

# Search the index
{:ok, results} = ExLLM.Embeddings.search_index(index, "What is AI?",
  top_k: 3
)
```

## Assistants

Work with OpenAI's Assistants API for stateful, multi-turn conversations.

### Create and Manage Assistants

```elixir
# Create assistant
{:ok, assistant} = ExLLM.create_assistant(:openai,
  name: "Code Helper",
  instructions: "You are an expert programmer.",
  model: "gpt-4",
  tools: [%{type: "code_interpreter"}]
)

# List assistants
{:ok, list} = ExLLM.list_assistants(:openai)

# Update assistant
{:ok, updated} = ExLLM.update_assistant(:openai, assistant.id, %{
  name: "Advanced Code Helper",
  model: "gpt-4-turbo"
})

# Delete assistant
{:ok, _} = ExLLM.delete_assistant(:openai, assistant.id)
```

### Conversation Threads

```elixir
# Create thread
{:ok, thread} = ExLLM.create_thread(:openai)

# Add messages to thread
{:ok, message} = ExLLM.create_message(:openai, thread.id,
  "Can you help me write a sorting algorithm?"
)

# Run assistant on thread
{:ok, run} = ExLLM.run_assistant(:openai, thread.id, assistant.id)

# Check run status (polling required)
{:ok, status} = ExLLM.get_run(:openai, thread.id, run.id)
```

## Knowledge Bases

Semantic search and document management (currently Gemini only).

### Manage Knowledge Bases

```elixir
# Create knowledge base
{:ok, kb} = ExLLM.create_knowledge_base(:gemini, "product_docs",
  display_name: "Product Documentation",
  description: "Company product guides and manuals"
)

# List knowledge bases
{:ok, list} = ExLLM.list_knowledge_bases(:gemini)

# Delete knowledge base
{:ok, _} = ExLLM.delete_knowledge_base(:gemini, "product_docs")
```

### Document Management

```elixir
# Add document
{:ok, doc} = ExLLM.add_document(:gemini, "product_docs", %{
  display_name: "User Guide v2.0",
  text: "Complete user guide content...",
  metadata: %{
    version: "2.0",
    category: "user-guide",
    last_updated: "2024-01-15"
  }
})

# List documents
{:ok, docs} = ExLLM.list_documents(:gemini, "product_docs")

# Get specific document
{:ok, doc} = ExLLM.get_document(:gemini, "product_docs", doc_id)

# Delete document
{:ok, _} = ExLLM.delete_document(:gemini, "product_docs", doc_id)
```

### Semantic Search

```elixir
# Search knowledge base
{:ok, results} = ExLLM.semantic_search(:gemini, "product_docs",
  "How do I reset my password?",
  results_count: 5,
  metadata_filter: %{category: "user-guide"}
)

# Results include answer and sources
IO.puts(results.answer.answer)
IO.inspect(results.answer.grounding_attributions)
```

## File Management

Upload and manage files for use with various APIs.

### File Operations

```elixir
# Upload file
{:ok, file} = ExLLM.upload_file(:openai, "data.pdf",
  purpose: "assistants"  # or "fine-tune"
)

# List files
{:ok, files} = ExLLM.list_files(:openai,
  purpose: "assistants"
)

# Get file info
{:ok, file} = ExLLM.get_file(:openai, file_id)

# Download file content
{:ok, content} = ExLLM.get_file_content(:openai, file_id)

# Delete file
{:ok, _} = ExLLM.delete_file(:openai, file_id)
```

## Fine-Tuning

Create custom models through fine-tuning (provider-specific).

### Fine-Tuning Workflow

```elixir
# 1. Upload training data
{:ok, file} = ExLLM.upload_file(:openai, "training.jsonl",
  purpose: "fine-tune"
)

# 2. Create fine-tuning job
{:ok, job} = ExLLM.create_fine_tuning_job(:openai,
  training_file: file.id,
  model: "gpt-3.5-turbo",
  hyperparameters: %{
    n_epochs: 3,
    batch_size: 4
  }
)

# 3. Monitor job progress
{:ok, status} = ExLLM.get_fine_tuning_job(:openai, job.id)

# 4. List checkpoints/events
{:ok, events} = ExLLM.list_fine_tuning_events(:openai, job.id)

# 5. Use fine-tuned model
{:ok, response} = ExLLM.chat(:openai, messages,
  model: job.fine_tuned_model
)

# Cancel if needed
{:ok, _} = ExLLM.cancel_fine_tuning_job(:openai, job.id)
```

## Provider Capabilities

Check what features each provider supports:

```elixir
# Check specific capability
if ExLLM.supports?(:anthropic, :streaming) do
  # Use streaming
end

# Get all capabilities
capabilities = ExLLM.capabilities(:openai)
# Returns list like [:chat, :embeddings, :streaming, :function_calling, ...]

# Get models for capability
{:ok, models} = ExLLM.models_for_capability(:gemini, :embeddings)
```

## Error Handling

ExLLM provides consistent error handling across all providers:

```elixir
case ExLLM.chat(:openai, messages) do
  {:ok, response} ->
    process_response(response)
    
  {:error, %{type: :rate_limit, message: msg}} ->
    Logger.warning("Rate limited: #{msg}")
    # Implement backoff
    
  {:error, %{type: :invalid_request, message: msg}} ->
    Logger.error("Invalid request: #{msg}")
    # Fix request parameters
    
  {:error, %{type: :authentication, message: msg}} ->
    Logger.error("Auth failed: #{msg}")
    # Check API key
    
  {:error, %{type: :network, message: msg}} ->
    Logger.error("Network error: #{msg}")
    # Retry with backoff
    
  {:error, %{type: :unsupported, message: msg}} ->
    Logger.warning("Feature not supported: #{msg}")
    # Use alternative approach
end
```

### Common Error Types

- `:rate_limit` - API rate limit exceeded
- `:invalid_request` - Invalid parameters or format
- `:authentication` - Invalid or missing API key
- `:network` - Network or connection issues
- `:timeout` - Request timeout
- `:unsupported` - Feature not supported by provider
- `:context_length` - Message exceeds model limits
- `:server_error` - Provider server error

## Best Practices

### 1. Provider Selection

```elixir
# Use module attributes for easy switching
@provider :openai  # Easy to change

def generate_response(prompt) do
  ExLLM.chat(@provider, prompt)
end

# Or use configuration
provider = Application.get_env(:my_app, :llm_provider, :openai)
```

### 2. Error Recovery

```elixir
# Implement retry logic
def chat_with_retry(provider, messages, retries \\ 3) do
  case ExLLM.chat(provider, messages) do
    {:ok, response} ->
      {:ok, response}
      
    {:error, %{type: type}} = error when type in [:rate_limit, :timeout] and retries > 0 ->
      Process.sleep(1000 * (4 - retries))  # Exponential backoff
      chat_with_retry(provider, messages, retries - 1)
      
    error ->
      error
  end
end
```

### 3. Cost Management

```elixir
# Monitor costs
{:ok, response} = ExLLM.chat(:openai, messages)
Logger.info("Request cost: $#{response.cost.total_cost}")

# Use cheaper models for simple tasks
model = case complexity do
  :high -> "gpt-4"
  :medium -> "gpt-3.5-turbo"
  :low -> "gpt-3.5-turbo-instruct"
end
```

### 4. Context Management

```elixir
# Use sessions for conversation management
session = ExLLM.Session.new_session(:anthropic)

# Automatically manages context window
{:ok, response, session} = ExLLM.Session.chat_session(session, user_input,
  max_tokens: 1000,
  context_strategy: :sliding_window
)

# Save session for later
ExLLM.Session.save_session(session, "session_#{user_id}.json")
```

### 5. Provider Fallbacks

```elixir
# Implement provider fallbacks
def chat_with_fallback(messages) do
  providers = [:openai, :anthropic, :gemini]
  
  Enum.reduce_while(providers, {:error, "All providers failed"}, fn provider, _acc ->
    case ExLLM.chat(provider, messages) do
      {:ok, response} -> {:halt, {:ok, response}}
      {:error, _} -> {:cont, {:error, "All providers failed"}}
    end
  end)
end
```

## Advanced Usage

### Custom Headers and Middleware

```elixir
# Add custom headers
{:ok, response} = ExLLM.chat(:openai, messages,
  headers: [{"X-Custom-Header", "value"}],
  middleware: [
    {Tesla.Middleware.Retry, delay: 500, max_retries: 3}
  ]
)
```

### Streaming with Accumulation

```elixir
# Accumulate streaming response
{:ok, buffer} = Agent.start_link(fn -> "" end)

ExLLM.stream(:openai, messages, fn chunk ->
  Agent.update(buffer, &(&1 <> chunk.content))
  # Optional: Update UI with partial response
  Phoenix.PubSub.broadcast(MyApp.PubSub, "chat:#{chat_id}", {:chunk, chunk.content})
end)

complete_response = Agent.get(buffer, & &1)
Agent.stop(buffer)
```

### Batch Processing

```elixir
# Process multiple requests efficiently
prompts = ["Question 1", "Question 2", "Question 3"]

tasks = Enum.map(prompts, fn prompt ->
  Task.async(fn -> ExLLM.chat(:openai, prompt) end)
end)

results = Task.await_many(tasks, 30_000)
```

## Conclusion

ExLLM's unified API provides a powerful abstraction over multiple LLM providers while maintaining flexibility and provider-specific features. By following the patterns and best practices in this guide, you can build robust, provider-agnostic applications that leverage the best of each LLM service.

For more examples and detailed API documentation, see the module documentation for each component:

- `ExLLM` - Main module and chat functions
- `ExLLM.Embeddings` - Embedding operations
- `ExLLM.Assistants` - Assistant management
- `ExLLM.KnowledgeBase` - Semantic search
- `ExLLM.Builder` - Fluent interface
- `ExLLM.Session` - Conversation management