#!/usr/bin/env elixir

# This example demonstrates how to use ExLLM's telemetry system for observability

# First, attach a handler to log all ExLLM events
:telemetry.attach_many(
  "ex-llm-logger",
  ExLLM.Telemetry.events(),
  fn event, measurements, metadata, _config ->
    IO.puts("\n🔍 Telemetry Event: #{inspect(event)}")
    IO.puts("📊 Measurements: #{inspect(measurements)}")
    IO.puts("📋 Metadata: #{inspect(metadata)}")
  end,
  nil
)

# Example 1: Basic chat with telemetry
IO.puts("\n=== Example 1: Basic Chat ===")

messages = [
  %{role: "user", content: "What is 2+2?"}
]

{:ok, response} = ExLLM.chat(:openai, messages, model: "gpt-4-turbo")
IO.puts("Response: #{response.content}")

# Example 2: Session with telemetry tracking
IO.puts("\n=== Example 2: Session Management ===")

# Create a new session (emits [:ex_llm, :session, :created])
session = ExLLM.Core.Session.new("anthropic", name: "Math Session")

# Add messages (emits [:ex_llm, :session, :message_added])
session = ExLLM.Core.Session.add_message(session, "user", "What is the capital of France?")
session = ExLLM.Core.Session.add_message(session, "assistant", "The capital of France is Paris.")

# Update token usage (emits [:ex_llm, :session, :token_usage_updated])
session = ExLLM.Core.Session.update_token_usage(session, %{input_tokens: 15, output_tokens: 10})

# Clear messages (emits [:ex_llm, :session, :cleared])
session = ExLLM.Core.Session.clear_messages(session)

# Example 3: Context window management
IO.puts("\n=== Example 3: Context Window ===")

# Create a very long conversation that might exceed context window
long_messages = for i <- 1..100 do
  %{
    role: if(rem(i, 2) == 0, do: "assistant", else: "user"),
    content: "This is message number #{i} with some content to fill up the context window."
  }
end

# This will emit [:ex_llm, :context, :window_exceeded] if messages are too long
case ExLLM.Core.Context.validate_context(long_messages, :openai, "gpt-4", max_tokens: 1000) do
  {:ok, token_count} ->
    IO.puts("Messages fit within context window: #{token_count} tokens")
  {:error, reason} ->
    IO.puts("Context validation failed: #{reason}")
end

# Truncate messages (emits [:ex_llm, :context, :truncation, :stop])
truncated = ExLLM.Core.Context.truncate_messages(long_messages, :openai, "gpt-4", 
  max_tokens: 1000,
  strategy: :smart
)
IO.puts("Truncated to #{length(truncated)} messages")

# Example 4: Streaming with telemetry
IO.puts("\n=== Example 4: Streaming ===")

stream_messages = [
  %{role: "user", content: "Count from 1 to 5"}
]

# Stream events emit [:ex_llm, :stream, :start], [:ex_llm, :stream, :chunk], [:ex_llm, :stream, :stop]
{:ok, stream} = ExLLM.stream_chat(:openai, stream_messages, model: "gpt-4-turbo")

for chunk <- stream do
  if chunk.content do
    IO.write(chunk.content)
  end
end
IO.puts("")

# Example 5: Cache telemetry
IO.puts("\n=== Example 5: Cache Operations ===")

cache_messages = [
  %{role: "user", content: "What is the weather?"}
]

# First call - cache miss (emits [:ex_llm, :cache, :miss] and [:ex_llm, :cache, :put])
{:ok, _} = ExLLM.chat(:openai, cache_messages, model: "gpt-4-turbo", cache: true)

# Second call - cache hit (emits [:ex_llm, :cache, :hit])
{:ok, _} = ExLLM.chat(:openai, cache_messages, model: "gpt-4-turbo", cache: true)

# Example 6: Using telemetry metrics
IO.puts("\n=== Example 6: Telemetry Metrics ===")

# You can use telemetry_metrics to aggregate data
# Here's how you would set up metrics reporters in your application:

IO.puts("""
To use telemetry_metrics in your application:

1. Add to your supervision tree:
   
   children = [
     {Telemetry.Metrics.ConsoleReporter, metrics: ExLLM.Telemetry.Metrics.metrics()}
   ]

2. Or use with Prometheus:
   
   children = [
     {TelemetryMetricsPrometheus, metrics: ExLLM.Telemetry.Metrics.metrics()}
   ]

3. Available metrics include:
   - Chat request counts and durations
   - Token usage statistics
   - Cache hit/miss ratios
   - Context truncation events
   - HTTP request performance
   - Cost tracking
""")

# Clean up - detach our handler
:telemetry.detach("ex-llm-logger")

IO.puts("\n✅ Telemetry example completed!")