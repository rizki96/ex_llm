defmodule ExLLM.Infrastructure.CircuitBreaker.BulkheadWorker do
  @moduledoc """
  GenServer that manages bulkhead state for a single circuit.

  This GenServer serializes all requests for a given circuit, eliminating
  race conditions and providing precise concurrency control with queuing.
  """

  use GenServer
  require Logger

  @vsn 1

  defstruct [
    # The name of the circuit this worker manages
    :circuit_name,
    # The bulkhead configuration
    :config,
    # Count of currently executing requests
    active_count: 0,
    # Map of monitor_ref => from_tuple for active requests
    active_monitors: %{},
    # :queue of from_tuples for waiting requests
    wait_queue: :queue.new(),
    # Metrics
    total_accepted: 0,
    total_rejected: 0,
    total_timeouts: 0
  ]

  # =================================================================
  # Public API (Client Functions)
  # =================================================================

  def start_link(opts) do
    # The circuit_name will be passed in from the supervisor
    {circuit_name, config} = Keyword.fetch!(opts, :circuit_config)
    GenServer.start_link(__MODULE__, {circuit_name, config}, name: via_tuple(circuit_name))
  end

  @doc """
  Requests a slot to execute a function. This is the primary entry point.
  """
  def execute(pid, fun, timeout) do
    # The GenServer.call timeout handles our queue timeout automatically.
    try do
      case GenServer.call(pid, :request, timeout) do
        {:ok, :execute} ->
          # Just execute the function - monitoring will handle cleanup
          fun.()

        {:error, reason} ->
          {:error, reason}
      end
    catch
      :exit, {:timeout, _} ->
        # GenServer.call timed out - this means we were queued and timed out
        {:error, :bulkhead_timeout}
    end
  end

  def get_metrics(pid) do
    GenServer.call(pid, :get_metrics)
  end

  @doc """
  Updates the configuration for this bulkhead worker.
  """
  def update_config(pid, new_config) do
    GenServer.call(pid, {:update_config, new_config})
  end

  @doc """
  Builds the name tuple for the Registry.
  """
  def via_tuple(circuit_name) do
    {:via, Registry, {ExLLM.Infrastructure.CircuitBreaker.Bulkhead.Registry, circuit_name}}
  end

  # =================================================================
  # GenServer Callbacks
  # =================================================================

  @impl true
  def init({circuit_name, config}) do
    state = %__MODULE__{
      circuit_name: circuit_name,
      config: config,
      wait_queue: :queue.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:request, from, state) do
    cond do
      # Slot available - execute immediately
      state.active_count < state.config.max_concurrent ->
        grant_slot(from, state)

      # Queue has space - enqueue the request
      :queue.len(state.wait_queue) < state.config.max_queued ->
        enqueue_request(from, state)

      # Both bulkhead and queue are full - reject
      true ->
        reject_request(state)
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      active_count: state.active_count,
      queued_count: :queue.len(state.wait_queue),
      total_accepted: state.total_accepted,
      total_rejected: state.total_rejected,
      total_timeouts: state.total_timeouts,
      config: state.config
    }

    {:reply, metrics, state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    # Update configuration
    new_state = %{state | config: new_config}

    # Process queue in case the new config allows more concurrent requests
    final_state = process_queue(new_state)

    {:reply, :ok, final_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # A monitored process crashed or exited
    case Map.pop(state.active_monitors, ref) do
      {nil, _monitors} ->
        # Not one of our monitored processes, ignore
        {:noreply, state}

      {_from, remaining_monitors} ->
        # One of our active processes died, free up the slot
        new_state = %{
          state
          | active_count: max(0, state.active_count - 1),
            active_monitors: remaining_monitors
        }

        final_state = process_queue(new_state)
        {:noreply, final_state}
    end
  end

  # =================================================================
  # Private Helper Functions
  # =================================================================

  defp grant_slot(from, state) do
    # Monitor the calling process for cleanup
    {caller_pid, _tag} = from
    monitor_ref = Process.monitor(caller_pid)

    new_state = %{
      state
      | active_count: state.active_count + 1,
        active_monitors: Map.put(state.active_monitors, monitor_ref, from),
        total_accepted: state.total_accepted + 1
    }

    {:reply, {:ok, :execute}, new_state}
  end

  defp enqueue_request(from, state) do
    new_queue = :queue.in(from, state.wait_queue)
    new_state = %{state | wait_queue: new_queue}

    # Don't reply yet - the caller will block until we reply later
    {:noreply, new_state}
  end

  defp reject_request(state) do
    new_state = %{state | total_rejected: state.total_rejected + 1}

    # Determine error type based on queue config
    error =
      if state.config.max_queued == 0 do
        :bulkhead_full
      else
        :bulkhead_queue_full
      end

    {:reply, {:error, error}, new_state}
  end

  defp process_queue(state) do
    case :queue.out(state.wait_queue) do
      {{:value, from}, remaining_queue} when state.active_count < state.config.max_concurrent ->
        # We have a waiting caller and a free slot
        {caller_pid, _tag} = from
        monitor_ref = Process.monitor(caller_pid)

        # Reply to the waiting caller to unblock them
        GenServer.reply(from, {:ok, :execute})

        new_state = %{
          state
          | active_count: state.active_count + 1,
            active_monitors: Map.put(state.active_monitors, monitor_ref, from),
            wait_queue: remaining_queue,
            total_accepted: state.total_accepted + 1
        }

        # Check if we can process more from the queue (recursive call returns state)
        process_queue_recursive(new_state)

      _ ->
        # No one waiting or no slots available
        state
    end
  end

  # Helper for recursive queue processing that returns state only
  defp process_queue_recursive(state) do
    case :queue.out(state.wait_queue) do
      {{:value, from}, remaining_queue} when state.active_count < state.config.max_concurrent ->
        # We have a waiting caller and a free slot
        {caller_pid, _tag} = from
        monitor_ref = Process.monitor(caller_pid)

        # Reply to the waiting caller to unblock them
        GenServer.reply(from, {:ok, :execute})

        new_state = %{
          state
          | active_count: state.active_count + 1,
            active_monitors: Map.put(state.active_monitors, monitor_ref, from),
            wait_queue: remaining_queue,
            total_accepted: state.total_accepted + 1
        }

        # Continue processing queue
        process_queue_recursive(new_state)

      _ ->
        # No one waiting or no slots available
        state
    end
  end
end
