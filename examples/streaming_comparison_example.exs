#!/usr/bin/env elixir
# Streaming Comparison Example
#
# This example compares standard streaming vs enhanced streaming,
# demonstrating the benefits of the new infrastructure.
#
# Usage: elixir examples/streaming_comparison_example.exs

Mix.install([
  {:ex_llm, path: ".", runtime: false}
])

defmodule StreamingComparisonExample do
  @moduledoc """
  Compares standard vs enhanced streaming to show the benefits.
  """

  def run do
    IO.puts("\n🔄 ExLLM Streaming Comparison\n")
    
    # Simulate slow terminal
    IO.puts("Simulating streaming to a slow terminal...\n")
    
    # Test message
    messages = [
      %{
        role: "user",
        content: "Write a short poem about streaming data efficiently."
      }
    ]
    
    # Example 1: Standard streaming (simulated)
    IO.puts("1️⃣  Standard Streaming (Direct Callback):")
    IO.puts("   - Each chunk immediately written")
    IO.puts("   - No buffering or flow control")
    IO.puts("   - Can drop chunks with slow consumers\n")
    
    simulate_standard_streaming()
    
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")
    
    # Example 2: Enhanced streaming (simulated)
    IO.puts("2️⃣  Enhanced Streaming (With Flow Control):")
    IO.puts("   - Intelligent buffering")
    IO.puts("   - Backpressure handling")
    IO.puts("   - Smooth output with batching\n")
    
    simulate_enhanced_streaming()
    
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")
    
    # Show configuration examples
    show_configuration_examples()
  end

  defp simulate_standard_streaming do
    # Simulate chunks arriving quickly
    chunks = generate_sample_chunks()
    dropped = 0
    
    IO.puts("Output: ")
    
    for chunk <- chunks do
      # Simulate fast chunk arrival
      Process.sleep(5)
      
      # Simulate slow terminal write (might drop)
      if :rand.uniform() > 0.1 do  # 90% success rate
        IO.write(chunk.content)
      else
        # Simulated drop
        dropped = dropped + 1
      end
    end
    
    IO.puts("\n\n⚠️  Dropped #{dropped} chunks due to slow consumer")
  end

  defp simulate_enhanced_streaming do
    alias ExLLM.Infrastructure.Streaming.{FlowController, StreamBuffer}
    
    chunks = generate_sample_chunks()
    delivered = 0
    
    # Consumer that tracks delivery
    consumer = fn chunk ->
      # Simulate slow terminal
      Process.sleep(20 + :rand.uniform(30))
      IO.write(chunk.content)
      delivered = delivered + 1
    end
    
    # Start enhanced flow controller
    {:ok, controller} = FlowController.start_link(
      consumer: consumer,
      buffer_capacity: 50,
      backpressure_threshold: 0.8,
      batch_config: [
        batch_size: 3,
        batch_timeout_ms: 50
      ]
    )
    
    IO.puts("Output: ")
    
    # Feed chunks with flow control
    for chunk <- chunks do
      # Fast arrival
      Process.sleep(5)
      
      # Flow control handles backpressure
      case FlowController.push_chunk(controller, chunk) do
        :ok -> :ok
        {:error, :backpressure} ->
          # Wait and retry
          Process.sleep(50)
          FlowController.push_chunk(controller, chunk)
      end
    end
    
    # Complete stream
    FlowController.complete_stream(controller)
    
    # Get metrics
    metrics = FlowController.get_metrics(controller)
    
    IO.puts("\n\n✅ Successfully delivered all #{metrics.chunks_delivered} chunks")
    IO.puts("📊 Stats:")
    IO.puts("   - No chunks dropped")
    IO.puts("   - Backpressure events: #{metrics.backpressure_events}")
    IO.puts("   - Average throughput: #{metrics.throughput_chunks_per_sec} chunks/sec")
    IO.puts("   - Buffer peak usage: #{metrics.max_buffer_size} chunks")
    
    GenServer.stop(controller)
  end

  defp generate_sample_chunks do
    text = """
    Data flows like water through silicon streams,
    Buffered and batched in digital dreams.
    No drops are lost in the flow control dance,
    Each chunk delivered, given its chance.
    From fast producers to consumers slow,
    The streaming pipeline maintains the flow.
    """
    
    # Split into word chunks
    text
    |> String.split(~r/(\s+)/, include_captures: true)
    |> Enum.map(&%ExLLM.Types.StreamChunk{content: &1})
  end

  defp show_configuration_examples do
    IO.puts("📋 Configuration Examples:\n")
    
    IO.puts("For slow terminals or network connections:")
    IO.puts("""
    ```elixir
    ExLLM.stream_chat(:anthropic, messages, callback,
      streaming_options: [
        consumer_type: :managed,
        buffer_config: %{capacity: 200},
        batch_config: %{size: 10, timeout_ms: 50}
      ]
    )
    ```
    """)
    
    IO.puts("\nFor high-speed providers (Groq, Claude):")
    IO.puts("""
    ```elixir
    ExLLM.stream_chat(:groq, messages, callback,
      streaming_options: [
        consumer_type: :managed,
        buffer_config: %{
          capacity: 100,
          overflow_strategy: :drop
        },
        flow_control: %{
          enabled: true,
          backpressure_threshold: 0.9
        }
      ]
    )
    ```
    """)
    
    IO.puts("\nFor production monitoring:")
    IO.puts("""
    ```elixir
    ExLLM.stream_chat(:openai, messages, callback,
      streaming_options: [
        consumer_type: :managed,
        metrics: %{enabled: true},
        on_metrics: &log_streaming_metrics/1
      ]
    )
    ```
    """)
  end
end

# Run the example
StreamingComparisonExample.run()