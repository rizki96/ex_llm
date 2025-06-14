# ExLLM Streaming Architecture

## Overview

ExLLM provides a unified streaming interface across all LLM providers, allowing real-time token-by-token responses. This document describes the streaming architecture and how to implement or use streaming functionality.

## Architecture Components

### 1. Core Streaming Interface

All adapters implement the streaming interface through:

```elixir
@callback stream_chat(messages :: list(map()), options :: keyword()) :: 
  {:ok, Enumerable.t()} | {:error, term()}
```

The returned stream yields `ExLLM.Types.StreamChunk` structs:

```elixir
defstruct [:content, :finish_reason, :model, :id, :metadata]
```

### 2. HTTPClient Streaming Support

The shared `HTTPClient` module provides unified HTTP streaming with:

- **Server-Sent Events (SSE) parsing**
- **Test response caching**
- **Error recovery**
- **Provider-specific handling**

Key functions:
- `HTTPClient.stream_request/5` - SSE streaming with callback
- `HTTPClient.post_stream/3` - Modern streaming with Req's into option

### 3. Streaming Patterns

#### Pattern 1: Direct HTTPClient Usage (Recommended)

Most adapters now use HTTPClient directly for streaming:

```elixir
# Example from Gemini adapter
callback = fn chunk_data ->
  case parse_streaming_chunk(chunk_data) do
    nil -> :ok
    chunk -> send(parent, {ref, {:chunk, chunk}})
  end
end

HTTPClient.stream_request(url, body, headers, callback,
  provider: :gemini,
  timeout: 60_000
)
```

#### Pattern 2: StreamingCoordinator (Advanced)

For adapters needing advanced features:

```elixir
StreamingCoordinator.start_stream(url, request, headers, callback,
  parse_chunk_fn: &parse_provider_chunk/1,
  recovery_id: stream_id
)
```

### 4. Provider Implementations

#### OpenAI/OpenAI-Compatible
- Uses HTTPClient.stream_request
- Parses JSON chunks in SSE format
- Supports function calls and tools

#### Anthropic
- Custom streaming with message events
- Handles content blocks and deltas

#### Gemini
- Unified through HTTPClient
- Parses Gemini-specific response format

#### Ollama
- NDJSON format (newline-delimited JSON)
- Handles completion with "done" flag

#### Others (Groq, Mistral, Perplexity)
- Use OpenAI-compatible format
- Leverage shared streaming infrastructure

## Implementation Guide

### Adding Streaming to a New Adapter

1. **Implement stream_chat callback**:

```elixir
@impl true
def stream_chat(messages, options \\ []) do
  # Validate and prepare request
  # ...
  
  # Create stream
  chunks_ref = make_ref()
  parent = self()
  
  # Define chunk callback
  callback = fn data ->
    case parse_chunk(data) do
      nil -> :ok
      chunk -> send(parent, {chunks_ref, {:chunk, chunk}})
    end
  end
  
  # Start streaming
  Task.start(fn ->
    case HTTPClient.stream_request(url, body, headers, callback, opts) do
      {:ok, :streaming} -> send(parent, {chunks_ref, :done})
      {:error, reason} -> send(parent, {chunks_ref, {:error, reason}})
    end
  end)
  
  # Return stream
  stream = Stream.resource(
    fn -> chunks_ref end,
    fn ref ->
      receive do
        {^ref, {:chunk, chunk}} -> {[chunk], ref}
        {^ref, :done} -> {:halt, ref}
        {^ref, {:error, error}} -> throw(error)
      after
        100 -> {[], ref}
      end
    end,
    fn _ -> :ok end
  )
  
  {:ok, stream}
end
```

2. **Implement chunk parser**:

```elixir
defp parse_chunk(data) when is_binary(data) do
  case Jason.decode(data) do
    {:ok, parsed} ->
      # Extract content from provider format
      content = get_in(parsed, ["choices", 0, "delta", "content"])
      
      %Types.StreamChunk{
        content: content,
        finish_reason: get_in(parsed, ["choices", 0, "finish_reason"])
      }
      
    {:error, _} -> nil
  end
end
```

## Usage Examples

### Basic Streaming

```elixir
{:ok, stream} = ExLLM.stream_chat(:openai, messages)

stream
|> Enum.each(fn chunk ->
  IO.write(chunk.content || "")
end)
```

### With Error Handling

```elixir
{:ok, stream} = ExLLM.stream_chat(:anthropic, messages)

try do
  for chunk <- stream do
    process_chunk(chunk)
  end
catch
  error -> handle_error(error)
end
```

### Collecting Full Response

```elixir
{:ok, stream} = ExLLM.stream_chat(:gemini, messages)

full_response = 
  stream
  |> Enum.map(& &1.content)
  |> Enum.filter(& &1)
  |> Enum.join("")
```

## Testing Streaming

ExLLM's test caching system supports streaming responses:

1. **Cached streaming responses are replayed**
2. **Timing is preserved for realistic testing**
3. **SSE format is maintained**

## Best Practices

1. **Always handle stream errors** - Streams can fail mid-response
2. **Use timeouts** - Network issues can cause hanging streams  
3. **Buffer wisely** - Don't accumulate entire streams in memory
4. **Test with caching** - Ensure consistent behavior

## Stream Recovery (Advanced)

ExLLM supports optional stream recovery for resuming interrupted streams:

```elixir
{:ok, stream} = ExLLM.stream_chat(:openai, messages,
  recovery: [
    enabled: true,
    strategy: :paragraph
  ]
)
```

See `ExLLM.StreamRecovery` for details.

## Debugging Streaming

Enable debug logging to see streaming details:

```elixir
config :ex_llm, :debug_logging,
  enabled: true,
  log_streaming: true
```

This will log:
- SSE events received
- Chunk parsing results
- Stream lifecycle events
- Error details