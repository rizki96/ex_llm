defmodule ExLLM.CircuitBreaker do
  @moduledoc """
  High-performance circuit breaker implementation using ETS for concurrent access.

  Implements the classic three-state pattern:
  - :closed - Normal operation, requests pass through
  - :open - Service failing, requests blocked with fail-fast
  - :half_open - Testing service recovery with limited requests
  """

  @table_name :ex_llm_circuit_breakers

  # Circuit breaker state structure
  @circuit_fields [
    # Circuit identifier
    :name,
    # :closed | :open | :half_open  
    :state,
    # Current consecutive failures
    :failure_count,
    # Successes in half-open state
    :success_count,
    # Timestamp of last failure
    :last_failure_time,
    # Circuit configuration
    :config
  ]

  defstruct @circuit_fields

  @doc """
  Initialize the circuit breaker system.
  Called during ExLLM application startup.
  """
  def init do
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])
  end

  @doc """
  Execute a function with circuit breaker protection.

  ## Options
    * `:failure_threshold` - Number of failures before opening circuit (default: 5)
    * `:success_threshold` - Number of successes to close from half-open (default: 3)
    * `:reset_timeout` - Milliseconds before attempting half-open (default: 30_000)
    * `:timeout` - Function execution timeout (default: 30_000)
    * `:name` - Circuit name (auto-generated if not provided)

  ## Examples
      iex> ExLLM.CircuitBreaker.call("api_service", fn -> 
      ...>   HTTPClient.get("/api/data")
      ...> end)
      {:ok, response}
      
      iex> ExLLM.CircuitBreaker.call("failing_service", fn -> 
      ...>   raise "Service down"
      ...> end)
      {:error, :circuit_open}
  """
  def call(circuit_name, fun, opts \\ []) when is_function(fun, 0) do
    config = build_config(opts)
    state = get_or_create_circuit(circuit_name, config)

    case state.state do
      :closed ->
        execute_with_monitoring(circuit_name, fun, config)

      :open ->
        if should_attempt_reset?(state, config) do
          # Transition to half-open and try the call
          transition_to_half_open(circuit_name)
          emit_telemetry(:state_change, circuit_name, :open, :half_open)
          execute_with_monitoring(circuit_name, fun, config)
        else
          emit_telemetry(:call_rejected, circuit_name, %{reason: :circuit_open})
          {:error, :circuit_open}
        end

      :half_open ->
        execute_with_monitoring(circuit_name, fun, config)
    end
  end

  @doc """
  Get current circuit breaker state and statistics.
  """
  def get_stats(circuit_name) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, state}] ->
        {:ok, Map.from_struct(state)}

      [] ->
        {:error, :circuit_not_found}
    end
  end

  @doc """
  Manually reset a circuit breaker to closed state.
  """
  def reset(circuit_name) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, state}] ->
        new_state = %{
          state
          | state: :closed,
            failure_count: 0,
            success_count: 0,
            last_failure_time: nil
        }

        :ets.insert(@table_name, {circuit_name, new_state})
        emit_telemetry(:state_change, circuit_name, state.state, :closed)
        emit_telemetry(:circuit_reset, circuit_name, %{})
        :ok

      [] ->
        {:error, :circuit_not_found}
    end
  end

  @doc """
  Update circuit breaker configuration at runtime.
  """
  def update_config(circuit_name, opts) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, state}] ->
        new_config = build_config(opts)

        # Validate config
        case validate_config(new_config) do
          :ok ->
            updated_state = %{state | config: Map.merge(state.config, new_config)}
            :ets.insert(@table_name, {circuit_name, updated_state})
            emit_telemetry(:config_updated, circuit_name, %{config: new_config})
            :ok

          {:error, _} = error ->
            error
        end

      [] ->
        {:error, :circuit_not_found}
    end
  end

  @doc """
  Batch update configuration for multiple circuits.
  """
  def batch_update_config(circuit_names, opts) do
    circuit_names
    |> Enum.map(fn circuit_name ->
      {circuit_name, update_config(circuit_name, opts)}
    end)
    |> Map.new()
  end

  @doc """
  Apply a configuration profile to a circuit using ConfigManager.
  """
  def apply_profile(circuit_name, profile_name) do
    ExLLM.CircuitBreaker.ConfigManager.apply_profile(circuit_name, profile_name)
  end

  @doc """
  Update circuit configuration using ConfigManager with validation and history.
  """
  def update_circuit_config(circuit_name, config_changes) do
    ExLLM.CircuitBreaker.ConfigManager.update_circuit(circuit_name, config_changes)
  end

  @doc """
  Get circuit configuration from ConfigManager.
  """
  def get_circuit_config(circuit_name) do
    ExLLM.CircuitBreaker.ConfigManager.get_config(circuit_name)
  end

  @doc """
  Rollback circuit to previous configuration.
  """
  def rollback_config(circuit_name) do
    ExLLM.CircuitBreaker.ConfigManager.rollback(circuit_name)
  end

  @doc """
  Execute a function with both circuit breaker and bulkhead protection.

  This combines circuit breaker fault tolerance with bulkhead concurrency limiting.
  """
  def call_with_bulkhead(circuit_name, fun, opts \\ []) when is_function(fun, 0) do
    ExLLM.CircuitBreaker.Bulkhead.execute(circuit_name, fun, opts)
  end

  # Private Implementation

  defp execute_with_monitoring(circuit_name, fun, config) do
    start_time = System.monotonic_time(:millisecond)
    timeout = config.timeout

    # Create task with proper supervision
    task =
      Task.async(fn ->
        try do
          fun.()
        rescue
          error ->
            {:error, error}
        catch
          :exit, reason ->
            {:exit, reason}

          kind, payload ->
            {kind, payload}
        end
      end)

    case Task.yield(task, timeout) do
      {:ok, {:error, error}} ->
        # Function raised an error
        duration = System.monotonic_time(:millisecond) - start_time
        record_failure(circuit_name, error)
        emit_telemetry(:call_failure, circuit_name, %{duration: duration, error: error})
        {:error, error}

      {:ok, {:exit, reason}} ->
        # Function exited
        duration = System.monotonic_time(:millisecond) - start_time
        record_failure(circuit_name, {:exit, reason})
        emit_telemetry(:call_failure, circuit_name, %{duration: duration, error: {:exit, reason}})
        {:error, {:exit, reason}}

      {:ok, {:ok, _} = success} ->
        # Function returned success tuple
        duration = System.monotonic_time(:millisecond) - start_time
        record_success(circuit_name)
        emit_telemetry(:call_success, circuit_name, %{duration: duration})
        success

      {:ok, {kind, payload}} when kind in [:throw, :error] ->
        # Other caught errors
        duration = System.monotonic_time(:millisecond) - start_time
        record_failure(circuit_name, {kind, payload})
        emit_telemetry(:call_failure, circuit_name, %{duration: duration, error: {kind, payload}})
        {:error, {kind, payload}}

      {:ok, result} ->
        # Success (non-tuple result)
        duration = System.monotonic_time(:millisecond) - start_time
        record_success(circuit_name)
        emit_telemetry(:call_success, circuit_name, %{duration: duration})
        {:ok, result}

      {:exit, reason} ->
        # Task itself crashed
        duration = System.monotonic_time(:millisecond) - start_time
        record_failure(circuit_name, {:task_exit, reason})

        emit_telemetry(:call_failure, circuit_name, %{
          duration: duration,
          error: {:task_exit, reason}
        })

        {:error, {:task_exit, reason}}

      nil ->
        # Task timed out
        Task.shutdown(task, :brutal_kill)
        record_failure(circuit_name, :timeout)
        emit_telemetry(:call_timeout, circuit_name, %{timeout: timeout})
        {:error, :timeout}
    end
  end

  defp record_success(circuit_name) do
    [{^circuit_name, state}] = :ets.lookup(@table_name, circuit_name)

    new_state =
      case state.state do
        :half_open ->
          new_success_count = state.success_count + 1

          if new_success_count >= state.config.success_threshold do
            %{state | state: :closed, success_count: 0, failure_count: 0}
          else
            %{state | success_count: new_success_count}
          end

        :closed ->
          %{state | failure_count: 0}

        _ ->
          # For open state (shouldn't happen) or any other state
          state
      end

    :ets.insert(@table_name, {circuit_name, new_state})

    if state.state != new_state.state do
      emit_telemetry(:state_change, circuit_name, state.state, new_state.state)
    end
  end

  defp record_failure(circuit_name, reason) do
    [{^circuit_name, state}] = :ets.lookup(@table_name, circuit_name)

    new_failure_count = state.failure_count + 1
    current_time = System.monotonic_time(:millisecond)

    new_state =
      if new_failure_count >= state.config.failure_threshold do
        %{state | state: :open, failure_count: new_failure_count, last_failure_time: current_time}
      else
        %{state | failure_count: new_failure_count, last_failure_time: current_time}
      end

    :ets.insert(@table_name, {circuit_name, new_state})

    if state.state != new_state.state do
      emit_telemetry(:state_change, circuit_name, state.state, new_state.state)
    end

    emit_telemetry(:failure_recorded, circuit_name, %{
      reason: reason,
      failure_count: new_failure_count,
      threshold: state.config.failure_threshold
    })
  end

  defp should_attempt_reset?(state, config) do
    current_time = System.monotonic_time(:millisecond)
    time_since_failure = current_time - (state.last_failure_time || 0)
    time_since_failure >= config.reset_timeout
  end

  defp transition_to_half_open(circuit_name) do
    [{^circuit_name, state}] = :ets.lookup(@table_name, circuit_name)
    new_state = %{state | state: :half_open, success_count: 0}
    :ets.insert(@table_name, {circuit_name, new_state})
  end

  defp get_or_create_circuit(circuit_name, config) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, state}] ->
        # Return existing circuit, don't update config
        state

      [] ->
        create_circuit(circuit_name, config)
    end
  end

  defp create_circuit(circuit_name, config) do
    state = %__MODULE__{
      name: circuit_name,
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      config: config
    }

    :ets.insert(@table_name, {circuit_name, state})
    emit_telemetry(:circuit_created, circuit_name, %{config: config})
    state
  end

  defp build_config(opts) do
    %{
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      success_threshold: Keyword.get(opts, :success_threshold, 3),
      reset_timeout: Keyword.get(opts, :reset_timeout, 30_000),
      timeout: Keyword.get(opts, :timeout, 30_000)
    }
  end

  defp emit_telemetry(event, circuit_name, metadata) when is_map(metadata) do
    measurements = %{count: 1}

    # Only include duration if it's provided in metadata
    measurements =
      if Map.has_key?(metadata, :duration) do
        Map.put(measurements, :duration, metadata.duration)
      else
        measurements
      end

    :telemetry.execute(
      [:ex_llm, :circuit_breaker, event],
      measurements,
      Map.merge(%{circuit_name: circuit_name}, metadata)
    )
  end

  defp emit_telemetry(event, circuit_name, old_state, new_state) do
    emit_telemetry(event, circuit_name, %{old_state: old_state, new_state: new_state})
  end

  defp validate_config(config) do
    cond do
      config.failure_threshold <= 0 ->
        {:error, {:invalid_config, :failure_threshold}}

      config.success_threshold <= 0 ->
        {:error, {:invalid_config, :success_threshold}}

      config.reset_timeout < 0 ->
        {:error, {:invalid_config, :reset_timeout}}

      config.timeout <= 0 ->
        {:error, {:invalid_config, :timeout}}

      true ->
        :ok
    end
  end
end
