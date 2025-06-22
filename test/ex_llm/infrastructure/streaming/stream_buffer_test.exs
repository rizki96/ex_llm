defmodule ExLLM.Infrastructure.Streaming.StreamBufferTest do
  use ExUnit.Case, async: true

  alias ExLLM.Infrastructure.Streaming.StreamBuffer
  alias ExLLM.Types.StreamChunk

  describe "new/1" do
    test "creates a buffer with specified capacity" do
      buffer = StreamBuffer.new(10)
      assert StreamBuffer.size(buffer) == 0
      assert buffer.capacity == 10
      assert StreamBuffer.empty?(buffer)
    end

    test "accepts overflow strategy option" do
      buffer = StreamBuffer.new(5, overflow_strategy: :overwrite)
      assert buffer.overflow_strategy == :overwrite
    end

    test "defaults to drop strategy" do
      buffer = StreamBuffer.new(5)
      assert buffer.overflow_strategy == :drop
    end
  end

  describe "push/2 and pop/1" do
    test "basic push and pop operations" do
      buffer = StreamBuffer.new(5)
      chunk = %StreamChunk{content: "Hello"}

      {:ok, buffer} = StreamBuffer.push(buffer, chunk)
      assert StreamBuffer.size(buffer) == 1
      refute StreamBuffer.empty?(buffer)

      {:ok, popped_chunk, buffer} = StreamBuffer.pop(buffer)
      assert popped_chunk == chunk
      assert StreamBuffer.empty?(buffer)
    end

    test "FIFO ordering" do
      buffer = StreamBuffer.new(10)
      chunks = for i <- 1..5, do: %StreamChunk{content: "Chunk #{i}"}

      buffer =
        Enum.reduce(chunks, buffer, fn chunk, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, chunk)
          new_buf
        end)

      assert StreamBuffer.size(buffer) == 5

      # Pop all chunks and verify order
      {popped_chunks, _} = StreamBuffer.pop_many(buffer, 5)
      assert popped_chunks == chunks
    end

    test "pop from empty buffer" do
      buffer = StreamBuffer.new(5)
      assert {:empty, ^buffer} = StreamBuffer.pop(buffer)
    end
  end

  describe "overflow strategies" do
    test "drop strategy silently drops new chunks when full" do
      buffer = StreamBuffer.new(3, overflow_strategy: :drop)
      chunks = for i <- 1..5, do: %StreamChunk{content: "Chunk #{i}"}

      buffer =
        Enum.reduce(chunks, buffer, fn chunk, buf ->
          case StreamBuffer.push(buf, chunk) do
            {:ok, new_buf} -> new_buf
            {:overflow, new_buf} -> new_buf
          end
        end)

      assert StreamBuffer.size(buffer) == 3
      assert buffer.overflow_count == 2

      # Should have first 3 chunks
      {popped, _} = StreamBuffer.pop_many(buffer, 3)
      assert Enum.map(popped, & &1.content) == ["Chunk 1", "Chunk 2", "Chunk 3"]
    end

    test "overwrite strategy overwrites oldest chunks when full" do
      buffer = StreamBuffer.new(3, overflow_strategy: :overwrite)
      chunks = for i <- 1..5, do: %StreamChunk{content: "Chunk #{i}"}

      buffer =
        Enum.reduce(chunks, buffer, fn chunk, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, chunk)
          new_buf
        end)

      assert StreamBuffer.size(buffer) == 3
      assert buffer.overflow_count == 2

      # Should have last 3 chunks
      {popped, _} = StreamBuffer.pop_many(buffer, 3)
      assert Enum.map(popped, & &1.content) == ["Chunk 3", "Chunk 4", "Chunk 5"]
    end

    test "block strategy returns overflow signal" do
      buffer = StreamBuffer.new(3, overflow_strategy: :block)
      chunks = for i <- 1..5, do: %StreamChunk{content: "Chunk #{i}"}

      # Fill the buffer
      buffer =
        chunks
        |> Enum.take(3)
        |> Enum.reduce(buffer, fn chunk, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, chunk)
          new_buf
        end)

      # Next pushes should return overflow
      assert {:overflow, buffer} = StreamBuffer.push(buffer, Enum.at(chunks, 3))
      assert buffer.overflow_count == 1
      assert StreamBuffer.size(buffer) == 3
    end
  end

  describe "push!/2" do
    test "always returns buffer for pipeline usage" do
      buffer = StreamBuffer.new(3, overflow_strategy: :block)
      chunks = for i <- 1..5, do: %StreamChunk{content: "Chunk #{i}"}

      final_buffer =
        Enum.reduce(chunks, buffer, fn chunk, buf ->
          StreamBuffer.push!(buf, chunk)
        end)

      assert StreamBuffer.size(final_buffer) == 3
      assert final_buffer.overflow_count == 2
    end
  end

  describe "pop_many/2" do
    test "pops requested number of chunks" do
      buffer = StreamBuffer.new(10)
      chunks = for i <- 1..5, do: %StreamChunk{content: "Chunk #{i}"}

      buffer =
        Enum.reduce(chunks, buffer, fn chunk, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, chunk)
          new_buf
        end)

      {popped, buffer} = StreamBuffer.pop_many(buffer, 3)
      assert length(popped) == 3
      assert StreamBuffer.size(buffer) == 2
      assert Enum.map(popped, & &1.content) == ["Chunk 1", "Chunk 2", "Chunk 3"]
    end

    test "returns all available chunks if requested more than available" do
      buffer = StreamBuffer.new(10)
      chunks = for i <- 1..3, do: %StreamChunk{content: "Chunk #{i}"}

      buffer =
        Enum.reduce(chunks, buffer, fn chunk, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, chunk)
          new_buf
        end)

      {popped, buffer} = StreamBuffer.pop_many(buffer, 10)
      assert length(popped) == 3
      assert StreamBuffer.empty?(buffer)
    end

    test "returns empty list from empty buffer" do
      buffer = StreamBuffer.new(5)
      {popped, buffer} = StreamBuffer.pop_many(buffer, 5)
      assert popped == []
      assert StreamBuffer.empty?(buffer)
    end
  end

  describe "metrics and statistics" do
    test "fill_percentage calculation" do
      buffer = StreamBuffer.new(10)

      assert StreamBuffer.fill_percentage(buffer) == 0.0

      buffer =
        1..5
        |> Enum.reduce(buffer, fn i, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, %StreamChunk{content: "#{i}"})
          new_buf
        end)

      assert StreamBuffer.fill_percentage(buffer) == 50.0

      buffer =
        6..10
        |> Enum.reduce(buffer, fn i, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, %StreamChunk{content: "#{i}"})
          new_buf
        end)

      assert StreamBuffer.fill_percentage(buffer) == 100.0
    end

    test "comprehensive stats" do
      buffer = StreamBuffer.new(5, overflow_strategy: :drop)

      # Push some chunks
      buffer =
        1..7
        |> Enum.reduce(buffer, fn i, buf ->
          case StreamBuffer.push(buf, %StreamChunk{content: "#{i}"}) do
            {:ok, new_buf} -> new_buf
            {:overflow, new_buf} -> new_buf
          end
        end)

      # Pop a few
      {_, buffer} = StreamBuffer.pop_many(buffer, 2)

      stats = StreamBuffer.stats(buffer)
      assert stats.size == 3
      assert stats.capacity == 5
      assert stats.fill_percentage == 60.0
      assert stats.overflow_count == 2
      assert stats.available_space == 2
      assert stats.total_pushed == 5
      assert stats.total_popped == 2
      assert stats.total_dropped == 2
    end
  end

  describe "utility functions" do
    test "to_list returns chunks in FIFO order" do
      buffer = StreamBuffer.new(10)
      chunks = for i <- 1..5, do: %StreamChunk{content: "Chunk #{i}"}

      buffer =
        Enum.reduce(chunks, buffer, fn chunk, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, chunk)
          new_buf
        end)

      list = StreamBuffer.to_list(buffer)
      assert list == chunks
    end

    test "clear empties the buffer" do
      buffer = StreamBuffer.new(5)

      buffer =
        1..3
        |> Enum.reduce(buffer, fn i, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, %StreamChunk{content: "#{i}"})
          new_buf
        end)

      assert StreamBuffer.size(buffer) == 3

      buffer = StreamBuffer.clear(buffer)
      assert StreamBuffer.empty?(buffer)
      # Capacity unchanged
      assert buffer.capacity == 5
    end

    test "full? predicate" do
      buffer = StreamBuffer.new(3)
      refute StreamBuffer.full?(buffer)

      buffer =
        1..3
        |> Enum.reduce(buffer, fn i, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, %StreamChunk{content: "#{i}"})
          new_buf
        end)

      assert StreamBuffer.full?(buffer)

      {:ok, _, buffer} = StreamBuffer.pop(buffer)
      refute StreamBuffer.full?(buffer)
    end
  end

  describe "circular buffer behavior" do
    test "wraps around correctly with overwrite strategy" do
      buffer = StreamBuffer.new(3, overflow_strategy: :overwrite)

      # Fill buffer multiple times over
      buffer =
        1..10
        |> Enum.reduce(buffer, fn i, buf ->
          {:ok, new_buf} = StreamBuffer.push(buf, %StreamChunk{content: "Item #{i}"})
          new_buf
        end)

      # Should have last 3 items
      items = StreamBuffer.to_list(buffer)
      assert length(items) == 3
      assert Enum.map(items, & &1.content) == ["Item 8", "Item 9", "Item 10"]
    end

    test "handles rapid push/pop cycles" do
      _buffer = StreamBuffer.new(5)

      # Simulate streaming with push/pop cycles  
      # We'll use overwrite strategy to ensure all pushes succeed
      buffer = StreamBuffer.new(5, overflow_strategy: :overwrite)

      final_buffer =
        1..100
        |> Enum.reduce({buffer, 0}, fn i, {buf, pops} ->
          chunk = %StreamChunk{content: "Stream #{i}"}

          # Push always succeeds with overwrite
          {:ok, buf} = StreamBuffer.push(buf, chunk)

          # Pop every 3 pushes
          if rem(i, 3) == 0 && !StreamBuffer.empty?(buf) do
            {:ok, _popped, buf} = StreamBuffer.pop(buf)
            {buf, pops + 1}
          else
            {buf, pops}
          end
        end)
        |> elem(0)

      # Buffer should have reasonable state
      assert StreamBuffer.size(final_buffer) <= 5
      stats = StreamBuffer.stats(final_buffer)
      # All pushes succeeded
      assert stats.total_pushed == 100
      # Popped every 3rd
      assert stats.total_popped == 33

      # Some overflows occurred due to buffer capacity
      assert stats.overflow_count > 0
    end
  end
end
