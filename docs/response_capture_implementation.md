# Response Capture Implementation Guide

## Quick Start Implementation

### 1. Create Response Capture Module

```elixir
defmodule ExLLM.ResponseCapture do
  @moduledoc """
  Captures API responses for debugging and development purposes.
  
  This module extends the test caching infrastructure to capture
  and optionally display API responses during development.
  """
  
  alias ExLLM.Testing.LiveApiCacheStorage
  alias ExLLM.Testing.TestCacheConfig
  alias ExLLM.Infrastructure.Logger
  
  @capture_dir "captured_responses"
  
  def enabled? do
    System.get_env("EX_LLM_CAPTURE_RESPONSES") == "true"
  end
  
  def display_enabled? do
    System.get_env("EX_LLM_SHOW_CAPTURED") == "true"
  end
  
  @doc """
  Capture a response from an API call.
  """
  def capture_response(provider, endpoint, request, response, metadata \\ %{}) do
    if enabled?() do
      # Generate a simpler cache key for captures
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
      cache_key = "#{provider}/#{endpoint}/#{timestamp}"
      
      # Enhance metadata
      enhanced_metadata = Map.merge(metadata, %{
        provider: provider,
        endpoint: endpoint,
        captured_at: timestamp,
        environment: Mix.env(),
        request_summary: summarize_request(request)
      })
      
      # Store using existing infrastructure
      result = LiveApiCacheStorage.store(
        cache_key,
        response,
        enhanced_metadata
      )
      
      # Display if enabled
      if display_enabled?() do
        display_capture(response, enhanced_metadata)
      end
      
      result
    else
      :ok
    end
  end
  
  defp summarize_request(request) when is_map(request) do
    %{
      messages_count: length(Map.get(request, :messages, [])),
      model: Map.get(request, :model),
      temperature: Map.get(request, :temperature),
      max_tokens: Map.get(request, :max_tokens)
    }
  end
  
  defp summarize_request(_), do: %{}
  
  defp display_capture(response, metadata) do
    IO.puts(format_capture(response, metadata))
  end
  
  defp format_capture(response, metadata) do
    """
    
    #{IO.ANSI.cyan()}━━━━━ CAPTURED RESPONSE ━━━━━#{IO.ANSI.reset()}
    #{IO.ANSI.yellow()}Provider:#{IO.ANSI.reset()} #{metadata.provider}
    #{IO.ANSI.yellow()}Endpoint:#{IO.ANSI.reset()} #{metadata.endpoint}
    #{IO.ANSI.yellow()}Time:#{IO.ANSI.reset()} #{metadata.captured_at}
    #{IO.ANSI.yellow()}Duration:#{IO.ANSI.reset()} #{metadata[:response_time_ms] || "N/A"}ms
    
    #{format_usage(response)}
    #{format_cost(metadata)}
    
    #{IO.ANSI.green()}Response:#{IO.ANSI.reset()}
    #{format_response_content(response)}
    #{IO.ANSI.cyan()}━━━━━━━━━━━━━━━━━━━━━━━━━━━#{IO.ANSI.reset()}
    """
  end
  
  defp format_usage(response) do
    case extract_usage(response) do
      nil -> ""
      usage ->
        """
        #{IO.ANSI.yellow()}Tokens:#{IO.ANSI.reset()} #{usage.input_tokens} in / #{usage.output_tokens} out / #{usage.total_tokens} total
        """
    end
  end
  
  defp format_cost(metadata) do
    case Map.get(metadata, :cost) do
      nil -> ""
      cost ->
        """
        #{IO.ANSI.yellow()}Cost:#{IO.ANSI.reset()} $#{Float.round(cost, 4)}
        """
    end
  end
  
  defp format_response_content(response) when is_map(response) do
    case extract_content(response) do
      nil -> Jason.encode!(response, pretty: true)
      content -> content
    end
  end
  
  defp format_response_content(response), do: inspect(response, pretty: true)
  
  defp extract_usage(response) when is_map(response) do
    # Try different response formats
    cond do
      # OpenAI format
      usage = Map.get(response, "usage") ->
        %{
          input_tokens: Map.get(usage, "prompt_tokens", 0),
          output_tokens: Map.get(usage, "completion_tokens", 0),
          total_tokens: Map.get(usage, "total_tokens", 0)
        }
      
      # Anthropic format  
      usage = Map.get(response, "usage") ->
        %{
          input_tokens: Map.get(usage, "input_tokens", 0),
          output_tokens: Map.get(usage, "output_tokens", 0),
          total_tokens: (Map.get(usage, "input_tokens", 0) + Map.get(usage, "output_tokens", 0))
        }
        
      true -> nil
    end
  end
  
  defp extract_usage(_), do: nil
  
  defp extract_content(response) when is_map(response) do
    # Try to extract the actual message content
    cond do
      # OpenAI format
      choices = Map.get(response, "choices", []) ->
        case List.first(choices) do
          %{"message" => %{"content" => content}} -> content
          _ -> nil
        end
        
      # Anthropic format
      content = Map.get(response, "content", []) ->
        case List.first(content) do
          %{"text" => text} -> text
          _ -> nil
        end
        
      # Direct content
      content = Map.get(response, "content") ->
        content
        
      true -> nil
    end
  end
  
  defp extract_content(_), do: nil
end
```

