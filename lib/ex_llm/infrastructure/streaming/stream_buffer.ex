defmodule ExLLM.Infrastructure.Streaming.StreamBuffer do
  @moduledoc """
  Efficient circular buffer implementation for stream chunk management.

  This module provides a memory-efficient circular buffer specifically designed
  for handling streaming LLM responses. It prevents unbounded memory growth
  while maintaining high performance for chunk processing.

  ## Features

  - Fixed-size circular buffer to prevent memory issues
  - O(1) push and pop operations
  - Configurable overflow strategies
  - Buffer state monitoring and metrics
  - Batch operations for efficiency

  ## Example

      # Create a buffer with capacity for 100 chunks
      buffer = StreamBuffer.new(100)

      # Push chunks
      {:ok, buffer} = StreamBuffer.push(buffer, chunk1)
      {:ok, buffer} = StreamBuffer.push(buffer, chunk2)

      # Pop chunks
      {:ok, chunk, buffer} = StreamBuffer.pop(buffer)

      # Pop multiple chunks at once
      {chunks, buffer} = StreamBuffer.pop_many(buffer, 5)

      # Check buffer status
      StreamBuffer.size(buffer)         # => 42
      StreamBuffer.fill_percentage(buffer) # => 42.0
  """

  alias ExLLM.Types

  defstruct [
    :data,
    :capacity,
    :size,
    :head,
    :tail,
    :overflow_count,
    :overflow_strategy,
    :total_pushed,
    :total_popped
  ]

  @type overflow_strategy :: :drop | :overwrite | :block
  @type t :: %__MODULE__{
          data: :array.array(),
          capacity: pos_integer(),
          size: non_neg_integer(),
          head: non_neg_integer(),
          tail: non_neg_integer(),
          overflow_count: non_neg_integer(),
          overflow_strategy: overflow_strategy(),
          total_pushed: non_neg_integer(),
          total_popped: non_neg_integer()
        }

  @doc """
  Creates a new stream buffer with the given capacity and options.

  ## Options

  - `:overflow_strategy` - How to handle buffer overflow (default: `:drop`)
    - `:drop` - Drop new chunks when buffer is full
    - `:overwrite` - Overwrite oldest chunks when buffer is full
    - `:block` - Return error when buffer is full (caller must handle)

  ## Examples

      # Basic buffer
      buffer = StreamBuffer.new(100)

      # With custom overflow strategy
      buffer = StreamBuffer.new(50, overflow_strategy: :overwrite)
  """
  @spec new(pos_integer(), keyword()) :: t()
  def new(capacity, opts \\ []) when capacity > 0 do
    overflow_strategy = Keyword.get(opts, :overflow_strategy, :drop)

    %__MODULE__{
      data: :array.new(capacity, default: nil),
      capacity: capacity,
      size: 0,
      head: 0,
      tail: 0,
      overflow_count: 0,
      overflow_strategy: overflow_strategy,
      total_pushed: 0,
      total_popped: 0
    }
  end

  @doc """
  Pushes a chunk into the buffer.

  Returns `{:ok, buffer}` if successful, or `{:overflow, buffer}` if buffer
  is full and overflow_strategy is `:block`.

  For `:drop` strategy, the chunk is silently dropped.
  For `:overwrite` strategy, the oldest chunk is overwritten.
  """
  @spec push(t(), Types.StreamChunk.t()) :: {:ok, t()} | {:overflow, t()}
  def push(%__MODULE__{} = buffer, %ExLLM.Types.StreamChunk{} = chunk) do
    if full?(buffer) do
      handle_overflow(buffer, chunk)
    else
      data = :array.set(buffer.tail, chunk, buffer.data)
      new_tail = rem(buffer.tail + 1, buffer.capacity)

      new_buffer = %{
        buffer
        | data: data,
          tail: new_tail,
          size: buffer.size + 1,
          total_pushed: buffer.total_pushed + 1
      }

      {:ok, new_buffer}
    end
  end

  @doc """
  Pushes a chunk, automatically handling overflow based on strategy.

  This is a convenience function that always returns the buffer,
  making it suitable for use in pipelines.
  """
  @spec push!(t(), Types.StreamChunk.t()) :: t()
  def push!(%__MODULE__{} = buffer, %ExLLM.Types.StreamChunk{} = chunk) do
    case push(buffer, chunk) do
      {:ok, new_buffer} -> new_buffer
      {:overflow, new_buffer} -> new_buffer
    end
  end

  @doc """
  Pops a chunk from the buffer.

  Returns `{:ok, chunk, buffer}` or `{:empty, buffer}`.
  """
  @spec pop(t()) :: {:ok, Types.StreamChunk.t(), t()} | {:empty, t()}
  def pop(%__MODULE__{} = buffer) do
    if empty?(buffer) do
      {:empty, buffer}
    else
      chunk = :array.get(buffer.head, buffer.data)
      new_head = rem(buffer.head + 1, buffer.capacity)

      new_buffer = %{
        buffer
        | head: new_head,
          size: buffer.size - 1,
          total_popped: buffer.total_popped + 1
      }

      {:ok, chunk, new_buffer}
    end
  end

  @doc """
  Pops up to n chunks from the buffer.

  Returns `{chunks, buffer}` where chunks is a list of at most n chunks.
  The chunks are returned in FIFO order.
  """
  @spec pop_many(t(), pos_integer()) :: {[Types.StreamChunk.t()], t()}
  def pop_many(%__MODULE__{} = buffer, n) when n > 0 do
    pop_many_acc(buffer, n, [])
  end

  @doc """
  Returns the current size of the buffer.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc """
  Returns true if the buffer is empty.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{size: 0}), do: true
  def empty?(_), do: false

  @doc """
  Returns true if the buffer is full.
  """
  @spec full?(t()) :: boolean()
  def full?(%__MODULE__{size: size, capacity: capacity}), do: size == capacity

  @doc """
  Returns the fill percentage of the buffer (0.0-100.0).
  """
  @spec fill_percentage(t()) :: float()
  def fill_percentage(%__MODULE__{size: size, capacity: capacity}) do
    size * 100.0 / capacity
  end

  @doc """
  Returns buffer statistics.

  Includes current state metrics and lifetime counters.
  """
  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = buffer) do
    %{
      size: buffer.size,
      capacity: buffer.capacity,
      fill_percentage: fill_percentage(buffer),
      overflow_count: buffer.overflow_count,
      overflow_strategy: buffer.overflow_strategy,
      available_space: buffer.capacity - buffer.size,
      total_pushed: buffer.total_pushed,
      total_popped: buffer.total_popped,
      total_dropped: buffer.overflow_count
    }
  end

  @doc """
  Returns all chunks currently in the buffer as a list.

  Chunks are returned in FIFO order (oldest first).
  This is primarily for debugging and testing.
  """
  @spec to_list(t()) :: [Types.StreamChunk.t()]
  def to_list(%__MODULE__{} = buffer) do
    if empty?(buffer) do
      []
    else
      to_list_acc(buffer, buffer.head, buffer.size, [])
    end
  end

  @doc """
  Clears all chunks from the buffer.

  Returns a new empty buffer with the same configuration.
  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = buffer) do
    %{
      buffer
      | data: :array.new(buffer.capacity, default: nil),
        size: 0,
        head: 0,
        tail: 0
    }
  end

  # Private functions

  defp handle_overflow(buffer, chunk) do
    case buffer.overflow_strategy do
      :drop ->
        # Silently drop the chunk
        new_buffer = %{buffer | overflow_count: buffer.overflow_count + 1}
        {:ok, new_buffer}

      :overwrite ->
        # Overwrite the oldest chunk
        data = :array.set(buffer.tail, chunk, buffer.data)
        new_tail = rem(buffer.tail + 1, buffer.capacity)
        new_head = rem(buffer.head + 1, buffer.capacity)

        new_buffer = %{
          buffer
          | data: data,
            tail: new_tail,
            head: new_head,
            overflow_count: buffer.overflow_count + 1,
            total_pushed: buffer.total_pushed + 1
        }

        {:ok, new_buffer}

      :block ->
        # Return overflow signal
        new_buffer = %{buffer | overflow_count: buffer.overflow_count + 1}
        {:overflow, new_buffer}
    end
  end

  defp pop_many_acc(buffer, 0, acc) do
    {Enum.reverse(acc), buffer}
  end

  defp pop_many_acc(buffer, n, acc) do
    case pop(buffer) do
      {:ok, chunk, new_buffer} ->
        pop_many_acc(new_buffer, n - 1, [chunk | acc])

      {:empty, _} ->
        {Enum.reverse(acc), buffer}
    end
  end

  defp to_list_acc(_buffer, _index, 0, acc) do
    Enum.reverse(acc)
  end

  defp to_list_acc(buffer, index, remaining, acc) do
    chunk = :array.get(index, buffer.data)
    next_index = rem(index + 1, buffer.capacity)
    to_list_acc(buffer, next_index, remaining - 1, [chunk | acc])
  end
end
