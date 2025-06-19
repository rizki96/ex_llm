#!/usr/bin/env elixir

# Comprehensive Advanced Streaming Example
# Demonstrates all streaming features: basic, coordination, enhanced infrastructure, and comparisons

Mix.install([
  {:ex_llm, path: "."}
])

defmodule ComprehensiveStreamingExample do
  alias ExLLM.Providers.Shared.{StreamingCoordinator, EnhancedStreamingCoordinator}
  alias ExLLM.Infrastructure.Streaming.{StreamBuffer, FlowController, ChunkBatcher}
  
  @doc """
  Complete demonstration of all streaming capabilities in ExLLM
  """
  def run do
    IO.puts("🚀 ExLLM Comprehensive Streaming Example")
    IO.puts("=" <> String.duplicate("=", 60) <> "\n")
    
    # Basic streaming
    basic_streaming_example()
    separator()
    
    # StreamingCoordinator features
    coordinator_features_example()
    separator()
    
    # Enhanced infrastructure
    enhanced_infrastructure_example()
    separator()
    
    # Performance comparison
    performance_comparison_example()
    separator()
    
    # Advanced combined features
    advanced_combined_example()
    
    IO.puts("\n✅ All streaming examples completed!")
  end
  
  # ============================================================================
  # 1. BASIC STREAMING
  # ============================================================================
  
  defp basic_streaming_example do
    IO.puts("📡 1. Basic Streaming Example")
    IO.puts("Simple streaming across different providers\n")
    
    messages = [%{role: "user", content: "Tell me a short joke"}]
    
    # OpenAI streaming
    IO.puts("🔹 OpenAI Streaming:")
    stream_with_provider(:openai, messages, "gpt-4.1-nano")
    
    # Mock provider for testing
    IO.puts("\n🔹 Mock Provider Streaming:")
    stream_with_provider(:mock, messages, "mock-model")
  end
  
  defp stream_with_provider(provider, messages, model) do
    case ExLLM.stream_chat(provider, messages, model: model) do
      {:ok, stream} ->
        IO.write("Response: ")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("\n")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  # ============================================================================
  # 2. STREAMING COORDINATOR FEATURES
  # ============================================================================
  
  defp coordinator_features_example do
    IO.puts("🎯 2. StreamingCoordinator Advanced Features")
    IO.puts("Metrics tracking, transformation, buffering, and validation\n")
    
    # Metrics tracking
    streaming_with_metrics()
    IO.puts("")
    
    # Chunk transformation
    streaming_with_transformation()
    IO.puts("")
    
    # Buffering
    streaming_with_buffering()
    IO.puts("")
    
    # Validation
    streaming_with_validation()
  end
  
  defp streaming_with_metrics do
    IO.puts("📊 Streaming with Real-time Metrics")
    
    messages = [%{role: "user", content: "Count from 1 to 5"}]
    
    # Metrics callback
    on_metrics = fn metrics ->
      IO.write("\r📈 Metrics: #{metrics.chunks_received} chunks, " <>
              "#{metrics.bytes_received} bytes, " <>
              "#{Float.round(metrics.chunks_per_second, 2)} chunks/sec")
    end
    
    case ExLLM.stream_chat(:mock, messages,
           model: "mock-model",
           track_metrics: true,
           on_metrics: on_metrics) do
      {:ok, stream} ->
        Enum.each(stream, fn chunk ->
          if chunk.content do
            IO.write(chunk.content)
            Process.sleep(100) # Simulate processing delay
          end
        end)
        IO.puts("\n")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  defp streaming_with_transformation do
    IO.puts("🔄 Streaming with Chunk Transformation")
    IO.puts("Adding emoji indicators to streaming chunks")
    
    messages = [%{role: "user", content: "Say hello"}]
    
    # Transformation function
    transform_chunk = fn chunk ->
      if chunk.content && String.trim(chunk.content) != "" do
        {:ok, %{chunk | content: "✨#{chunk.content}"}}
      else
        {:ok, chunk}
      end
    end
    
    case ExLLM.stream_chat(:mock, messages,
           model: "mock-model",
           transform_chunk: transform_chunk) do
      {:ok, stream} ->
        IO.write("Transformed: ")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  defp streaming_with_buffering do
    IO.puts("🔢 Streaming with Chunk Buffering")
    IO.puts("Buffering chunks before processing")
    
    messages = [%{role: "user", content: "List: apple, banana, cherry"}]
    
    case ExLLM.stream_chat(:mock, messages,
           model: "mock-model",
           buffer_chunks: 3) do
      {:ok, stream} ->
        IO.write("Buffered output: ")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  defp streaming_with_validation do
    IO.puts("✅ Streaming with Content Validation")
    IO.puts("Validating chunks meet quality criteria")
    
    messages = [%{role: "user", content: "Say something positive"}]
    
    # Validation function
    validate_chunk = fn chunk ->
      if chunk.content && String.length(chunk.content) > 0 do
        :ok
      else
        {:error, "Empty content not allowed"}
      end
    end
    
    case ExLLM.stream_chat(:mock, messages,
           model: "mock-model",
           validate_chunk: validate_chunk) do
      {:ok, stream} ->
        IO.write("Validated: ")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  # ============================================================================
  # 3. ENHANCED INFRASTRUCTURE
  # ============================================================================
  
  defp enhanced_infrastructure_example do
    IO.puts("🏗️ 3. Enhanced Streaming Infrastructure")
    IO.puts("StreamBuffer, FlowController, and ChunkBatcher\n")
    
    demonstrate_stream_buffer()
    IO.puts("")
    
    demonstrate_flow_controller()
    IO.puts("")
    
    demonstrate_chunk_batcher()
  end
  
  defp demonstrate_stream_buffer do
    IO.puts("🗂️ StreamBuffer Example")
    IO.puts("Intelligent buffering with configurable strategies")
    
    # Create a buffer with specific configuration
    {:ok, buffer_pid} = StreamBuffer.start_link([
      strategy: :line_based,
      max_size: 1024,
      flush_interval: 1000
    ])
    
    # Simulate adding chunks to buffer
    chunks = ["Hello ", "streaming ", "world!", "\n", "Next line here."]
    
    IO.write("Buffering: ")
    Enum.each(chunks, fn chunk ->
      StreamBuffer.add_chunk(buffer_pid, chunk)
      IO.write(".")
      Process.sleep(200)
    end)
    
    # Flush and get results
    buffered_content = StreamBuffer.flush(buffer_pid)
    IO.puts("\nBuffered result: #{inspect(buffered_content)}")
    
    GenServer.stop(buffer_pid)
  end
  
  defp demonstrate_flow_controller do
    IO.puts("🌊 FlowController Example")
    IO.puts("Intelligent backpressure management")
    
    # Create flow controller
    {:ok, controller_pid} = FlowController.start_link([
      max_buffer_size: 100,
      target_latency: 50
    ])
    
    # Simulate high-frequency data
    IO.write("Flow control: ")
    Enum.each(1..10, fn i ->
      case FlowController.should_throttle?(controller_pid) do
        true ->
          IO.write("⏸️")
          Process.sleep(100) # Throttle
        false ->
          IO.write("⚡")
      end
      
      FlowController.record_chunk(controller_pid, "chunk_#{i}")
      Process.sleep(50)
    end)
    
    stats = FlowController.get_stats(controller_pid)
    IO.puts("\nFlow stats: #{inspect(stats)}")
    
    GenServer.stop(controller_pid)
  end
  
  defp demonstrate_chunk_batcher do
    IO.puts("📦 ChunkBatcher Example")
    IO.puts("Batching chunks for efficient processing")
    
    # Create batcher
    {:ok, batcher_pid} = ChunkBatcher.start_link([
      batch_size: 3,
      flush_interval: 2000
    ])
    
    # Set up batch handler
    handler = fn batch ->
      IO.puts("Batch received: #{Enum.join(batch, " | ")}")
    end
    
    ChunkBatcher.set_handler(batcher_pid, handler)
    
    # Add chunks
    chunks = ["chunk1", "chunk2", "chunk3", "chunk4", "chunk5"]
    IO.puts("Adding chunks...")
    
    Enum.each(chunks, fn chunk ->
      ChunkBatcher.add_chunk(batcher_pid, chunk)
      Process.sleep(500)
    end)
    
    # Flush remaining
    ChunkBatcher.flush(batcher_pid)
    
    GenServer.stop(batcher_pid)
  end
  
  # ============================================================================
  # 4. PERFORMANCE COMPARISON
  # ============================================================================
  
  defp performance_comparison_example do
    IO.puts("⚡ 4. Performance Comparison")
    IO.puts("Standard vs Enhanced streaming performance\n")
    
    messages = [%{role: "user", content: "Generate a short paragraph about AI"}]
    
    # Standard streaming
    IO.puts("🔹 Standard Streaming Performance:")
    {time_standard, _result} = :timer.tc(fn ->
      case ExLLM.stream_chat(:mock, messages, model: "mock-model") do
        {:ok, stream} ->
          chunk_count = Enum.count(stream)
          IO.puts("  Processed #{chunk_count} chunks")
        {:error, reason} ->
          IO.puts("  Error: #{inspect(reason)}")
      end
    end)
    
    IO.puts("  Time: #{Float.round(time_standard / 1000, 2)}ms")
    
    # Enhanced streaming
    IO.puts("\n🔹 Enhanced Streaming Performance:")
    {time_enhanced, _result} = :timer.tc(fn ->
      case ExLLM.stream_chat(:mock, messages,
             model: "mock-model",
             track_metrics: true,
             buffer_chunks: 2) do
        {:ok, stream} ->
          chunk_count = Enum.count(stream)
          IO.puts("  Processed #{chunk_count} chunks with metrics & buffering")
        {:error, reason} ->
          IO.puts("  Error: #{inspect(reason)}")
      end
    end)
    
    IO.puts("  Time: #{Float.round(time_enhanced / 1000, 2)}ms")
    
    # Calculate overhead
    overhead = ((time_enhanced - time_standard) / time_standard) * 100
    IO.puts("\n📊 Performance overhead: #{Float.round(overhead, 2)}%")
  end
  
  # ============================================================================
  # 5. ADVANCED COMBINED FEATURES
  # ============================================================================
  
  defp advanced_combined_example do
    IO.puts("🎪 5. Advanced Combined Features")
    IO.puts("All streaming features working together\n")
    
    messages = [%{role: "user", content: "Explain streaming in one sentence"}]
    
    # Combined metrics callback
    on_metrics = fn metrics ->
      IO.write("\r🔄 #{metrics.chunks_received} chunks processed")
    end
    
    # Combined transformation
    transform_chunk = fn chunk ->
      if chunk.content do
        enhanced_content = String.replace(chunk.content, ~r/\b(streaming|stream)\b/i, "🌊\\1🌊")
        {:ok, %{chunk | content: enhanced_content}}
      else
        {:ok, chunk}
      end
    end
    
    # Combined validation
    validate_chunk = fn chunk ->
      if chunk.content && String.length(String.trim(chunk.content)) > 0 do
        :ok
      else
        {:error, "Invalid chunk content"}
      end
    end
    
    IO.puts("Using combined: metrics + transformation + validation + buffering")
    
    case ExLLM.stream_chat(:mock, messages,
           model: "mock-model",
           track_metrics: true,
           on_metrics: on_metrics,
           transform_chunk: transform_chunk,
           validate_chunk: validate_chunk,
           buffer_chunks: 2) do
      {:ok, stream} ->
        IO.write("\nResult: ")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("\n")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  # ============================================================================
  # UTILITIES
  # ============================================================================
  
  defp separator do
    IO.puts("\n" <> String.duplicate("─", 60) <> "\n")
  end
end

# Run the example
ComprehensiveStreamingExample.run()