#!/usr/bin/env elixir
# Run with: elixir examples/streaming_metrics_example.exs

# Add the lib directory to the load path
Code.prepend_path("_build/dev/lib/ex_llm/ebin")

# Configure the application
Application.put_env(:ex_llm, :log_level, :info)
Application.ensure_all_started(:logger)
Application.ensure_all_started(:hackney)
Application.ensure_all_started(:telemetry)

defmodule StreamingMetricsExample do
  @moduledoc """
  Example demonstrating the streaming metrics collection capabilities.
  
  This example shows how to:
  - Enable metrics collection for streaming
  - Configure metrics callbacks
  - Track performance metrics in real-time
  - Handle different reporting intervals
  """

  alias ExLLM.Providers.Shared.Streaming.Engine

  def run do
    IO.puts("\n=== ExLLM Streaming Metrics Example ===\n")

    # Get API key from environment
    api_key = System.get_env("OPENAI_API_KEY")
    
    if !api_key do
      IO.puts("Error: OPENAI_API_KEY environment variable not set")
      IO.puts("Please set it with: export OPENAI_API_KEY=your-key-here")
      System.halt(1)
    end

    IO.puts("Starting streaming with metrics collection...\n")

    # Example 1: Basic metrics collection
    basic_metrics_example(api_key)
    Process.sleep(1000)

    # Example 2: Periodic metrics reporting
    periodic_metrics_example(api_key)
    Process.sleep(1000)

    # Example 3: Detailed metrics with raw chunks
    detailed_metrics_example(api_key)
    Process.sleep(1000)

    # Example 4: Performance comparison between providers
    if System.get_env("ANTHROPIC_API_KEY") do
      provider_comparison_example(api_key)
    end

    IO.puts("\n=== Examples completed ===")
  end

  defp basic_metrics_example(api_key) do
    IO.puts("\n--- Example 1: Basic Metrics Collection ---")

    # Create client with metrics enabled
    client = Engine.client(
      provider: :openai,
      api_key: api_key,
      enable_metrics: true,
      metrics_callback: &print_final_metrics/1
    )

    # Prepare request
    request = %{
      "model" => "gpt-3.5-turbo",
      "messages" => [
        %{"role" => "user", "content" => "Count from 1 to 10 slowly"}
      ],
      "stream" => true,
      "max_tokens" => 100
    }

    # Stream with metrics
    {:ok, stream_id} = Engine.stream(
      client,
      "/chat/completions",
      request,
      callback: &handle_chunk/1,
      parse_chunk: &parse_openai_chunk/1
    )

    # Wait for completion
    wait_for_stream_completion(stream_id)
  end

  defp periodic_metrics_example(api_key) do
    IO.puts("\n--- Example 2: Periodic Metrics Reporting ---")

    # Track metrics over time
    start_time = System.system_time(:millisecond)
    
    # Create client with periodic reporting
    client = Engine.client(
      provider: :openai,
      api_key: api_key,
      enable_metrics: true,
      metrics_callback: fn metrics ->
        elapsed = System.system_time(:millisecond) - start_time
        IO.puts("\n[#{elapsed}ms] Metrics Update:")
        IO.puts("  Chunks: #{metrics.chunks_received}")
        IO.puts("  Bytes: #{metrics.bytes_received}")
        IO.puts("  Rate: #{metrics.chunks_per_second} chunks/sec")
      end,
      metrics_interval: 500  # Report every 500ms
    )

    request = %{
      "model" => "gpt-3.5-turbo",
      "messages" => [
        %{"role" => "user", "content" => "Tell me a short story about a robot learning to paint"}
      ],
      "stream" => true,
      "max_tokens" => 300
    }

    {:ok, stream_id} = Engine.stream(
      client,
      "/chat/completions",
      request,
      callback: &handle_chunk_silent/1,
      parse_chunk: &parse_openai_chunk/1
    )

    wait_for_stream_completion(stream_id)
  end

  defp detailed_metrics_example(api_key) do
    IO.puts("\n--- Example 3: Detailed Metrics with Raw Chunks ---")

    chunk_contents = []
    
    client = Engine.client(
      provider: :openai,
      api_key: api_key,
      enable_metrics: true,
      include_raw_chunks: true,
      metrics_callback: fn metrics ->
        if metrics.status == :completed do
          IO.puts("\nDetailed Final Metrics:")
          IO.puts("  Provider: #{metrics.provider}")
          IO.puts("  Duration: #{metrics.duration_ms}ms")
          IO.puts("  Total chunks: #{metrics.chunks_received}")
          IO.puts("  Total bytes: #{metrics.bytes_received}")
          IO.puts("  Average chunk size: #{metrics.avg_chunk_size} bytes")
          IO.puts("  Throughput: #{metrics.bytes_per_second} bytes/sec")
          
          if raw_chunks = metrics[:raw_chunks] do
            IO.puts("  Raw chunk count: #{length(raw_chunks)}")
            
            # Analyze chunk distribution
            sizes = Enum.map(raw_chunks, fn chunk -> 
              byte_size(chunk.content || "")
            end)
            
            IO.puts("  Chunk size distribution:")
            IO.puts("    Min: #{Enum.min(sizes)} bytes")
            IO.puts("    Max: #{Enum.max(sizes)} bytes")
            IO.puts("    Avg: #{Float.round(Enum.sum(sizes) / length(sizes), 2)} bytes")
          end
        end
      end
    )

    request = %{
      "model" => "gpt-3.5-turbo",
      "messages" => [
        %{"role" => "user", "content" => "List 5 interesting facts about streaming data"}
      ],
      "stream" => true
    }

    {:ok, stream_id} = Engine.stream(
      client,
      "/chat/completions",
      request,
      callback: &handle_chunk_collect(&1, chunk_contents),
      parse_chunk: &parse_openai_chunk/1
    )

    wait_for_stream_completion(stream_id)
  end

  defp provider_comparison_example(openai_key) do
    IO.puts("\n--- Example 4: Provider Performance Comparison ---")
    
    anthropic_key = System.get_env("ANTHROPIC_API_KEY")
    
    providers = [
      {:openai, openai_key, "gpt-3.5-turbo", "/chat/completions"},
      {:anthropic, anthropic_key, "claude-3-haiku-20240307", "/v1/messages"}
    ]

    results = Enum.map(providers, fn {provider, key, model, path} ->
      IO.puts("\nTesting #{provider}...")
      
      metrics_ref = make_ref()
      
      client = Engine.client(
        provider: provider,
        api_key: key,
        enable_metrics: true,
        metrics_callback: fn metrics ->
          if metrics.status == :completed do
            send(self(), {metrics_ref, metrics})
          end
        end
      )

      request = build_request(provider, model, "Say hello in 3 words")

      {:ok, stream_id} = Engine.stream(
        client,
        path,
        request,
        callback: &handle_chunk_silent/1,
        parse_chunk: &parse_provider_chunk(provider, &1)
      )

      # Wait for metrics
      receive do
        {^metrics_ref, metrics} -> {provider, metrics}
      after
        10_000 -> {provider, nil}
      end
    end)

    # Compare results
    IO.puts("\n=== Performance Comparison ===")
    Enum.each(results, fn {provider, metrics} ->
      if metrics do
        IO.puts("\n#{provider}:")
        IO.puts("  Time to first chunk: ~#{metrics.duration_ms}ms")
        IO.puts("  Chunks per second: #{metrics.chunks_per_second}")
        IO.puts("  Bytes per second: #{metrics.bytes_per_second}")
        IO.puts("  Average chunk size: #{metrics.avg_chunk_size} bytes")
      else
        IO.puts("\n#{provider}: Failed to collect metrics")
      end
    end)
  end

  # Helper functions

  defp handle_chunk(chunk) do
    IO.write(chunk.content || "")
  end

  defp handle_chunk_silent(_chunk) do
    # Don't print, just process
    :ok
  end

  defp handle_chunk_collect(chunk, contents) do
    if chunk.content do
      Agent.update(contents, &[chunk.content | &1])
    end
  end

  defp print_final_metrics(metrics) do
    IO.puts("\n\nFinal Streaming Metrics:")
    IO.puts("  Stream ID: #{metrics.stream_id}")
    IO.puts("  Status: #{metrics.status}")
    IO.puts("  Duration: #{metrics.duration_ms}ms")
    IO.puts("  Chunks received: #{metrics.chunks_received}")
    IO.puts("  Bytes received: #{metrics.bytes_received}")
    IO.puts("  Chunks/second: #{metrics.chunks_per_second}")
    IO.puts("  Bytes/second: #{metrics.bytes_per_second}")
    
    if metrics.error_count > 0 do
      IO.puts("  Errors: #{metrics.error_count}")
      IO.puts("  Last error: #{inspect(metrics.last_error)}")
    end
  end

  defp wait_for_stream_completion(stream_id, timeout \\ 30_000) do
    wait_until = System.system_time(:millisecond) + timeout
    
    wait_loop = fn wait_loop ->
      case Engine.stream_status(stream_id) do
        {:ok, :completed} -> :ok
        {:ok, :running} ->
          if System.system_time(:millisecond) < wait_until do
            Process.sleep(100)
            wait_loop.(wait_loop)
          else
            IO.puts("\nWarning: Stream timeout")
          end
        {:error, :not_found} -> :ok
      end
    end
    
    wait_loop.(wait_loop)
  end

  defp parse_openai_chunk(data) do
    # Simplified OpenAI chunk parser
    with {:ok, json} <- Jason.decode(data),
         [choice | _] <- json["choices"],
         delta <- choice["delta"] do
      chunk = %ExLLM.Types.StreamChunk{
        content: delta["content"],
        finish_reason: choice["finish_reason"]
      }
      {:ok, chunk}
    else
      _ -> {:error, :parse_error}
    end
  end

  defp parse_provider_chunk(:openai, data), do: parse_openai_chunk(data)
  defp parse_provider_chunk(:anthropic, data) do
    # Simplified Anthropic parser
    with {:ok, json} <- Jason.decode(data) do
      case json["type"] do
        "content_block_delta" ->
          {:ok, %ExLLM.Types.StreamChunk{
            content: json["delta"]["text"],
            finish_reason: nil
          }}
        "message_stop" ->
          {:ok, %ExLLM.Types.StreamChunk{
            content: "",
            finish_reason: "stop"
          }}
        _ ->
          {:ok, nil}
      end
    else
      _ -> {:error, :parse_error}
    end
  end

  defp build_request(:openai, model, prompt) do
    %{
      "model" => model,
      "messages" => [%{"role" => "user", "content" => prompt}],
      "stream" => true,
      "max_tokens" => 50
    }
  end

  defp build_request(:anthropic, model, prompt) do
    %{
      "model" => model,
      "messages" => [%{"role" => "user", "content" => prompt}],
      "stream" => true,
      "max_tokens" => 50
    }
  end
end

# Run the example
StreamingMetricsExample.run()