### 2. Integrate with HTTP.Core

Modify `lib/ex_llm/providers/shared/http/core.ex` to add capture hooks:

```elixir
# In the Tesla.post callback handling:
defp handle_response({:ok, response} = result, provider, endpoint, request_body) do
  # Capture the response if enabled
  if ExLLM.ResponseCapture.enabled?() do
    Task.start(fn ->
      metadata = %{
        response_time_ms: response.opts[:response_time_ms] || 0,
        status_code: response.status,
        headers: response.headers
      }
      
      ExLLM.ResponseCapture.capture_response(
        provider,
        endpoint,
        request_body,
        response.body,
        metadata
      )
    end)
  end
  
  result
end
```

### 3. Create Mix Task for Management

```elixir
defmodule Mix.Tasks.ExLlm.Captures do
  @shortdoc "Manage captured API responses"
  
  @moduledoc """
  Manage captured API responses for debugging.
  
  ## Commands
  
      mix ex_llm.captures list [--provider PROVIDER] [--today] [--limit N]
      mix ex_llm.captures show TIMESTAMP
      mix ex_llm.captures clear [--older-than DAYS]
      mix ex_llm.captures stats
  
  ## Examples
  
      # List recent captures
      mix ex_llm.captures list --limit 10
      
      # Show specific capture
      mix ex_llm.captures show 2024-01-15T10-30-45
      
      # Clear old captures
      mix ex_llm.captures clear --older-than 7
  """
  
  use Mix.Task
  alias ExLLM.Testing.LiveApiCacheStorage
  
  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:ex_llm)
    
    case args do
      ["list" | opts] -> list_captures(opts)
      ["show", timestamp] -> show_capture(timestamp)
      ["clear" | opts] -> clear_captures(opts)
      ["stats"] -> show_stats()
      _ -> show_help()
    end
  end
  
  defp list_captures(opts) do
    {parsed, _, _} = OptionParser.parse(opts, 
      switches: [provider: :string, today: :boolean, limit: :integer]
    )
    
    cache_keys = LiveApiCacheStorage.list_cache_keys()
    |> filter_captures()
    |> filter_by_provider(parsed[:provider])
    |> filter_by_date(parsed[:today])
    |> limit_results(parsed[:limit] || 20)
    
    if Enum.empty?(cache_keys) do
      Mix.shell().info("No captures found")
    else
      Mix.shell().info("Recent captures:")
      Enum.each(cache_keys, &display_capture_summary/1)
    end
  end
  
  defp filter_captures(keys) do
    # Filter to only captured responses (not test cache)
    Enum.filter(keys, &String.starts_with?(&1, "captured_responses/"))
  end
  
  defp show_capture(timestamp) do
    # Implementation to show specific capture
    Mix.shell().info("Showing capture: #{timestamp}")
  end
  
  defp clear_captures(opts) do
    {parsed, _, _} = OptionParser.parse(opts, 
      switches: [older_than: :integer]
    )
    
    older_than_days = parsed[:older_than] || 7
    Mix.shell().info("Clearing captures older than #{older_than_days} days...")
    
    # Use LiveApiCacheStorage cleanup functionality
    :ok
  end
  
  defp show_stats do
    stats = LiveApiCacheStorage.get_stats(:all)
    
    Mix.shell().info("""
    Capture Statistics:
    Total Captures: #{stats.total_entries}
    Total Size: #{format_bytes(stats.total_size)}
    Oldest: #{stats.oldest_entry || "N/A"}
    Newest: #{stats.newest_entry || "N/A"}
    """)
  end
  
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
end
```

### 4. Configuration Updates

Add to `config/dev.exs`:

```elixir
# Response capture configuration for development
config :ex_llm, :response_capture,
  enabled: System.get_env("EX_LLM_CAPTURE_RESPONSES") == "true",
  display: System.get_env("EX_LLM_SHOW_CAPTURED") == "true",
  storage_dir: "captured_responses",
  max_captures: 1000,
  cleanup_after_days: 30

# Extend test cache config for captures
config :ex_llm, :test_cache,
  capture_mode: %{
    enabled: System.get_env("EX_LLM_CAPTURE_RESPONSES") == "true",
    cache_dir: "captured_responses",
    ttl: :infinity,
    organization: :by_timestamp,
    deduplicate_content: false
  }
```

