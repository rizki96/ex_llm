defmodule ExLLM.Core.Streaming.Recovery do
  @moduledoc """
  Streaming error recovery and resumption support for ExLLM.

  This module provides functionality to recover from interrupted streaming
  responses, allowing continuation from where the stream was interrupted.

  ## Features

  - Automatic saving of partial responses during streaming
  - Detection of recoverable vs non-recoverable errors
  - Multiple resumption strategies
  - Configurable storage backends
  - Automatic cleanup of old partial responses

  ## Usage

      # Enable recovery when streaming
      {:ok, stream} = ExLLM.stream_chat(:anthropic, messages,
        recovery: [
          enabled: true,
          strategy: :paragraph,
          storage: :memory
        ]
      )
      
      # If stream is interrupted, resume it
      {:ok, resumed_stream} = ExLLM.Core.Streaming.Recovery.resume_stream(recovery_id)
  """

  use GenServer

  alias ExLLM.Types

  @default_ttl :timer.minutes(30)
  @cleanup_interval :timer.minutes(5)

  defmodule State do
    @moduledoc false
    defstruct [
      :storage_backend,
      :partial_responses,
      :cleanup_timer
    ]
  end

  defmodule PartialResponse do
    @moduledoc """
    Represents a partial streaming response that can be resumed.
    """
    defstruct [
      :id,
      :provider,
      :messages,
      :options,
      :chunks,
      :token_count,
      :last_chunk_at,
      :created_at,
      :error_reason,
      :model
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            provider: atom(),
            messages: list(map()),
            options: keyword(),
            chunks: list(Types.StreamChunk.t()),
            token_count: non_neg_integer(),
            last_chunk_at: DateTime.t(),
            created_at: DateTime.t(),
            error_reason: term() | nil,
            model: String.t()
          }
  end

  @doc """
  Starts the StreamRecovery GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes a recoverable stream.
  """
  def init_recovery(provider, messages, options) do
    recovery_id = generate_recovery_id()

    partial = %PartialResponse{
      id: recovery_id,
      provider: provider,
      messages: messages,
      options: options,
      chunks: [],
      token_count: 0,
      created_at: DateTime.utc_now(),
      last_chunk_at: DateTime.utc_now(),
      model: Keyword.get(options, :model)
    }

    GenServer.call(__MODULE__, {:save_partial, partial})
    {:ok, recovery_id}
  end

  @doc """
  Records a chunk for a recoverable stream.
  """
  def record_chunk(recovery_id, chunk) do
    GenServer.cast(__MODULE__, {:record_chunk, recovery_id, chunk})
  end

  @doc """
  Marks a stream as completed (no recovery needed).
  """
  def complete_stream(recovery_id) do
    GenServer.cast(__MODULE__, {:complete_stream, recovery_id})
  end

  @doc """
  Records an error for potential recovery.
  """
  def record_error(recovery_id, error) do
    GenServer.call(__MODULE__, {:record_error, recovery_id, error})
  end

  @doc """
  Gets the partial response (chunks) for a recovery ID.
  """
  def get_partial_response(recovery_id) do
    case GenServer.call(__MODULE__, {:get_partial, recovery_id}) do
      {:ok, partial} -> {:ok, partial.chunks}
      error -> error
    end
  end

  @doc """
  Clears a partial response from memory.
  """
  def clear_partial_response(recovery_id) do
    GenServer.cast(__MODULE__, {:complete_stream, recovery_id})
    :ok
  end

  @doc """
  Attempts to resume a previously interrupted stream.

  ## Strategies

  - `:exact` - Continue from exact cutoff point
  - `:paragraph` - Regenerate from last complete paragraph
  - `:summarize` - Summarize received content and continue
  """
  def resume_stream(recovery_id, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :paragraph)

    case GenServer.call(__MODULE__, {:get_partial, recovery_id}) do
      {:ok, partial} ->
        resume_with_strategy(partial, strategy)

      error ->
        error
    end
  end

  @doc """
  Checks if an error is recoverable.
  """
  def recoverable_error?({:network_error, _}), do: true
  def recoverable_error?({:timeout, _}), do: true
  def recoverable_error?({:stream_interrupted, _}), do: true
  def recoverable_error?({:api_error, %{status: status}}) when status >= 500, do: true
  # Rate limit
  def recoverable_error?({:api_error, %{status: 429}}), do: true
  def recoverable_error?(_), do: false

  @doc """
  Lists all recoverable streams.
  """
  def list_recoverable_streams do
    GenServer.call(__MODULE__, :list_recoverable)
  end

  @doc """
  Cleans up old partial responses.
  """
  def cleanup_old_responses(ttl \\ @default_ttl) do
    GenServer.cast(__MODULE__, {:cleanup, ttl})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    storage_backend = Keyword.get(opts, :storage_backend, :memory)

    # Schedule periodic cleanup
    cleanup_timer = Process.send_after(self(), :cleanup, @cleanup_interval)

    state = %State{
      storage_backend: storage_backend,
      partial_responses: %{},
      cleanup_timer: cleanup_timer
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:save_partial, partial}, _from, state) do
    new_partials = Map.put(state.partial_responses, partial.id, partial)
    {:reply, :ok, %{state | partial_responses: new_partials}}
  end

  @impl true
  def handle_call({:get_partial, recovery_id}, _from, state) do
    case Map.get(state.partial_responses, recovery_id) do
      nil -> {:reply, {:error, :not_found}, state}
      partial -> {:reply, {:ok, partial}, state}
    end
  end

  @impl true
  def handle_call({:record_error, recovery_id, error}, _from, state) do
    case Map.get(state.partial_responses, recovery_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      partial ->
        updated = %{partial | error_reason: error}
        new_partials = Map.put(state.partial_responses, recovery_id, updated)

        recoverable = recoverable_error?(error)
        {:reply, {:ok, recoverable}, %{state | partial_responses: new_partials}}
    end
  end

  @impl true
  def handle_call(:list_recoverable, _from, state) do
    recoverable =
      state.partial_responses
      |> Map.values()
      |> Enum.filter(fn partial ->
        partial.error_reason != nil && recoverable_error?(partial.error_reason)
      end)
      |> Enum.map(fn partial ->
        %{
          id: partial.id,
          provider: partial.provider,
          model: partial.model,
          chunks_received: length(partial.chunks),
          token_count: partial.token_count,
          error: partial.error_reason,
          last_chunk_at: partial.last_chunk_at
        }
      end)

    {:reply, recoverable, state}
  end

  @impl true
  def handle_cast({:record_chunk, recovery_id, chunk}, state) do
    case Map.get(state.partial_responses, recovery_id) do
      nil ->
        {:noreply, state}

      partial when is_map(chunk) ->
        # Check if chunk has valid content
        if Map.has_key?(chunk, :content) and is_binary(chunk.content) do
          # Estimate tokens in chunk (rough approximation)
          chunk_tokens = estimate_chunk_tokens(chunk)

          updated = %{
            partial
            | chunks: partial.chunks ++ [chunk],
              token_count: partial.token_count + chunk_tokens,
              last_chunk_at: DateTime.utc_now()
          }

          new_partials = Map.put(state.partial_responses, recovery_id, updated)
          {:noreply, %{state | partial_responses: new_partials}}
        else
          # Invalid chunk content, ignore
          {:noreply, state}
        end

      _partial ->
        # Invalid chunk, ignore it
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:complete_stream, recovery_id}, state) do
    new_partials = Map.delete(state.partial_responses, recovery_id)
    {:noreply, %{state | partial_responses: new_partials}}
  end

  @impl true
  def handle_cast({:cleanup, ttl}, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -ttl, :millisecond)

    new_partials =
      state.partial_responses
      |> Enum.filter(fn {_id, partial} ->
        DateTime.compare(partial.last_chunk_at, cutoff) == :gt
      end)
      |> Enum.into(%{})

    {:noreply, %{state | partial_responses: new_partials}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_responses()

    # Schedule next cleanup
    Process.cancel_timer(state.cleanup_timer)
    cleanup_timer = Process.send_after(self(), :cleanup, @cleanup_interval)

    {:noreply, %{state | cleanup_timer: cleanup_timer}}
  end

  # Private functions

  defp generate_recovery_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp estimate_chunk_tokens(%{content: content}) do
    # Rough estimate: ~4 characters per token
    div(String.length(content || ""), 4)
  end

  defp resume_with_strategy(partial, :exact) do
    # Continue from exact cutoff
    content =
      partial.chunks
      |> Enum.map(& &1.content)
      |> Enum.join("")

    # Adjust messages to include partial response
    adjusted_messages =
      partial.messages ++
        [
          %{role: "assistant", content: content},
          %{role: "user", content: "Continue from where you left off."}
        ]

    # Adjust token count
    adjusted_options =
      Keyword.update(
        partial.options,
        :max_tokens,
        4000,
        &(&1 - partial.token_count)
      )

    ExLLM.stream_chat(partial.provider, adjusted_messages, adjusted_options)
  end

  defp resume_with_strategy(partial, :paragraph) do
    # Find last complete paragraph
    content =
      partial.chunks
      |> Enum.map(& &1.content)
      |> Enum.join("")

    last_paragraph_end = find_last_paragraph_end(content)
    truncated_content = String.slice(content, 0, last_paragraph_end)

    # Adjust messages
    adjusted_messages =
      partial.messages ++
        [
          %{role: "assistant", content: truncated_content},
          %{
            role: "user",
            content: "Continue from where you left off. Start with a new paragraph."
          }
        ]

    ExLLM.stream_chat(partial.provider, adjusted_messages, partial.options)
  end

  defp resume_with_strategy(partial, :summarize) do
    # Summarize what was received
    content =
      partial.chunks
      |> Enum.map(& &1.content)
      |> Enum.join("")

    summary_prompt = """
    The following is a partial response that was interrupted:

    #{content}

    Please briefly summarize what was covered above, then continue with the rest of the response.
    """

    adjusted_messages =
      partial.messages ++
        [
          %{role: "user", content: summary_prompt}
        ]

    ExLLM.stream_chat(partial.provider, adjusted_messages, partial.options)
  end

  defp find_last_paragraph_end(content) do
    # Find the last double newline or end of sentence before the cutoff
    patterns = ["\n\n", ".\n", ". ", "!\n", "! ", "?\n", "? "]

    last_positions =
      patterns
      |> Enum.map(fn pattern ->
        case :binary.matches(content, pattern) do
          [] ->
            0

          matches ->
            {pos, len} = List.last(matches)
            pos + len
        end
      end)

    case Enum.max(last_positions) do
      0 -> String.length(content)
      pos -> pos
    end
  end
end
