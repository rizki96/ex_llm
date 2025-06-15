#!/usr/bin/env elixir
# Enhanced Streaming Example
# 
# This example demonstrates the new streaming infrastructure in ExLLM,
# including flow control, buffering, and intelligent batching.
#
# Usage: elixir examples/enhanced_streaming_example.exs

Mix.install([
  {:ex_llm, path: ".", runtime: false}
])

defmodule EnhancedStreamingExample do
  @moduledoc """
  Examples of using ExLLM's enhanced streaming capabilities.
  """

  alias ExLLM.Streaming.{StreamBuffer, FlowController, ChunkBatcher}

  def run do
    IO.puts("\n🚀 ExLLM Enhanced Streaming Examples\n")
    
    # Example 1: Basic circular buffer usage
    buffer_example()
    
    # Example 2: Flow control with backpressure
    flow_control_example()
    
    # Example 3: Intelligent chunk batching
    batching_example()
    
    # Example 4: Complete streaming pipeline
    complete_pipeline_example()
    
    # Example 5: Real LLM streaming with enhancements
    if System.get_env("ANTHROPIC_API_KEY") do
      real_streaming_example()
    else
      IO.puts("\n⚠️  Set ANTHROPIC_API_KEY to run real streaming example")
    end
  end

  defp buffer_example do
    IO.puts("📦 Example 1: Circular Buffer\n")
    
    # Create a buffer with capacity for 5 chunks
    buffer = StreamBuffer.new(5, overflow_strategy: :overwrite)
    
    # Simulate streaming chunks
    chunks = for i <- 1..8 do
      %ExLLM.Types.StreamChunk{content: "Chunk #{i}"}
    end
    
    # Push all chunks (buffer will overflow)
    final_buffer = Enum.reduce(chunks, buffer, fn chunk, buf ->
      case StreamBuffer.push(buf, chunk) do
        {:ok, new_buf} -> 
          IO.puts("✅ Added: #{chunk.content}")
          new_buf
        {:overflow, new_buf} -> 
          IO.puts("♻️  Overflow (overwriting oldest): #{chunk.content}")
          new_buf
      end
    end)
    
    # Check buffer stats
    stats = StreamBuffer.stats(final_buffer)
    IO.puts("\n📊 Buffer Stats:")
    IO.puts("   Size: #{stats.size}/#{stats.capacity}")
    IO.puts("   Fill: #{stats.fill_percentage}%")
    IO.puts("   Overflows: #{stats.overflow_count}")
    
    # Pop all remaining chunks
    IO.puts("\n📤 Popping chunks:")
    {chunks, _} = StreamBuffer.pop_many(final_buffer, 10)
    Enum.each(chunks, fn chunk ->
      IO.puts("   Retrieved: #{chunk.content}")
    end)
    
    IO.puts("\n" <> String.duplicate("-", 50) <> "\n")
  end

  defp flow_control_example do
    IO.puts("🚦 Example 2: Flow Control with Backpressure\n")
    
    # Simulate a slow consumer (like a terminal)
    slow_consumer = fn chunk ->
      IO.write(".")
      Process.sleep(100)  # Simulate slow I/O
    end
    
    # Start flow controller
    {:ok, controller} = FlowController.start_link(
      consumer: slow_consumer,
      buffer_capacity: 10,
      backpressure_threshold: 0.8,
      on_metrics: fn metrics ->
        IO.puts("\n📈 Metrics: #{metrics.chunks_delivered} delivered, " <>
               "#{metrics.backpressure_events} backpressure events")
      end
    )
    
    # Simulate fast producer
    IO.puts("Simulating fast producer with slow consumer...")
    
    task = Task.async(fn ->
      for i <- 1..20 do
        chunk = %ExLLM.Types.StreamChunk{content: "Fast chunk #{i}"}
        
        case FlowController.push_chunk(controller, chunk) do
          :ok -> 
            IO.write("✓")
          {:error, :backpressure} ->
            IO.write("⚠")
            Process.sleep(50)  # Back off when hitting backpressure
            # Retry
            FlowController.push_chunk(controller, chunk)
        end
        
        Process.sleep(10)  # Fast producer
      end
    end)
    
    Task.await(task)
    Process.sleep(500)  # Let consumer catch up
    
    # Get final metrics
    metrics = FlowController.get_metrics(controller)
    IO.puts("\n\n📊 Final Flow Control Metrics:")
    IO.puts("   Chunks received: #{metrics.chunks_received}")
    IO.puts("   Chunks delivered: #{metrics.chunks_delivered}")
    IO.puts("   Backpressure events: #{metrics.backpressure_events}")
    IO.puts("   Throughput: #{metrics.throughput_chunks_per_sec} chunks/sec")
    
    FlowController.complete_stream(controller)
    GenServer.stop(controller)
    
    IO.puts("\n" <> String.duplicate("-", 50) <> "\n")
  end

  defp batching_example do
    IO.puts("📦 Example 3: Intelligent Chunk Batching\n")
    
    # Track batches
    test_pid = self()
    
    {:ok, batcher} = ChunkBatcher.start_link(
      batch_size: 5,
      batch_timeout_ms: 100,
      adaptive: true,
      on_batch_ready: fn batch ->
        send(test_pid, {:batch, batch})
      end
    )
    
    IO.puts("Sending chunks with varying sizes and intervals...")
    
    # Send chunks with different patterns
    patterns = [
      # Small chunks quickly
      {1..5, 10, 50},
      # Large chunks slowly  
      {6..8, 200, 1000},
      # Mixed
      {9..12, 50, 100}
    ]
    
    for {range, delay, size} <- patterns do
      IO.puts("\nPattern: #{inspect(range)} with #{delay}ms delay, ~#{size} bytes")
      
      for i <- range do
        content = String.duplicate("x", size + :rand.uniform(100))
        chunk = %ExLLM.Types.StreamChunk{content: "Chunk #{i}: #{content}"}
        
        case ChunkBatcher.add_chunk(batcher, chunk) do
          :ok -> IO.write(".")
          {:batch_ready, batch} -> 
            IO.write("B")
            IO.puts(" [Batch of #{length(batch)} ready]")
        end
        
        Process.sleep(delay)
      end
    end
    
    # Final flush
    remaining = ChunkBatcher.flush(batcher)
    if length(remaining) > 0 do
      IO.puts("\nFlushed final #{length(remaining)} chunks")
    end
    
    # Get metrics
    metrics = ChunkBatcher.get_metrics(batcher)
    IO.puts("\n📊 Batching Metrics:")
    IO.puts("   Total chunks: #{metrics.chunks_batched}")
    IO.puts("   Batches created: #{metrics.batches_created}")
    IO.puts("   Average batch size: #{metrics.average_batch_size}")
    IO.puts("   Min/Max batch size: #{metrics.min_batch_size}/#{metrics.max_batch_size}")
    IO.puts("   Forced flushes: #{metrics.forced_flushes}")
    IO.puts("   Timeout flushes: #{metrics.timeout_flushes}")
    
    ChunkBatcher.stop(batcher)
    
    IO.puts("\n" <> String.duplicate("-", 50) <> "\n")
  end

  defp complete_pipeline_example do
    IO.puts("🔄 Example 4: Complete Streaming Pipeline\n")
    
    # Simulate complete pipeline with all components
    IO.puts("Building pipeline: Producer -> FlowController -> ChunkBatcher -> Terminal")
    
    # Terminal simulator with realistic delays
    terminal_write = fn text ->
      # Simulate variable terminal speed
      delay = 10 + :rand.uniform(20)
      Process.sleep(delay)
      IO.write(text)
    end
    
    # Start flow controller with batching
    {:ok, controller} = FlowController.start_link(
      consumer: terminal_write,
      buffer_capacity: 50,
      backpressure_threshold: 0.9,
      batch_config: [
        batch_size: 5,
        batch_timeout_ms: 50,
        min_batch_size: 3
      ]
    )
    
    # Simulate streaming text generation
    text = """
    The enhanced streaming infrastructure in ExLLM provides production-ready
    features for handling high-speed LLM responses. With circular buffers,
    flow control, and intelligent batching, applications can smoothly handle
    even the fastest models like Groq's Llama or Anthropic's Claude without
    dropping characters or overwhelming slow consumers.
    """
    
    IO.puts("\nStreaming text with realistic LLM speeds...\n")
    
    # Simulate LLM streaming chunks
    words = String.split(text)
    
    for {word, i} <- Enum.with_index(words) do
      chunk = %ExLLM.Types.StreamChunk{content: word <> " "}
      
      # Vary the speed to simulate real LLM behavior
      delay = case rem(i, 10) do
        0 -> 50   # Occasional pause
        _ -> 5    # Fast streaming
      end
      
      FlowController.push_chunk(controller, chunk)
      Process.sleep(delay)
    end
    
    # Send completion
    FlowController.push_chunk(controller, %ExLLM.Types.StreamChunk{
      content: "\n",
      finish_reason: "stop"
    })
    
    # Complete and get metrics
    FlowController.complete_stream(controller)
    
    status = FlowController.get_status(controller)
    IO.puts("\n\n📊 Pipeline Status:")
    IO.puts("   Status: #{status.status}")
    IO.puts("   Buffer utilization: #{status.buffer_fill_percentage}%")
    IO.puts("   Chunks delivered: #{status.metrics.chunks_delivered}")
    
    GenServer.stop(controller)
    
    IO.puts("\n" <> String.duplicate("-", 50) <> "\n")
  end

  defp real_streaming_example do
    IO.puts("🤖 Example 5: Real LLM Streaming with Enhancements\n")
    
    # This would integrate with the actual ExLLM streaming
    # For now, showing the configuration approach
    
    IO.puts("Configuration for enhanced streaming with ExLLM:")
    IO.puts("""
    
    # Direct streaming (current behavior)
    ExLLM.stream_chat(:anthropic, messages, fn chunk ->
      IO.write(chunk.content)
    end)
    
    # Enhanced streaming with flow control
    ExLLM.stream_chat(:anthropic, messages, fn chunk ->
      IO.write(chunk.content)
    end, streaming_options: [
      consumer_type: :managed,
      buffer_config: %{
        capacity: 100,
        overflow_strategy: :drop
      },
      batch_config: %{
        size: 5,
        timeout_ms: 25
      },
      flow_control: %{
        enabled: true,
        backpressure_threshold: 0.8
      },
      on_metrics: fn metrics ->
        # Log streaming performance
        Logger.debug("Streaming: \#{metrics.chunks_delivered} chunks, " <>
                    "\#{metrics.throughput_chunks_per_sec} chunks/sec")
      end
    ])
    
    # For slow terminals
    ExLLM.stream_chat(:groq, messages, fn chunk ->
      slow_terminal_write(chunk.content)
    end, streaming_options: [
      consumer_type: :managed,
      buffer_config: %{capacity: 200},
      batch_config: %{size: 10, timeout_ms: 50}
    ])
    """)
  end
end

# Run the examples
EnhancedStreamingExample.run()