defmodule ExLLM.Infrastructure.CircuitBreaker.Telemetry do
  @moduledoc """
  Telemetry instrumentation for circuit breaker operations.

  Provides comprehensive telemetry events, default handlers, and metrics collection
  for monitoring circuit breaker behavior and performance.
  """

  require Logger

  @events [
    # Circuit lifecycle events
    [:ex_llm, :circuit_breaker, :circuit_created],
    [:ex_llm, :circuit_breaker, :state_change],

    # Call events
    [:ex_llm, :circuit_breaker, :call_success],
    [:ex_llm, :circuit_breaker, :call_failure],
    [:ex_llm, :circuit_breaker, :call_timeout],
    [:ex_llm, :circuit_breaker, :call_rejected],

    # Failure tracking
    [:ex_llm, :circuit_breaker, :failure_recorded],
    [:ex_llm, :circuit_breaker, :success_recorded],

    # Configuration events
    [:ex_llm, :circuit_breaker, :config_updated],
    [:ex_llm, :circuit_breaker, :circuit_reset],

    # Health check events
    [:ex_llm, :circuit_breaker, :health_check],
    [:ex_llm, :circuit_breaker, :health_check, :completed],

    # Adaptive threshold events
    [:ex_llm, :circuit_breaker, :threshold_update],

    # Bulkhead events  
    [:ex_llm, :circuit_breaker, :bulkhead, :metrics_updated],
    [:ex_llm, :circuit_breaker, :bulkhead, :request_accepted],
    [:ex_llm, :circuit_breaker, :bulkhead, :request_rejected],
    [:ex_llm, :circuit_breaker, :bulkhead, :request_queued],

    # Configuration manager events
    [:ex_llm, :circuit_breaker, :config_manager, :config_updated],
    [:ex_llm, :circuit_breaker, :config_manager, :profile_applied],
    [:ex_llm, :circuit_breaker, :config_manager, :config_rollback],
    [:ex_llm, :circuit_breaker, :config_manager, :config_reset]
  ]

  # ETS table for metrics storage
  @metrics_table :ex_llm_circuit_metrics

  @doc """
  List all available telemetry events.
  """
  def events, do: @events

  @doc """
  Initialize the metrics storage.
  """
  def init_metrics do
    if :ets.info(@metrics_table) == :undefined do
      :ets.new(@metrics_table, [:named_table, :public, :set])
    end
  end

  @doc """
  Attach standard telemetry handlers for logging and metrics.
  """
  def attach_default_handlers do
    init_metrics()

    :telemetry.attach_many(
      "ex_llm_circuit_breaker_logger",
      @events,
      &handle_telemetry_event/4,
      %{handler_type: :logger}
    )

    :telemetry.attach_many(
      "ex_llm_circuit_breaker_metrics",
      @events,
      &handle_telemetry_event/4,
      %{handler_type: :metrics}
    )

    :ok
  end

  @doc """
  Get circuit breaker metrics for monitoring systems.
  """
  def get_metrics(:all) do
    circuits = :ets.tab2list(:ex_llm_circuit_breakers)

    circuits
    |> Enum.map(fn {circuit_name, _state} ->
      # Convert string keys to atoms for test compatibility
      key = if is_binary(circuit_name), do: String.to_atom(circuit_name), else: circuit_name
      {key, get_circuit_metrics(circuit_name)}
    end)
    |> Map.new()
  end

  def get_metrics(circuit_name) do
    get_circuit_metrics(circuit_name)
  end

  @doc """
  Get dashboard data for circuit breaker visualization.
  """
  def dashboard_data do
    circuits = :ets.tab2list(:ex_llm_circuit_breakers)

    circuit_data =
      Enum.map(circuits, fn {name, state} ->
        metrics = get_circuit_metrics(name)

        %{
          name: name,
          state: state.state,
          failure_count: state.failure_count,
          success_rate: metrics.success_rate,
          total_calls: metrics.total_calls,
          config: state.config
        }
      end)

    summary = %{
      total_circuits: length(circuits),
      open_circuits: Enum.count(circuit_data, &(&1.state == :open)),
      half_open_circuits: Enum.count(circuit_data, &(&1.state == :half_open)),
      closed_circuits: Enum.count(circuit_data, &(&1.state == :closed))
    }

    alerts = generate_alerts(circuit_data)

    %{
      circuits: circuit_data,
      summary: summary,
      alerts: alerts
    }
  end

  # Private functions

  defp handle_telemetry_event(event, _measurements, metadata, %{handler_type: :logger}) do
    case event do
      [:ex_llm, :circuit_breaker, :state_change] ->
        Logger.info(
          "Circuit breaker #{metadata.circuit_name} state changed: #{metadata.old_state} -> #{metadata.new_state}"
        )

      [:ex_llm, :circuit_breaker, :call_rejected] ->
        Logger.info(
          "Circuit breaker #{metadata.circuit_name} rejected call: #{metadata.reason}"
        )

      [:ex_llm, :circuit_breaker, :failure_recorded] ->
        Logger.info(
          "Circuit breaker #{metadata.circuit_name} recorded failure (#{metadata.failure_count}/#{metadata.threshold})"
        )

      _ ->
        :ok
    end
  end

  defp handle_telemetry_event(event, measurements, metadata, %{handler_type: :metrics}) do
    # Update metrics in ETS
    case event do
      [:ex_llm, :circuit_breaker, :call_success] ->
        update_metric(metadata.circuit_name, :successes, 1)
        update_metric(metadata.circuit_name, :total_calls, 1)

        if duration = measurements[:duration],
          do: record_duration(metadata.circuit_name, duration)

      [:ex_llm, :circuit_breaker, :call_failure] ->
        update_metric(metadata.circuit_name, :failures, 1)
        update_metric(metadata.circuit_name, :total_calls, 1)

        if duration = measurements[:duration],
          do: record_duration(metadata.circuit_name, duration)

      [:ex_llm, :circuit_breaker, :call_timeout] ->
        update_metric(metadata.circuit_name, :timeouts, 1)
        update_metric(metadata.circuit_name, :total_calls, 1)

      [:ex_llm, :circuit_breaker, :call_rejected] ->
        update_metric(metadata.circuit_name, :rejections, 1)

      [:ex_llm, :circuit_breaker, :state_change] ->
        record_state_change(metadata.circuit_name, metadata.new_state)

      _ ->
        :ok
    end
  end

  defp get_circuit_metrics(circuit_name) do
    metrics_key = {:metrics, circuit_name}

    default_metrics = %{
      total_calls: 0,
      successes: 0,
      failures: 0,
      timeouts: 0,
      rejections: 0,
      success_rate: 0.0,
      failure_rate: 0.0,
      avg_duration: 0.0,
      state: :unknown
    }

    case :ets.lookup(@metrics_table, metrics_key) do
      [{^metrics_key, metrics}] ->
        metrics
        |> Map.put(:circuit_name, circuit_name)
        |> calculate_rates()

      [] ->
        # Try to get state from circuit breaker
        state =
          case :ets.lookup(:ex_llm_circuit_breakers, circuit_name) do
            [{^circuit_name, circuit_state}] -> circuit_state.state
            [] -> :unknown
          end

        Map.put(default_metrics, :state, state)
    end
  end

  defp update_metric(circuit_name, metric, increment) do
    metrics_key = {:metrics, circuit_name}

    # Get existing metrics or create new ones
    metrics =
      case :ets.lookup(@metrics_table, metrics_key) do
        [{^metrics_key, existing}] ->
          existing

        [] ->
          %{
            total_calls: 0,
            successes: 0,
            failures: 0,
            timeouts: 0,
            rejections: 0
          }
      end

    # Update the specific metric
    updated_metrics = Map.update(metrics, metric, increment, &(&1 + increment))

    # Store back in ETS
    :ets.insert(@metrics_table, {metrics_key, updated_metrics})

    # Also ensure we have the circuit state recorded
    state_key = {:state, circuit_name}

    if :ets.lookup(@metrics_table, state_key) == [] do
      # Get state from circuit breaker if not already recorded
      case :ets.lookup(:ex_llm_circuit_breakers, circuit_name) do
        [{^circuit_name, circuit_state}] ->
          :ets.insert(@metrics_table, {state_key, circuit_state.state})

        [] ->
          :ok
      end
    end
  end

  defp record_duration(circuit_name, duration) do
    duration_key = {:durations, circuit_name}

    case :ets.lookup(@metrics_table, duration_key) do
      [{^duration_key, durations}] ->
        :ets.insert(@metrics_table, {duration_key, [duration | Enum.take(durations, 99)]})

      [] ->
        :ets.insert(@metrics_table, {duration_key, [duration]})
    end
  end

  defp record_state_change(circuit_name, new_state) do
    state_key = {:state, circuit_name}
    :ets.insert(@metrics_table, {state_key, new_state})

    # Also update the metrics record to include the state
    metrics_key = {:metrics, circuit_name}

    case :ets.lookup(@metrics_table, metrics_key) do
      [{^metrics_key, metrics}] ->
        :ets.insert(@metrics_table, {metrics_key, Map.put(metrics, :state, new_state)})

      [] ->
        :ok
    end
  end

  defp calculate_rates(metrics) do
    total = Map.get(metrics, :total_calls, 0)

    # Get current state from the state key if stored
    current_state =
      case :ets.lookup(@metrics_table, {:state, metrics[:circuit_name]}) do
        [{_, state}] -> state
        [] -> Map.get(metrics, :state, :unknown)
      end

    base_metrics =
      if total > 0 do
        metrics
        |> Map.put(:success_rate, Map.get(metrics, :successes, 0) / total)
        |> Map.put(:failure_rate, Map.get(metrics, :failures, 0) / total)
      else
        metrics
        |> Map.put(:success_rate, 0.0)
        |> Map.put(:failure_rate, 0.0)
      end

    Map.put(base_metrics, :state, current_state)
  end

  defp generate_alerts(circuit_data) do
    Enum.flat_map(circuit_data, fn circuit ->
      alerts = []

      # Alert for open circuits
      alerts =
        if circuit.state == :open do
          [
            %{
              circuit_name: circuit.name,
              type: :circuit_open,
              severity: :high,
              message: "Circuit #{circuit.name} is open"
            }
            | alerts
          ]
        else
          alerts
        end

      # Alert for high failure rate
      alerts =
        if circuit.total_calls > 10 && circuit.success_rate < 0.5 do
          [
            %{
              circuit_name: circuit.name,
              type: :high_failure_rate,
              severity: :medium,
              message:
                "Circuit #{circuit.name} has high failure rate: #{Float.round((1 - circuit.success_rate) * 100, 1)}%"
            }
            | alerts
          ]
        else
          alerts
        end

      alerts
    end)
  end

  # Placeholder metrics integration functions
  # These would be replaced with actual metrics library integration

  def increment_counter(_metric, _opts), do: :ok
  def record_histogram(_metric, _value, _opts), do: :ok
  def set_gauge(_metric, _value, _opts), do: :ok
end
