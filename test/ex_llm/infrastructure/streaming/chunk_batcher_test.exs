defmodule ExLLM.Infrastructure.Streaming.ChunkBatcherTest do
  use ExUnit.Case, async: true

  alias ExLLM.Infrastructure.Streaming.ChunkBatcher
  alias ExLLM.Types.StreamChunk

  describe "start_link/1" do
    test "starts with default configuration" do
      assert {:ok, batcher} = ChunkBatcher.start_link()
      assert Process.alive?(batcher)
      ChunkBatcher.stop(batcher)
    end

    test "starts with custom configuration" do
      assert {:ok, batcher} =
               ChunkBatcher.start_link(
                 batch_size: 10,
                 batch_timeout_ms: 50,
                 min_batch_size: 5,
                 max_batch_size: 20
               )

      assert Process.alive?(batcher)
      ChunkBatcher.stop(batcher)
    end
  end

  describe "add_chunk/2" do
    test "accumulates chunks until batch size reached" do
      {:ok, batcher} =
        ChunkBatcher.start_link(
          batch_size: 3,
          # Very long timeout
          batch_timeout_ms: 60_000,
          # Disable adaptive behavior
          adaptive: false
        )

      # First two chunks should return :ok
      chunk1 = %StreamChunk{content: "First"}
      chunk2 = %StreamChunk{content: "Second"}
      chunk3 = %StreamChunk{content: "Third"}

      assert :ok = ChunkBatcher.add_chunk(batcher, chunk1)
      assert :ok = ChunkBatcher.add_chunk(batcher, chunk2)

      # Third chunk should trigger batch
      assert {:batch_ready, batch} = ChunkBatcher.add_chunk(batcher, chunk3)
      assert batch == [chunk1, chunk2, chunk3]

      ChunkBatcher.stop(batcher)
    end

    test "triggers batch on timeout" do
      {:ok, batcher} =
        ChunkBatcher.start_link(
          batch_size: 5,
          batch_timeout_ms: 100
        )

      chunk = %StreamChunk{content: "Timeout test"}
      assert :ok = ChunkBatcher.add_chunk(batcher, chunk)

      # Wait for timeout
      Process.sleep(150)

      # Next chunk should get fresh batch
      chunk2 = %StreamChunk{content: "After timeout"}
      assert :ok = ChunkBatcher.add_chunk(batcher, chunk2)

      ChunkBatcher.stop(batcher)
    end

    test "respects max batch size" do
      {:ok, batcher} =
        ChunkBatcher.start_link(
          batch_size: 5,
          max_batch_size: 3
        )

      chunks = for i <- 1..3, do: %StreamChunk{content: "Chunk #{i}"}

      # First two should accumulate
      assert :ok = ChunkBatcher.add_chunk(batcher, Enum.at(chunks, 0))
      assert :ok = ChunkBatcher.add_chunk(batcher, Enum.at(chunks, 1))

      # Third should trigger due to max size
      assert {:batch_ready, batch} = ChunkBatcher.add_chunk(batcher, Enum.at(chunks, 2))
      assert length(batch) == 3

      ChunkBatcher.stop(batcher)
    end

    test "flushes immediately on stream end marker" do
      {:ok, batcher} = ChunkBatcher.start_link(batch_size: 10)

      chunk1 = %StreamChunk{content: "Regular chunk"}
      chunk2 = %StreamChunk{content: "", finish_reason: "stop"}

      assert :ok = ChunkBatcher.add_chunk(batcher, chunk1)
      assert {:batch_ready, batch} = ChunkBatcher.add_chunk(batcher, chunk2)

      assert batch == [chunk1, chunk2]

      ChunkBatcher.stop(batcher)
    end
  end

  describe "flush/1" do
    test "returns current batch contents" do
      {:ok, batcher} = ChunkBatcher.start_link()

      chunks = for i <- 1..3, do: %StreamChunk{content: "Chunk #{i}"}

      for chunk <- chunks do
        assert :ok = ChunkBatcher.add_chunk(batcher, chunk)
      end

      flushed = ChunkBatcher.flush(batcher)
      assert flushed == chunks

      # Buffer should be empty after flush
      assert ChunkBatcher.flush(batcher) == []

      ChunkBatcher.stop(batcher)
    end

    test "cancels pending timer on flush" do
      {:ok, batcher} = ChunkBatcher.start_link(batch_timeout_ms: 1000)

      chunk = %StreamChunk{content: "Test"}
      assert :ok = ChunkBatcher.add_chunk(batcher, chunk)

      # Flush immediately
      assert [^chunk] = ChunkBatcher.flush(batcher)

      # Wait to ensure no timeout occurs
      Process.sleep(100)

      # Add another chunk - should start fresh
      chunk2 = %StreamChunk{content: "Test2"}
      assert :ok = ChunkBatcher.add_chunk(batcher, chunk2)

      ChunkBatcher.stop(batcher)
    end
  end

  describe "adaptive batching" do
    test "adapts batch size based on chunk size" do
      {:ok, batcher} =
        ChunkBatcher.start_link(
          batch_size: 5,
          adaptive: true
        )

      # Send large chunks
      large_chunks =
        for _i <- 1..10 do
          %StreamChunk{content: String.duplicate("x", 2000)}
        end

      # Add chunks and track batch sizes
      batch_sizes =
        large_chunks
        |> Enum.reduce([], fn chunk, acc ->
          case ChunkBatcher.add_chunk(batcher, chunk) do
            {:batch_ready, batch} -> [length(batch) | acc]
            :ok -> acc
          end
        end)

      # Should adapt to smaller batches for large chunks
      assert Enum.any?(batch_sizes, &(&1 < 5))

      ChunkBatcher.stop(batcher)
    end

    test "adapts timeout based on arrival rate" do
      {:ok, batcher} =
        ChunkBatcher.start_link(
          batch_timeout_ms: 50,
          adaptive: true
        )

      # Send chunks rapidly
      for i <- 1..20 do
        chunk = %StreamChunk{content: "Rapid #{i}"}
        ChunkBatcher.add_chunk(batcher, chunk)
        # Very fast arrival
        Process.sleep(5)
      end

      metrics = ChunkBatcher.get_metrics(batcher)
      assert metrics.chunks_batched > 0

      ChunkBatcher.stop(batcher)
    end

    test "can disable adaptive behavior" do
      {:ok, batcher} =
        ChunkBatcher.start_link(
          batch_size: 3,
          adaptive: false
        )

      # Should always batch at exactly 3
      chunks = for i <- 1..6, do: %StreamChunk{content: "Chunk #{i}"}

      results = Enum.map(chunks, &ChunkBatcher.add_chunk(batcher, &1))

      batch_ready_count =
        Enum.count(results, fn
          {:batch_ready, _} -> true
          _ -> false
        end)

      # Exactly 2 batches of 3
      assert batch_ready_count == 2

      ChunkBatcher.stop(batcher)
    end
  end

  describe "get_metrics/1" do
    test "tracks comprehensive metrics" do
      {:ok, batcher} = ChunkBatcher.start_link(batch_size: 3)

      # Add chunks to create batches
      chunks = for _i <- 1..7, do: %StreamChunk{content: String.duplicate("x", 100)}

      for chunk <- chunks do
        ChunkBatcher.add_chunk(batcher, chunk)
      end

      # Force flush remaining
      ChunkBatcher.flush(batcher)

      # Add small delay to ensure duration_ms > 0
      Process.sleep(1)

      metrics = ChunkBatcher.get_metrics(batcher)

      assert metrics.chunks_batched == 7
      # At least 2 full batches
      assert metrics.batches_created >= 2
      # The manual flush
      assert metrics.forced_flushes >= 1
      assert metrics.total_bytes == 700
      assert metrics.average_batch_size > 0
      assert metrics.duration_ms > 0
      assert metrics.throughput_chunks_per_sec > 0

      ChunkBatcher.stop(batcher)
    end

    test "tracks min/max batch sizes" do
      {:ok, batcher} =
        ChunkBatcher.start_link(
          batch_size: 5,
          batch_timeout_ms: 60_000,
          adaptive: false
        )

      # Create batch 1: 5 chunks (full batch)
      for i <- 1..5 do
        chunk = %StreamChunk{content: "#{i}"}
        result = ChunkBatcher.add_chunk(batcher, chunk)
        # The 5th chunk should trigger a batch
        if i == 5 do
          assert {:batch_ready, batch} = result
          assert length(batch) == 5
        else
          assert result == :ok
        end
      end

      # Create batch 2: 2 chunks (forced flush)
      for i <- 6..7 do
        chunk = %StreamChunk{content: "#{i}"}
        assert :ok = ChunkBatcher.add_chunk(batcher, chunk)
      end

      # Force flush the remaining 2 chunks
      remaining = ChunkBatcher.flush(batcher)
      assert length(remaining) == 2

      metrics = ChunkBatcher.get_metrics(batcher)
      assert metrics.min_batch_size == 2
      assert metrics.max_batch_size == 5

      ChunkBatcher.stop(batcher)
    end
  end

  describe "on_batch_ready callback" do
    test "calls callback when batch is ready" do
      test_pid = self()

      on_batch = fn batch ->
        send(test_pid, {:batch_ready, batch})
      end

      {:ok, batcher} =
        ChunkBatcher.start_link(
          batch_size: 2,
          batch_timeout_ms: 100,
          on_batch_ready: on_batch
        )

      chunk1 = %StreamChunk{content: "One"}
      _chunk2 = %StreamChunk{content: "Two"}

      ChunkBatcher.add_chunk(batcher, chunk1)

      # Should trigger on timeout
      assert_receive {:batch_ready, [^chunk1]}, 200

      ChunkBatcher.stop(batcher)
    end
  end

  describe "stop/1" do
    test "returns remaining chunks on stop" do
      {:ok, batcher} = ChunkBatcher.start_link()

      chunks = for i <- 1..3, do: %StreamChunk{content: "Chunk #{i}"}

      for chunk <- chunks do
        ChunkBatcher.add_chunk(batcher, chunk)
      end

      remaining = ChunkBatcher.stop(batcher)
      assert remaining == chunks

      # Give process time to terminate
      Process.sleep(10)
      refute Process.alive?(batcher)
    end
  end

  describe "edge cases" do
    test "handles empty chunks" do
      {:ok, batcher} =
        ChunkBatcher.start_link(
          batch_size: 3,
          batch_timeout_ms: 60_000,
          adaptive: false
        )

      chunks = [
        %StreamChunk{content: "Normal"},
        %StreamChunk{content: ""},
        %StreamChunk{content: "Another"}
      ]

      results = Enum.map(chunks, &ChunkBatcher.add_chunk(batcher, &1))
      assert {:batch_ready, batch} = List.last(results)
      assert length(batch) == 3

      ChunkBatcher.stop(batcher)
    end

    test "handles rapid consecutive flushes" do
      {:ok, batcher} = ChunkBatcher.start_link()

      chunk = %StreamChunk{content: "Test"}
      ChunkBatcher.add_chunk(batcher, chunk)

      # Multiple flushes
      assert [^chunk] = ChunkBatcher.flush(batcher)
      assert [] = ChunkBatcher.flush(batcher)
      assert [] = ChunkBatcher.flush(batcher)

      ChunkBatcher.stop(batcher)
    end

    test "handles chunks with varying sizes" do
      {:ok, batcher} =
        ChunkBatcher.start_link(
          batch_size: 3,
          adaptive: true
        )

      chunks = [
        %StreamChunk{content: ""},
        %StreamChunk{content: String.duplicate("x", 1000)},
        %StreamChunk{content: "small"},
        %StreamChunk{content: String.duplicate("y", 2000)}
      ]

      for chunk <- chunks do
        ChunkBatcher.add_chunk(batcher, chunk)
      end

      metrics = ChunkBatcher.get_metrics(batcher)
      assert metrics.chunks_batched == 4
      assert metrics.total_bytes == 3005

      ChunkBatcher.stop(batcher)
    end
  end
end
