defmodule ExLLM.Streaming.FlowControllerTest do
  use ExUnit.Case, async: true

  alias ExLLM.Streaming.FlowController
  alias ExLLM.Types.StreamChunk

  setup do
    # Create a simple consumer that collects chunks
    test_pid = self()
    consumer = fn chunk -> send(test_pid, {:chunk_received, chunk}) end

    {:ok, consumer: consumer, test_pid: test_pid}
  end

  describe "start_link/1" do
    test "starts with required consumer", %{consumer: consumer} do
      assert {:ok, controller} = FlowController.start_link(consumer: consumer)
      assert Process.alive?(controller)
      GenServer.stop(controller)
    end

    test "starts with custom configuration", %{consumer: consumer} do
      assert {:ok, controller} =
               FlowController.start_link(
                 consumer: consumer,
                 buffer_capacity: 50,
                 backpressure_threshold: 0.9,
                 rate_limit_ms: 5
               )

      status = FlowController.get_status(controller)
      assert status.status == :running
      GenServer.stop(controller)
    end

    test "requires consumer function" do
      assert_raise KeyError, fn ->
        FlowController.start_link([])
      end
    end
  end

  describe "push_chunk/2" do
    test "accepts chunks and delivers to consumer", %{consumer: consumer} do
      {:ok, controller} = FlowController.start_link(consumer: consumer)

      chunk = %StreamChunk{content: "Hello, World!"}
      assert :ok = FlowController.push_chunk(controller, chunk)

      assert_receive {:chunk_received, ^chunk}, 1000

      GenServer.stop(controller)
    end

    test "handles multiple chunks in order", %{consumer: consumer} do
      {:ok, controller} = FlowController.start_link(consumer: consumer)

      chunks = for i <- 1..5, do: %StreamChunk{content: "Chunk #{i}"}

      for chunk <- chunks do
        assert :ok = FlowController.push_chunk(controller, chunk)
      end

      # Verify all chunks received in order
      for chunk <- chunks do
        assert_receive {:chunk_received, ^chunk}, 1000
      end

      GenServer.stop(controller)
    end

    test "applies rate limiting", %{consumer: consumer} do
      {:ok, controller} =
        FlowController.start_link(
          consumer: consumer,
          rate_limit_ms: 50
        )

      start_time = System.monotonic_time(:millisecond)

      # Push chunks rapidly
      for i <- 1..3 do
        chunk = %StreamChunk{content: "Chunk #{i}"}
        assert :ok = FlowController.push_chunk(controller, chunk)
      end

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # Should have taken at least 100ms (2 delays of 50ms)
      assert elapsed >= 100

      GenServer.stop(controller)
    end
  end

  describe "backpressure" do
    test "applies backpressure when buffer is near capacity", %{test_pid: test_pid} do
      # Slow consumer that blocks
      slow_consumer = fn chunk ->
        send(test_pid, {:chunk_received, chunk})
        Process.sleep(100)
      end

      {:ok, controller} =
        FlowController.start_link(
          consumer: slow_consumer,
          buffer_capacity: 10,
          backpressure_threshold: 0.8
        )

      # Fill buffer quickly
      chunks = for i <- 1..8, do: %StreamChunk{content: "Chunk #{i}"}

      results =
        for chunk <- chunks do
          FlowController.push_chunk(controller, chunk)
        end

      # First 8 should succeed
      assert Enum.all?(Enum.take(results, 8), &(&1 == :ok))

      # Next push should trigger backpressure
      chunk = %StreamChunk{content: "Overflow"}
      assert {:error, :backpressure} = FlowController.push_chunk(controller, chunk)

      GenServer.stop(controller)
    end

    test "releases backpressure as buffer drains", %{test_pid: test_pid} do
      # Consumer with controllable speed
      slow_consumer = fn chunk ->
        send(test_pid, {:chunk_received, chunk})
        Process.sleep(10)
      end

      {:ok, controller} =
        FlowController.start_link(
          consumer: slow_consumer,
          buffer_capacity: 5,
          backpressure_threshold: 0.8
        )

      # Fill to backpressure threshold
      for i <- 1..4 do
        chunk = %StreamChunk{content: "Chunk #{i}"}
        assert :ok = FlowController.push_chunk(controller, chunk)
      end

      # Should hit backpressure
      overflow_chunk = %StreamChunk{content: "Overflow"}
      assert {:error, :backpressure} = FlowController.push_chunk(controller, overflow_chunk)

      # Wait for buffer to drain
      Process.sleep(100)

      # Should be able to push again
      assert :ok = FlowController.push_chunk(controller, overflow_chunk)

      GenServer.stop(controller)
    end
  end

  describe "metrics tracking" do
    test "tracks basic metrics", %{consumer: consumer} do
      {:ok, controller} = FlowController.start_link(consumer: consumer)

      # Push some chunks
      for i <- 1..5 do
        chunk = %StreamChunk{content: String.duplicate("x", 100)}
        FlowController.push_chunk(controller, chunk)
      end

      # Let consumer process
      Process.sleep(100)

      metrics = FlowController.get_metrics(controller)

      assert metrics.chunks_received == 5
      assert metrics.chunks_delivered == 5
      assert metrics.bytes_received == 500
      assert metrics.bytes_delivered == 500
      assert metrics.chunks_dropped == 0
      assert metrics.backpressure_events == 0

      GenServer.stop(controller)
    end

    test "tracks overflow and drops with drop strategy", %{test_pid: test_pid} do
      # Very slow consumer
      slow_consumer = fn chunk ->
        send(test_pid, {:chunk_received, chunk})
        Process.sleep(1000)
      end

      {:ok, controller} =
        FlowController.start_link(
          consumer: slow_consumer,
          buffer_capacity: 3,
          overflow_strategy: :drop
        )

      # Push more chunks than buffer can hold
      for i <- 1..5 do
        chunk = %StreamChunk{content: "Chunk #{i}"}
        FlowController.push_chunk(controller, chunk)
      end

      metrics = FlowController.get_metrics(controller)
      assert metrics.chunks_received >= 3
      assert metrics.chunks_dropped >= 0

      GenServer.stop(controller)
    end

    test "metric callbacks", %{consumer: consumer, test_pid: test_pid} do
      metrics_callback = fn metrics ->
        send(test_pid, {:metrics_report, metrics})
      end

      {:ok, controller} =
        FlowController.start_link(
          consumer: consumer,
          on_metrics: metrics_callback
        )

      # Push some chunks
      chunk = %StreamChunk{content: "Test"}
      FlowController.push_chunk(controller, chunk)

      # Wait for metrics report
      assert_receive {:metrics_report, metrics}, 2000
      assert metrics.chunks_received >= 1
      assert metrics.duration_ms > 0

      GenServer.stop(controller)
    end
  end

  describe "complete_stream/1" do
    test "drains buffer before completing", %{test_pid: test_pid} do
      # Slow consumer to ensure chunks stay in buffer
      slow_consumer = fn chunk ->
        send(test_pid, {:chunk_received, chunk})
        Process.sleep(50)
      end

      {:ok, controller} = FlowController.start_link(consumer: slow_consumer)

      # Push chunks
      chunks = for i <- 1..3, do: %StreamChunk{content: "Chunk #{i}"}

      for chunk <- chunks do
        FlowController.push_chunk(controller, chunk)
      end

      # Complete stream
      assert :ok = FlowController.complete_stream(controller)

      # All chunks should have been delivered
      for chunk <- chunks do
        assert_received {:chunk_received, ^chunk}
      end

      # Status should be completed
      status = FlowController.get_status(controller)
      assert status.status == :completed

      GenServer.stop(controller)
    end
  end

  describe "integration with ChunkBatcher" do
    test "uses batcher when configured", %{test_pid: test_pid} do
      # Consumer that tracks batch sizes
      consumer = fn chunk ->
        send(test_pid, {:chunk_received, chunk})
      end

      {:ok, controller} =
        FlowController.start_link(
          consumer: consumer,
          batch_config: [
            batch_size: 3,
            batch_timeout_ms: 100
          ]
        )

      # Push chunks that should be batched
      chunks = for i <- 1..3, do: %StreamChunk{content: "Chunk #{i}"}

      for chunk <- chunks do
        FlowController.push_chunk(controller, chunk)
      end

      # Should receive all chunks (batcher flushes when full)
      for chunk <- chunks do
        assert_receive {:chunk_received, ^chunk}, 1000
      end

      GenServer.stop(controller)
    end
  end

  describe "error handling" do
    test "handles consumer errors gracefully", %{test_pid: test_pid} do
      # Consumer that crashes on certain chunks
      faulty_consumer = fn chunk ->
        if chunk.content == "crash" do
          raise "Consumer error!"
        else
          send(test_pid, {:chunk_received, chunk})
        end
      end

      {:ok, controller} = FlowController.start_link(consumer: faulty_consumer)

      # Push normal chunk
      good_chunk = %StreamChunk{content: "good"}
      assert :ok = FlowController.push_chunk(controller, good_chunk)
      assert_receive {:chunk_received, ^good_chunk}, 1000

      # Push crash chunk
      crash_chunk = %StreamChunk{content: "crash"}
      assert :ok = FlowController.push_chunk(controller, crash_chunk)

      # Consumer should recover and continue
      Process.sleep(100)

      # Push another good chunk
      another_chunk = %StreamChunk{content: "recovered"}
      assert :ok = FlowController.push_chunk(controller, another_chunk)
      assert_receive {:chunk_received, ^another_chunk}, 1000

      # Check error metrics
      metrics = FlowController.get_metrics(controller)
      assert metrics.consumer_errors > 0

      GenServer.stop(controller)
    end
  end

  describe "get_status/1" do
    test "returns comprehensive status", %{consumer: consumer} do
      {:ok, controller} =
        FlowController.start_link(
          consumer: consumer,
          buffer_capacity: 10
        )

      # Push some chunks
      for i <- 1..3 do
        chunk = %StreamChunk{content: "Chunk #{i}"}
        FlowController.push_chunk(controller, chunk)
      end

      Process.sleep(100)

      status = FlowController.get_status(controller)

      assert status.status == :running
      assert status.buffer_size >= 0
      assert status.buffer_fill_percentage >= 0.0
      assert status.consumer_active == true
      assert is_map(status.metrics)

      GenServer.stop(controller)
    end
  end
end