### 5. Integration Example

```elixir
# In your application code:
defmodule MyApp.LLMClient do
  def chat_with_capture(messages, opts \\ []) do
    # Normal ExLLM call - capture happens automatically if enabled
    result = ExLLM.chat(messages, opts)
    
    # The response is automatically captured and displayed
    # based on environment variables
    
    result
  end
end
```

## Usage Guide

### Enable Response Capture

```bash
# Enable capture without display
export EX_LLM_CAPTURE_RESPONSES=true

# Enable capture with display
export EX_LLM_CAPTURE_RESPONSES=true
export EX_LLM_SHOW_CAPTURED=true

# Run your application
iex -S mix
```

### View Captured Responses

```bash
# List recent captures
mix ex_llm.captures list

# List captures from specific provider
mix ex_llm.captures list --provider openai

# Show specific capture
mix ex_llm.captures show 2024-01-15T10-30-45

# View statistics
mix ex_llm.captures stats

# Clean up old captures
mix ex_llm.captures clear --older-than 7
```

### Terminal Output Example

When `EX_LLM_SHOW_CAPTURED=true`:

```
━━━━━ CAPTURED RESPONSE ━━━━━
Provider: openai
Endpoint: v1/chat/completions
Time: 2024-01-15T10:30:45.123Z
Duration: 1523ms

Tokens: 150 in / 245 out / 395 total
Cost: $0.0123

Response:
Hello! I'm Claude, an AI assistant. How can I help you today?
━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Advanced Features

### 1. Filtering Captures

Add provider and endpoint filtering:

```elixir
defmodule ExLLM.ResponseCapture.Filter do
  def should_capture?(provider, endpoint) do
    allowed_providers = parse_env_list("EX_LLM_CAPTURE_PROVIDERS")
    allowed_endpoints = parse_env_list("EX_LLM_CAPTURE_ENDPOINTS")
    
    provider_allowed = Enum.empty?(allowed_providers) or provider in allowed_providers
    endpoint_allowed = Enum.empty?(allowed_endpoints) or endpoint in allowed_endpoints
    
    provider_allowed and endpoint_allowed
  end
  
  defp parse_env_list(env_var) do
    case System.get_env(env_var) do
      nil -> []
      value -> String.split(value, ",") |> Enum.map(&String.trim/1)
    end
  end
end
```

### 2. Response Sampling

For high-volume environments:

```elixir
defmodule ExLLM.ResponseCapture.Sampler do
  @sample_rate 0.1  # Capture 10% of responses
  
  def should_sample? do
    :rand.uniform() < sample_rate()
  end
  
  defp sample_rate do
    case System.get_env("EX_LLM_CAPTURE_SAMPLE_RATE") do
      nil -> @sample_rate
      value -> String.to_float(value)
    end
  end
end
```

### 3. Export Functionality

Export captures for analysis:

```elixir
defmodule ExLLM.ResponseCapture.Export do
  def export_to_jsonl(output_file, filters \\ %{}) do
    captures = load_filtered_captures(filters)
    
    File.open!(output_file, [:write], fn file ->
      Enum.each(captures, fn capture ->
        IO.write(file, Jason.encode!(capture) <> "\n")
      end)
    end)
  end
  
  def export_to_csv(output_file, filters \\ %{}) do
    # Export summary data to CSV
  end
end
```

## Testing

Add tests for the capture functionality:

```elixir
defmodule ExLLM.ResponseCaptureTest do
  use ExUnit.Case
  
  setup do
    # Enable capture for tests
    System.put_env("EX_LLM_CAPTURE_RESPONSES", "true")
    System.put_env("EX_LLM_SHOW_CAPTURED", "false")
    
    on_exit(fn ->
      System.delete_env("EX_LLM_CAPTURE_RESPONSES")
      System.delete_env("EX_LLM_SHOW_CAPTURED")
    end)
    
    :ok
  end
  
  test "captures responses when enabled" do
    # Test implementation
  end
  
  test "skips capture when disabled" do
    System.put_env("EX_LLM_CAPTURE_RESPONSES", "false")
    # Test implementation
  end
end
```

## Performance Considerations

1. **Async Capture**: Use `Task.start` to avoid blocking API calls
2. **Sampling**: Implement sampling for high-volume production use
3. **Cleanup**: Automatic cleanup of old captures to manage disk space
4. **Compression**: Consider compressing older captures

## Security Notes

1. **Sanitization**: The existing system already sanitizes API keys
2. **Access Control**: Captures should be in gitignored directories
3. **Production**: Consider disabling in production environments
4. **PII**: Be careful about capturing personally identifiable information

## Next Steps

1. Implement the basic ResponseCapture module
2. Add integration hooks to HTTP.Core
3. Create the Mix task for management
4. Test with different providers
5. Add advanced features based on usage feedback