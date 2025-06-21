defmodule ExLLM.Infrastructure.CircuitBreaker.Adaptive do
  @moduledoc """
  Adaptive circuit breaker that automatically adjusts failure thresholds based on error patterns.

  This module runs as a GenServer that periodically analyzes circuit performance and 
  adjusts thresholds to optimize fault tolerance and availability.

  ## Configuration

      config :ex_llm, :circuit_breaker,
        adaptive: %{
          enabled: true,
          update_interval: 60_000,       # 1 minute
          min_calls_for_adaptation: 10,  # Minimum calls before adapting
          adaptation_factor: 0.1,        # How aggressively to adapt (0.0-1.0)
          min_threshold: 2,              # Minimum failure threshold
          max_threshold: 20              # Maximum failure threshold
        }

  ## Adaptation Algorithm

  The adaptive algorithm analyzes recent circuit performance and adjusts thresholds:

  - **High error rate** (>30%): Decrease threshold for faster fault detection
  - **Moderate error rate** (10-30%): Maintain current threshold
  - **Low error rate** (<10%): Increase threshold for more tolerance
  - **Very low error rate** (<2%): Significantly increase threshold

  Adjustments are gradual and bounded by min/max limits to prevent oscillation.
  """

  use GenServer
  alias ExLLM.Infrastructure.Logger

  @table_name :ex_llm_circuit_adaptive_state

  # Default configuration
  @default_config %{
    enabled: false,
    update_interval: 60_000,
    min_calls_for_adaptation: 10,
    adaptation_factor: 0.1,
    min_threshold: 2,
    max_threshold: 20
  }

  defstruct [
    :config,
    :timer_ref
  ]

  ## Public API

  @doc """
  Start the adaptive circuit breaker GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger threshold updates for all circuits.
  """
  def update_thresholds do
    GenServer.call(__MODULE__, :update_thresholds)
  end

  @doc """
  Get adaptive metrics for a specific circuit.
  """
  def get_circuit_metrics(circuit_name) do
    # Ensure table exists
    if :ets.info(@table_name) == :undefined do
      :ets.new(@table_name, [
        :named_table,
        :public,
        :set,
        read_concurrency: true
      ])
    end

    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, metrics}] ->
        metrics

      [] ->
        %{
          total_calls: 0,
          error_count: 0,
          error_rate: 0.0,
          current_threshold: get_default_threshold(),
          last_updated: nil,
          adaptation_history: []
        }
    end
  end

  @doc """
  Get configuration for the adaptive system.
  """
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  @doc """
  Update configuration for the adaptive system.
  """
  def update_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    config = build_config(opts)

    # Create ETS table for adaptive state
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true
    ])

    state = %__MODULE__{
      config: config,
      timer_ref: nil
    }

    # Start periodic updates if enabled
    state =
      if config.enabled do
        schedule_update(state)
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def handle_call(:update_thresholds, _from, state) do
    result = perform_threshold_updates(state.config)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    updated_config = Map.merge(state.config, new_config)

    # Cancel existing timer
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    # Restart timer with new interval if enabled
    new_state = %{state | config: updated_config}

    new_state =
      if updated_config.enabled do
        schedule_update(new_state)
      else
        %{new_state | timer_ref: nil}
      end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:update_thresholds, state) do
    perform_threshold_updates(state.config)
    new_state = schedule_update(state)
    {:noreply, new_state}
  end

  ## Private Implementation

  defp build_config(opts) do
    # Handle both keyword list and map inputs
    opts_map = if is_list(opts), do: Map.new(opts), else: opts

    app_config = Application.get_env(:ex_llm, :circuit_breaker, %{})
    adaptive_config = Map.get(app_config, :adaptive, %{})

    @default_config
    |> Map.merge(adaptive_config)
    |> Map.merge(opts_map)
  end

  defp schedule_update(state) do
    timer_ref = Process.send_after(self(), :update_thresholds, state.config.update_interval)
    %{state | timer_ref: timer_ref}
  end

  defp perform_threshold_updates(config) do
    circuits = :ets.tab2list(:ex_llm_circuit_breakers)

    results =
      Enum.map(circuits, fn {circuit_name, circuit_state} ->
        {circuit_name, update_circuit_threshold(circuit_name, circuit_state, config)}
      end)

    Logger.debug("Updated thresholds for #{length(results)} circuits")
    results
  end

  defp update_circuit_threshold(circuit_name, circuit_state, config) do
    # Get telemetry metrics for this circuit
    telemetry_metrics = ExLLM.Infrastructure.CircuitBreaker.Telemetry.get_metrics(circuit_name)

    # Only adapt if we have enough calls
    if telemetry_metrics.total_calls >= config.min_calls_for_adaptation do
      error_rate = telemetry_metrics.failure_rate
      current_threshold = circuit_state.config.failure_threshold

      # Calculate new threshold based on error rate
      new_threshold = calculate_new_threshold(error_rate, current_threshold, config)

      if new_threshold != current_threshold do
        # Update circuit configuration
        ExLLM.Infrastructure.CircuitBreaker.update_config(circuit_name,
          failure_threshold: new_threshold
        )

        # Store adaptive metrics
        store_adaptive_metrics(circuit_name, telemetry_metrics, new_threshold)

        # Emit telemetry event
        :telemetry.execute(
          [:ex_llm, :circuit_breaker, :threshold_update],
          %{
            old_threshold: current_threshold,
            new_threshold: new_threshold,
            error_rate: error_rate
          },
          %{
            circuit_name: circuit_name,
            adaptation_reason: get_adaptation_reason(error_rate)
          }
        )

        Logger.info(
          "Adapted threshold for circuit #{circuit_name}: #{current_threshold} -> #{new_threshold} (error rate: #{Float.round(error_rate * 100, 2)}%)"
        )

        {:updated, new_threshold}
      else
        {:unchanged, current_threshold}
      end
    else
      {:skipped, :insufficient_calls}
    end
  end

  defp calculate_new_threshold(error_rate, current_threshold, config) do
    cond do
      # High error rate - decrease threshold for faster fault detection
      error_rate > 0.3 ->
        new_threshold = round(current_threshold * (1 - config.adaptation_factor))
        max(new_threshold, config.min_threshold)

      # Moderate error rate - maintain current threshold  
      error_rate > 0.1 ->
        current_threshold

      # Low error rate - increase threshold for more tolerance
      error_rate > 0.02 ->
        new_threshold = round(current_threshold * (1 + config.adaptation_factor))
        min(new_threshold, config.max_threshold)

      # Very low error rate - significantly increase threshold
      true ->
        new_threshold = round(current_threshold * (1 + config.adaptation_factor * 2))
        min(new_threshold, config.max_threshold)
    end
  end

  defp get_adaptation_reason(error_rate) do
    cond do
      error_rate > 0.3 -> :high_error_rate
      error_rate > 0.1 -> :moderate_error_rate
      error_rate > 0.02 -> :low_error_rate
      true -> :very_low_error_rate
    end
  end

  defp store_adaptive_metrics(circuit_name, telemetry_metrics, new_threshold) do
    existing_metrics = get_circuit_metrics(circuit_name)

    updated_metrics = %{
      total_calls: telemetry_metrics.total_calls,
      error_count: round(telemetry_metrics.total_calls * telemetry_metrics.failure_rate),
      error_rate: telemetry_metrics.failure_rate,
      current_threshold: new_threshold,
      last_updated: System.system_time(:second),
      adaptation_history: [
        %{
          timestamp: System.system_time(:second),
          old_threshold: existing_metrics.current_threshold || get_default_threshold(),
          new_threshold: new_threshold,
          error_rate: telemetry_metrics.failure_rate,
          total_calls: telemetry_metrics.total_calls
        }
        # Keep last 10 adaptations
        | Enum.take(existing_metrics.adaptation_history || [], 9)
      ]
    }

    :ets.insert(@table_name, {circuit_name, updated_metrics})
  end

  defp get_default_threshold do
    Application.get_env(:ex_llm, :circuit_breaker, %{})
    |> Map.get(:failure_threshold, 5)
  end
end
