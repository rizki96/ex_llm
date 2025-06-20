defmodule ExLLM.Infrastructure.Streaming.StreamRecovery do
  @moduledoc """
  Handles automatic recovery for streaming responses.
  
  This module provides resilience for streaming operations by:
  - Automatically reconnecting on network failures
  - Resuming from the last successfully received chunk
  - Detecting and handling duplicate chunks
  - Implementing exponential backoff for retries
  
  ## Options
  
    * `:max_retries` - Maximum number of reconnection attempts (default: 3)
    * `:initial_backoff` - Initial backoff in milliseconds (default: 1000)
    * `:max_backoff` - Maximum backoff in milliseconds (default: 30000)
    * `:backoff_multiplier` - Backoff multiplier (default: 2)
    * `:checkpoint_interval` - Chunks between checkpoints (default: 100)
  """
  
  use GenServer
  require Logger
  
  alias ExLLM.Types.StreamChunk
  
  @default_opts [
    max_retries: 3,
    initial_backoff: 1_000,
    max_backoff: 30_000,
    backoff_multiplier: 2,
    checkpoint_interval: 100
  ]
  
  @type state :: %{
    stream_fn: function(),
    callback: function(),
    options: keyword(),
    retry_count: non_neg_integer(),
    last_chunk_id: String.t() | nil,
    chunk_buffer: list(StreamChunk.t()),
    checkpoint: map() | nil,
    status: :active | :recovering | :failed
  }
  
  # Client API
  
  @doc """
  Starts a recoverable stream.
  
  ## Parameters
  
    * `stream_fn` - Function that starts the stream (arity 1, receives resume_from option)
    * `callback` - Function to call with each chunk
    * `options` - Recovery options
  """
  @spec start_stream(function(), function(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_stream(stream_fn, callback, options \\ []) do
    GenServer.start_link(__MODULE__, {stream_fn, callback, options})
  end
  
  @doc """
  Gracefully stops a recoverable stream.
  """
  @spec stop_stream(pid()) :: :ok
  def stop_stream(pid) do
    GenServer.stop(pid, :normal)
  end
  
  # Server callbacks
  
  @impl GenServer
  def init({stream_fn, callback, options}) do
    opts = Keyword.merge(@default_opts, options)
    
    state = %{
      stream_fn: stream_fn,
      callback: callback,
      options: opts,
      retry_count: 0,
      last_chunk_id: nil,
      chunk_buffer: [],
      checkpoint: nil,
      status: :active
    }
    
    # Start the initial stream
    send(self(), :start_stream)
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_info(:start_stream, state) do
    resume_opts = build_resume_options(state)
    
    case state.stream_fn.(resume_opts) do
      {:ok, stream_pid} ->
        Process.monitor(stream_pid)
        {:noreply, %{state | status: :active, retry_count: 0}}
        
      {:error, reason} ->
        handle_stream_error(reason, state)
    end
  end
  
  def handle_info({:stream_chunk, chunk}, state) do
    # Check for duplicate chunks
    if is_duplicate_chunk?(chunk, state) do
      Logger.debug("Skipping duplicate chunk: #{inspect(chunk.id)}")
      {:noreply, state}
    else
      # Process the chunk
      state = process_chunk(chunk, state)
      {:noreply, state}
    end
  end
  
  def handle_info({:stream_error, error}, state) do
    Logger.error("Stream error: #{inspect(error)}")
    handle_stream_error(error, state)
  end
  
  def handle_info({:stream_complete}, state) do
    # Stream completed successfully
    state.callback.(%{done: true})
    {:stop, :normal, state}
  end
  
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.warning("Stream process died: #{inspect(reason)}")
    handle_stream_error({:process_died, reason}, state)
  end
  
  def handle_info(:retry_stream, state) do
    Logger.info("Retrying stream (attempt #{state.retry_count + 1}/#{state.options[:max_retries]})")
    send(self(), :start_stream)
    {:noreply, %{state | retry_count: state.retry_count + 1}}
  end
  
  # Private functions
  
  defp build_resume_options(state) do
    base_opts = [
      stream_recovery_pid: self()
    ]
    
    if state.last_chunk_id do
      Keyword.put(base_opts, :resume_from, state.last_chunk_id)
    else
      base_opts
    end
  end
  
  defp is_duplicate_chunk?(chunk, state) do
    chunk.id && chunk.id in Enum.map(state.chunk_buffer, & &1.id)
  end
  
  defp process_chunk(chunk, state) do
    # Update last chunk ID
    state = if chunk.id, do: %{state | last_chunk_id: chunk.id}, else: state
    
    # Add to buffer (keep last 100 chunks for duplicate detection)
    buffer = [chunk | state.chunk_buffer] |> Enum.take(100)
    state = %{state | chunk_buffer: buffer}
    
    # Forward to callback
    state.callback.(chunk)
    
    # Maybe create checkpoint
    if should_checkpoint?(state) do
      create_checkpoint(state)
    else
      state
    end
  end
  
  defp should_checkpoint?(state) do
    interval = state.options[:checkpoint_interval]
    rem(length(state.chunk_buffer), interval) == 0
  end
  
  defp create_checkpoint(state) do
    checkpoint = %{
      last_chunk_id: state.last_chunk_id,
      chunk_count: length(state.chunk_buffer),
      timestamp: System.system_time(:second)
    }
    
    %{state | checkpoint: checkpoint}
  end
  
  defp handle_stream_error(error, state) do
    if state.retry_count < state.options[:max_retries] do
      # Calculate backoff
      backoff = calculate_backoff(state)
      
      Logger.info("Stream recovery: retrying in #{backoff}ms")
      
      # Schedule retry
      Process.send_after(self(), :retry_stream, backoff)
      
      {:noreply, %{state | status: :recovering}}
    else
      # Max retries exceeded
      Logger.error("Stream recovery failed after #{state.options[:max_retries]} attempts")
      
      state.callback.(%{
        error: true,
        message: "Stream failed after #{state.options[:max_retries]} recovery attempts",
        original_error: error,
        done: true
      })
      
      {:stop, {:error, :max_retries_exceeded}, state}
    end
  end
  
  defp calculate_backoff(state) do
    base = state.options[:initial_backoff]
    multiplier = state.options[:backoff_multiplier]
    max_backoff = state.options[:max_backoff]
    
    backoff = base * :math.pow(multiplier, state.retry_count) |> round()
    min(backoff, max_backoff)
  end
end
