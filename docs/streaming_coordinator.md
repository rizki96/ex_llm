# StreamingCoordinator - Advanced Streaming Features

The `ExLLM.Adapters.Shared.StreamingCoordinator` provides advanced streaming capabilities for LLM adapters, including metrics tracking, chunk transformation, validation, and recovery support.

## Features

### 1. Metrics Tracking

Track real-time streaming performance metrics:

```elixir
{:ok, stream} = ExLLM.stream_chat(:openai, messages,
  track_metrics: true,
  on_metrics: fn metrics ->
    IO.inspect(metrics, label: "Streaming metrics")
  end
)
```

Metrics include:
- `stream_id` - Unique stream identifier
- `provider` - LLM provider name
- `duration_ms` - Elapsed time
- `chunks_received` - Number of chunks processed
- `bytes_received` - Total bytes received
- `errors` - Error count
- `chunks_per_second` - Throughput rate
- `bytes_per_second` - Bandwidth usage

### 2. Chunk Transformation

Transform chunks before they reach your callback:

```elixir
transform_chunk = fn chunk ->
  # Example: Filter out empty chunks
  if chunk.content && String.trim(chunk.content) != "" do
    # Example: Add timestamp
    metadata = Map.put(chunk.metadata || %{}, :timestamp, DateTime.utc_now())
    {:ok, %{chunk | metadata: metadata}}
  else
    :skip  # Skip this chunk
  end
end

{:ok, stream} = ExLLM.stream_chat(:anthropic, messages,
  transform_chunk: transform_chunk
)
```

### 3. Chunk Validation

Validate chunks to ensure quality and safety:

```elixir
validate_chunk = fn chunk ->
  cond do
    # Check for inappropriate content
    chunk.content && contains_profanity?(chunk.content) ->
      {:error, "Content violates policy"}
    
    # Check chunk size
    chunk.content && String.length(chunk.content) > 1000 ->
      {:error, "Chunk too large"}
    
    true ->
      :ok
  end
end

{:ok, stream} = ExLLM.stream_chat(:gemini, messages,
  validate_chunk: validate_chunk
)
```

### 4. Chunk Buffering

Buffer chunks for batch processing:

```elixir
{:ok, stream} = ExLLM.stream_chat(:ollama, messages,
  buffer_chunks: 5  # Buffer 5 chunks before sending
)
```

### 5. Stream Recovery

Enable automatic recovery for interrupted streams:

```elixir
{:ok, stream} = ExLLM.stream_chat(:openai, messages,
  stream_recovery: true,
  recovery: [
    strategy: :paragraph,  # Resume from last paragraph
    max_retries: 3
  ]
)
```

### 6. Error Handling

Enhanced error handling with callbacks:

```elixir
on_error = fn status, body ->
  Logger.error("Stream error: #{status} - #{inspect(body)}")
  # Custom error handling
end

{:ok, stream} = ExLLM.stream_chat(:mistral, messages,
  on_error: on_error
)
```

## Using StreamingCoordinator Directly

For custom implementations:

```elixir
alias ExLLM.Adapters.Shared.StreamingCoordinator

# Simple streaming
StreamingCoordinator.simple_stream(
  url: "https://api.provider.com/v1/chat",
  request: request_body,
  headers: headers,
  callback: fn chunk -> process_chunk(chunk) end,
  parse_chunk: &parse_provider_chunk/1,
  options: [
    provider: :my_provider,
    track_metrics: true
  ]
)

# Advanced streaming
StreamingCoordinator.start_stream(
  url,
  request,
  headers,
  callback,
  parse_chunk_fn: &parse_chunk/1,
  provider: :my_provider,
  timeout: 120_000,
  stream_recovery: true,
  track_metrics: true,
  on_metrics: &log_metrics/1
)
```

## Implementing in an Adapter

Example adapter implementation with full StreamingCoordinator features:

```elixir
defmodule MyAdapter do
  @behaviour ExLLM.Adapter
  
  alias ExLLM.Adapters.Shared.StreamingCoordinator
  
  @impl true
  def stream_chat(messages, options \\ []) do
    # Validate and prepare request
    with {:ok, request} <- build_request(messages, options),
         {:ok, headers} <- build_headers() do
      
      # Setup stream
      chunks_ref = make_ref()
      parent = self()
      
      callback = fn chunk ->
        send(parent, {chunks_ref, {:chunk, chunk}})
      end
      
      # Configure advanced features
      stream_options = [
        parse_chunk_fn: &parse_chunk/1,
        provider: :my_provider,
        stream_recovery: Keyword.get(options, :stream_recovery, false),
        track_metrics: Keyword.get(options, :track_metrics, false),
        on_metrics: Keyword.get(options, :on_metrics),
        transform_chunk: create_transformer(options),
        validate_chunk: create_validator(options),
        buffer_chunks: Keyword.get(options, :buffer_chunks, 1),
        timeout: Keyword.get(options, :timeout, 300_000)
      ]
      
      case StreamingCoordinator.start_stream(url, request, headers, callback, stream_options) do
        {:ok, stream_id} ->
          # Create Elixir stream
          stream = Stream.resource(
            fn -> {chunks_ref, stream_id} end,
            fn state -> receive_chunks(state) end,
            fn _ -> :ok end
          )
          
          {:ok, stream}
          
        {:error, reason} ->
          {:error, reason}
      end
    end
  end
  
  defp receive_chunks({ref, stream_id} = state) do
    receive do
      {^ref, {:chunk, chunk}} -> 
        {[chunk], state}
    after
      100 -> 
        {[], state}
    end
  end
end
```

## Best Practices

1. **Enable metrics in development** to understand streaming performance
2. **Use validation** for user-facing applications
3. **Implement transformations** for data preprocessing
4. **Enable recovery** for critical applications
5. **Buffer chunks** when processing is expensive
6. **Set appropriate timeouts** based on expected response times

## Performance Considerations

- Metrics tracking adds minimal overhead (~1-2%)
- Transformations run inline, keep them fast
- Validation should be lightweight
- Buffering increases memory usage
- Recovery saves chunks to disk/memory

## Troubleshooting

Enable debug logging to see StreamingCoordinator internals:

```elixir
config :logger, :console,
  level: :debug,
  metadata: [:stream_id, :provider]
```

Common issues:
- **Timeouts**: Increase `:timeout` option
- **Memory usage**: Reduce `:buffer_chunks`
- **Recovery failures**: Check StreamRecovery process is running
- **Validation errors**: Log rejected chunks for analysis