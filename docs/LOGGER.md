# ExLLM Logger User Guide

The ExLLM Logger provides a unified logging system with features specifically designed for debugging and monitoring LLM interactions.

## Table of Contents

- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Basic Logging](#basic-logging)
- [Context Tracking](#context-tracking)
- [Structured Logging](#structured-logging)
- [Security & Redaction](#security--redaction)
- [Best Practices](#best-practices)

## Quick Start

```elixir
# Add the logger alias in your module
alias ExLLM.Logger

# Simple logging - just like Elixir's Logger!
Logger.info("Processing request")
Logger.error("Request failed", error: reason)
Logger.debug("Response received", tokens: 150)
```

## Configuration

Configure ExLLM logging in your `config/config.exs` or `config/runtime.exs`:

```elixir
config :ex_llm,
  # Overall log level: :debug, :info, :warn, :error, :none
  log_level: :info,
  
  # Control which components log
  log_components: %{
    requests: true,     # API request logging
    responses: true,    # API response logging
    streaming: false,   # Stream events (can be noisy)
    retries: true,      # Retry attempts
    cache: false,       # Cache hits/misses
    models: true        # Model loading events
  },
  
  # Security settings
  log_redaction: %{
    api_keys: true,     # Always redact API keys
    content: false      # Redact message content (recommended for production)
  }
```

### Environment-Specific Configuration

```elixir
# config/dev.exs
config :ex_llm,
  log_level: :debug,
  log_components: %{
    requests: true,
    responses: true,
    streaming: true,  # Enable in dev for debugging
    retries: true,
    cache: true,
    models: true
  },
  log_redaction: %{
    api_keys: true,
    content: false    # Show content in dev
  }

# config/prod.exs
config :ex_llm,
  log_level: :info,
  log_components: %{
    requests: false,  # Reduce noise in production
    responses: false,
    streaming: false,
    retries: true,    # Keep retry logs
    cache: false,
    models: true
  },
  log_redaction: %{
    api_keys: true,
    content: true     # Redact content in production
  }
```

## Basic Logging

The logger provides the same simple API as Elixir's Logger:

```elixir
alias ExLLM.Logger

# Log levels
Logger.debug("Detailed debugging info")
Logger.info("General information")
Logger.warn("Warning - something might be wrong")
Logger.error("Error occurred")

# With metadata
Logger.info("Request completed", 
  provider: :openai,
  duration_ms: 250,
  tokens: 1500
)

# Metadata is automatically included in log output
# 10:23:45.123 [info] Request completed [provider=openai duration_ms=250 tokens=1500 ex_llm=true]
```

## Context Tracking

Add context that automatically appears in all logs within a scope:

### Temporary Context (within a function)

```elixir
Logger.with_context(provider: :anthropic, operation: :chat) do
  Logger.info("Starting request")
  # ... do work ...
  Logger.info("Request completed", tokens: 150)
end
# Both logs automatically include provider=anthropic operation=chat
```

### Persistent Context (for a process)

```elixir
# Set context for the rest of this process
Logger.put_context(request_id: "abc123", user_id: "user456")

# All subsequent logs include this context
Logger.info("Processing")  # Includes request_id and user_id

# Clear context when done
Logger.clear_context()
```

### Real-World Example

```elixir
defmodule MyApp.LLMService do
  alias ExLLM.Logger
  
  def process_request(user_id, messages) do
    # Set process context
    Logger.put_context(user_id: user_id, request_id: generate_id())
    
    # Use scoped context for specific operations
    Logger.with_context(provider: :openai, operation: :chat) do
      Logger.info("Starting chat request")
      
      case ExLLM.chat(:openai, messages) do
        {:ok, response} ->
          Logger.info("Chat completed", 
            tokens: response.usage.total_tokens,
            cost: response.cost.total_cost
          )
          {:ok, response}
          
        {:error, reason} ->
          Logger.error("Chat failed", error: reason)
          {:error, reason}
      end
    end
  end
end
```

## Structured Logging

ExLLM provides specialized logging functions for common LLM operations:

### API Requests and Responses

```elixir
# Automatically redacts sensitive data
Logger.log_request(:openai, url, body, headers)
# Logs: API request [provider=openai url="..." method=POST ...]

Logger.log_response(:openai, response, duration_ms)
# Logs: API response [provider=openai duration_ms=250 status=200 ...]
```

### Streaming Events

```elixir
Logger.log_stream_event(:anthropic, :start, %{url: url})
Logger.log_stream_event(:anthropic, :chunk_received, %{size: 1024})
Logger.log_stream_event(:anthropic, :complete, %{total_chunks: 45})
Logger.log_stream_event(:anthropic, :error, %{reason: "timeout"})
```

### Retry Attempts

```elixir
Logger.log_retry(:openai, attempt, max_attempts, reason, delay_ms)
# Logs: Retry attempt 2/3 [provider=openai reason="rate_limit" delay_ms=2000 ...]
```

### Cache Operations

```elixir
Logger.log_cache_event(:hit, cache_key)
Logger.log_cache_event(:miss, cache_key)
Logger.log_cache_event(:put, cache_key, %{ttl: 300_000})
Logger.log_cache_event(:evict, cache_key, %{reason: :expired})
```

### Model Events

```elixir
Logger.log_model_event(:openai, :loading, %{model: "gpt-4"})
Logger.log_model_event(:openai, :loaded, %{model: "gpt-4", size_mb: 125})
Logger.log_model_event(:openai, :error, %{model: "gpt-4", error: "not found"})
```

## Security & Redaction

The logger automatically handles sensitive data based on your configuration:

### API Key Redaction (enabled by default)

```elixir
# Original
headers = [{"Authorization", "Bearer sk-1234567890abcdef"}]

# Logged as
# [headers=[{"Authorization", "***"}] ...]
```

### Content Redaction (optional)

```elixir
# When content redaction is enabled
body = %{"messages" => [%{"role" => "user", "content" => "sensitive data"}]}

# Logged as
# [body=%{"messages" => "[1 messages]"} ...]
```

### URL Parameter Redaction

```elixir
# API keys in URLs are automatically redacted
url = "https://api.example.com/v1/chat?api_key=secret123"

# Logged as
# [url="https://api.example.com/v1/chat?api_key=***" ...]
```

## Best Practices

### 1. Use Context for Request Tracking

```elixir
def handle_request(conn, params) do
  # Set context early
  Logger.put_context(
    request_id: conn.assigns.request_id,
    user_id: get_user_id(conn),
    endpoint: conn.request_path
  )
  
  # All logs in this request now have context
  process_request(params)
end
```

### 2. Use Appropriate Log Levels

```elixir
# Debug - Detailed information for debugging
Logger.debug("Parsing response", raw_response: response)

# Info - General operational information
Logger.info("Request completed", provider: provider, duration_ms: 250)

# Warn - Something unexpected but recoverable
Logger.warn("Rate limit approaching", remaining: 10, reset_at: timestamp)

# Error - Something failed
Logger.error("API request failed", error: reason, provider: provider)
```

### 3. Structure Your Metadata

```elixir
# Good - structured metadata
Logger.info("Operation completed",
  provider: :openai,
  operation: :chat,
  duration_ms: 250,
  tokens: %{input: 100, output: 200, total: 300}
)

# Less useful - unstructured
Logger.info("Operation completed for openai chat in 250ms with 300 tokens")
```

### 4. Configure for Your Environment

Development:
- Enable debug logging
- Show all components
- Don't redact content (easier debugging)

Production:
- Info or warn level only
- Disable noisy components (requests/responses)
- Enable content redaction
- Keep important events (retries, errors)

### 5. Use Structured Logging Functions

```elixir
# Instead of
Logger.info("Retrying request", provider: :openai, attempt: 2, ...)

# Use
Logger.log_retry(:openai, 2, 3, "rate_limit", 1000)
# Consistent structure and automatic metadata
```

## Filtering Logs

You can filter ExLLM logs using the metadata tag:

```elixir
# In your Logger backend configuration
config :logger, :console,
  metadata_filter: [ex_llm: false]  # Exclude ExLLM logs

# Or include only ExLLM logs
config :logger, :console,
  metadata_filter: [ex_llm: true]   # Only ExLLM logs
```

## Examples

### Complete Request Lifecycle Logging

```elixir
defmodule MyApp.AI do
  alias ExLLM.Logger
  
  def generate_summary(text, user_id) do
    # Set up context
    Logger.with_context(
      operation: :summary,
      user_id: user_id,
      request_id: UUID.uuid4()
    ) do
      Logger.info("Starting summary generation")
      
      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Summarize: #{text}"}
      ]
      
      # The actual API call (logging handled internally)
      case ExLLM.chat(:openai, messages) do
        {:ok, response} ->
          Logger.info("Summary generated",
            tokens: response.usage.total_tokens,
            cost_usd: response.cost.total_cost
          )
          {:ok, response.content}
          
        {:error, reason} ->
          Logger.error("Summary generation failed", error: reason)
          {:error, reason}
      end
    end
  end
end
```

### Custom Adapter Logging

```elixir
defmodule MyCustomAdapter do
  alias ExLLM.Logger
  
  def make_request(messages, options) do
    Logger.with_context(provider: :custom, operation: :chat) do
      url = build_url(options)
      body = build_body(messages, options)
      headers = build_headers(options)
      
      # Log the request
      Logger.log_request(:custom, url, body, headers)
      
      start_time = System.monotonic_time(:millisecond)
      
      case HTTPClient.post(url, body, headers) do
        {:ok, response} ->
          duration = System.monotonic_time(:millisecond) - start_time
          Logger.log_response(:custom, response, duration)
          parse_response(response)
          
        {:error, reason} ->
          Logger.error("Request failed", error: reason)
          {:error, reason}
      end
    end
  end
end
```

## Troubleshooting

### Logs Not Appearing

1. Check your log level configuration
2. Verify the component is enabled in `log_components`
3. Ensure your Logger backend is configured to show the appropriate level

### Too Many Logs

1. Disable noisy components (streaming, requests/responses)
2. Increase log level to :warn or :error
3. Use metadata filters to exclude ExLLM logs

### Missing Context

1. Ensure you're using `with_context` or `put_context`
2. Check that context is set before logging
3. Remember that context is process-specific

## Summary

The ExLLM Logger provides:
- **Simple API** - Works like Elixir's Logger
- **Automatic Context** - Track requests across operations
- **Security** - Built-in redaction for sensitive data
- **Structure** - Consistent logging for LLM operations
- **Control** - Fine-grained configuration options

Use it everywhere in your ExLLM applications for better debugging and monitoring!