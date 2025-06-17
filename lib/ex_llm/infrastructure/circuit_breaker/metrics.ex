defmodule ExLLM.Infrastructure.CircuitBreaker.Metrics do
  @moduledoc """
  Comprehensive metrics integration for circuit breakers.

  Provides metrics collection and export for Prometheus and StatsD, enabling
  detailed monitoring and observability of circuit breaker performance.

  ## Supported Metrics Backends

  - **Prometheus**: Via `:prometheus_ex` and `:prometheus_plugs`
  - **StatsD**: Via `:statsd` client
  - **Custom**: Pluggable metrics backend interface

  ## Metrics Collected

  ### Circuit Breaker Metrics
  - **State Duration**: Time spent in each state (closed/open/half_open)
  - **Request Counts**: Total requests, successes, failures by circuit
  - **Failure Rates**: Percentage of failed requests over time windows
  - **Recovery Times**: Time circuits spend in open state
  - **Transition Counts**: State change frequencies

  ### Bulkhead Metrics  
  - **Concurrency**: Active request counts and utilization
  - **Queue Metrics**: Queue length, wait times, timeouts
  - **Throughput**: Requests per second, completion rates
  - **Rejection Rates**: Percentage of rejected requests

  ### Performance Metrics
  - **Response Times**: Request duration histograms
  - **Error Rates**: Error classification and frequencies
  - **Circuit Health**: Overall health scores and status

  ## Configuration

      config :ex_llm, :circuit_breaker_metrics,
        enabled: true,
        backends: [:prometheus, :statsd],
        prometheus: [
          registry: :default,
          namespace: "ex_llm_circuit_breaker"
        ],
        statsd: [
          host: "localhost",
          port: 8125,
          namespace: "ex_llm.circuit_breaker"
        ]

  ## Usage

      # Start metrics collection
      ExLLM.Infrastructure.CircuitBreaker.Metrics.setup()
      
      # Manual metric recording
      ExLLM.Infrastructure.CircuitBreaker.Metrics.record_request("api_service", :success, 150)
      ExLLM.Infrastructure.CircuitBreaker.Metrics.record_state_change("api_service", :closed, :open)
      
      # Get current metrics
      ExLLM.Infrastructure.CircuitBreaker.Metrics.get_metrics("api_service")
  """

  require Logger

  # Check if optional dependencies are available at compile time
  @prometheus_available Code.ensure_loaded?(Prometheus)
  @statsd_available Code.ensure_loaded?(Statsd)

  # Metric names and labels
  @metric_names %{
    # Circuit breaker state metrics
    circuit_state: "circuit_breaker_state",
    state_duration: "circuit_breaker_state_duration_seconds",
    state_transitions: "circuit_breaker_state_transitions_total",

    # Request metrics
    requests_total: "circuit_breaker_requests_total",
    request_duration: "circuit_breaker_request_duration_seconds",
    failures_total: "circuit_breaker_failures_total",

    # Bulkhead metrics
    bulkhead_active: "circuit_breaker_bulkhead_active_requests",
    bulkhead_queued: "circuit_breaker_bulkhead_queued_requests",
    bulkhead_utilization: "circuit_breaker_bulkhead_utilization_ratio",
    bulkhead_rejections: "circuit_breaker_bulkhead_rejections_total",

    # Health metrics
    health_score: "circuit_breaker_health_score",
    health_level: "circuit_breaker_health_level"
  }

  @state_labels [:closed, :open, :half_open]
  @result_labels [:success, :failure, :timeout, :rejected]

  ## Public API

  @doc """
  Initialize metrics collection system.
  """
  def setup do
    if metrics_enabled?() do
      Logger.info("Initializing circuit breaker metrics collection")

      backends = get_enabled_backends()

      Enum.each(backends, fn backend ->
        # Note: When neither Prometheus nor StatsD are available, setup_backend
        # will always return {:error, _}. We use dynamic dispatch to avoid
        # compile-time warnings.
        setup_result = setup_backend(backend)

        # Log the result appropriately
        log_setup_result(backend, setup_result)
      end)

      # Attach telemetry handlers
      attach_telemetry_handlers()

      Logger.info("Circuit breaker metrics collection initialized")
    else
      Logger.debug("Circuit breaker metrics collection disabled")
    end
  end

  @doc """
  Record a circuit breaker request with timing and result.
  """
  def record_request(circuit_name, result, duration_ms) when result in @result_labels do
    if metrics_enabled?() do
      labels = %{circuit: circuit_name, result: Atom.to_string(result)}

      # Record request count
      emit_counter(@metric_names.requests_total, 1, labels)

      # Record request duration
      emit_histogram(@metric_names.request_duration, duration_ms / 1000, labels)

      # Record failures separately
      if result in [:failure, :timeout] do
        emit_counter(@metric_names.failures_total, 1, labels)
      end
    end

    :ok
  end

  @doc """
  Record a circuit breaker state change.
  """
  def record_state_change(circuit_name, from_state, to_state)
      when from_state in @state_labels and to_state in @state_labels do
    if metrics_enabled?() do
      labels = %{
        circuit: circuit_name,
        from_state: Atom.to_string(from_state),
        to_state: Atom.to_string(to_state)
      }

      emit_counter(@metric_names.state_transitions, 1, labels)

      # Update current state gauge
      state_labels = %{circuit: circuit_name}

      # Set all states to 0, then the current state to 1
      Enum.each(@state_labels, fn state ->
        value = if state == to_state, do: 1, else: 0
        state_specific_labels = Map.put(state_labels, :state, Atom.to_string(state))
        emit_gauge(@metric_names.circuit_state, value, state_specific_labels)
      end)
    end

    :ok
  end

  @doc """
  Record circuit state duration.
  """
  def record_state_duration(circuit_name, state, duration_ms) when state in @state_labels do
    if metrics_enabled?() do
      labels = %{circuit: circuit_name, state: Atom.to_string(state)}
      emit_histogram(@metric_names.state_duration, duration_ms / 1000, labels)
    end

    :ok
  end

  @doc """
  Record bulkhead metrics.
  """
  def record_bulkhead_metrics(circuit_name, metrics) do
    if metrics_enabled?() do
      labels = %{circuit: circuit_name}

      # Active requests
      emit_gauge(@metric_names.bulkhead_active, metrics.active_count, labels)

      # Queued requests
      emit_gauge(@metric_names.bulkhead_queued, metrics.queued_count, labels)

      # Utilization ratio
      utilization = calculate_utilization_ratio(metrics)
      emit_gauge(@metric_names.bulkhead_utilization, utilization, labels)

      # Record rejections if available
      if Map.has_key?(metrics, :total_rejected) do
        emit_counter(@metric_names.bulkhead_rejections, metrics.total_rejected, labels)
      end
    end

    :ok
  end

  @doc """
  Record circuit health metrics.
  """
  def record_health_metrics(circuit_name, health) do
    if metrics_enabled?() do
      labels = %{circuit: circuit_name}

      # Health score (0-100)
      emit_gauge(@metric_names.health_score, health.health_score, labels)

      # Health level as gauge (excellent=5, good=4, fair=3, poor=2, critical=1)
      level_value = health_level_to_value(health.health_level)
      health_labels = Map.put(labels, :level, Atom.to_string(health.health_level))
      emit_gauge(@metric_names.health_level, level_value, health_labels)
    end

    :ok
  end

  @doc """
  Get current metrics for a circuit.
  """
  def get_metrics(circuit_name) do
    if metrics_enabled?() do
      backends = get_enabled_backends()

      metrics = %{
        circuit_name: circuit_name,
        collected_at: DateTime.utc_now(),
        backends: backends
      }

      # Add backend-specific metrics
      backend_metrics =
        Enum.reduce(backends, %{}, fn backend, acc ->
          case get_backend_metrics(backend, circuit_name) do
            {:ok, data} -> Map.put(acc, backend, data)
            {:error, _} -> acc
          end
        end)

      Map.put(metrics, :backend_data, backend_metrics)
    else
      {:error, :metrics_disabled}
    end
  end

  @doc """
  Get system-wide metrics summary.
  """
  def get_system_metrics do
    if metrics_enabled?() do
      circuits = get_all_circuits()

      system_metrics = %{
        total_circuits: length(circuits),
        active_circuits: count_active_circuits(circuits),
        collected_at: DateTime.utc_now(),
        circuit_summaries:
          Enum.map(circuits, fn circuit ->
            case get_metrics(circuit) do
              {:error, _} -> %{circuit: circuit, status: :error}
              metrics -> %{circuit: circuit, status: :ok, metrics: metrics}
            end
          end)
      }

      {:ok, system_metrics}
    else
      {:error, :metrics_disabled}
    end
  end

  @doc """
  Export metrics in Prometheus format.
  """
  if @prometheus_available do
    def export_prometheus do
      if :prometheus_ex in get_enabled_backends() do
        try do
          case Code.ensure_loaded(Prometheus.Format.Text) do
            {:module, _} ->
              {:ok, Prometheus.Format.Text.format()}

            {:error, _} ->
              {:error, :prometheus_not_available}
          end
        rescue
          error -> {:error, {:prometheus_export_failed, error}}
        end
      else
        {:error, :prometheus_not_enabled}
      end
    end
  else
    def export_prometheus do
      {:error, :prometheus_not_available}
    end
  end

  ## Private Implementation

  defp metrics_enabled? do
    Application.get_env(:ex_llm, :circuit_breaker_metrics, [])
    |> Keyword.get(:enabled, false)
  end

  defp get_enabled_backends do
    Application.get_env(:ex_llm, :circuit_breaker_metrics, [])
    |> Keyword.get(:backends, [])
  end

  # When either Prometheus or StatsD is available, handle success case
  if @prometheus_available or @statsd_available do
    defp log_setup_result(backend, :ok) do
      Logger.info("Successfully initialized #{backend} metrics backend")
    end

    defp log_setup_result(backend, {:error, reason}) do
      Logger.warning("Failed to initialize #{backend} metrics backend: #{inspect(reason)}")
    end

    defp log_setup_result(backend, other) do
      Logger.warning("Unexpected setup result for #{backend}: #{inspect(other)}")
    end
  else
    # When no metrics backends are available, only handle error case
    defp log_setup_result(backend, {:error, reason}) do
      Logger.warning("Failed to initialize #{backend} metrics backend: #{inspect(reason)}")
    end

    defp log_setup_result(backend, other) do
      Logger.warning("Unexpected setup result for #{backend}: #{inspect(other)}")
    end
  end

  defp setup_backend(backend) do
    case backend do
      :prometheus ->
        if Code.ensure_loaded?(Prometheus) do
          setup_prometheus_metrics()
        else
          {:error, :prometheus_not_available}
        end

      :statsd ->
        if Code.ensure_loaded?(Statsd) do
          setup_statsd_client()
        else
          {:error, :statsd_not_available}
        end

      _ ->
        Logger.warning("Unknown metrics backend: #{backend}")
        {:error, :unknown_backend}
    end
  end

  if @prometheus_available do
    defp setup_prometheus_metrics do
      try do
        namespace = get_prometheus_namespace()

        # Define counters
        Prometheus.Counter.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.requests_total}"),
          help: "Total number of circuit breaker requests",
          labels: [:circuit, :result]
        )

        Prometheus.Counter.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.failures_total}"),
          help: "Total number of circuit breaker failures",
          labels: [:circuit, :result]
        )

        Prometheus.Counter.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.state_transitions}"),
          help: "Total number of circuit breaker state transitions",
          labels: [:circuit, :from_state, :to_state]
        )

        Prometheus.Counter.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.bulkhead_rejections}"),
          help: "Total number of bulkhead rejections",
          labels: [:circuit]
        )

        # Define gauges
        Prometheus.Gauge.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.circuit_state}"),
          help: "Current circuit breaker state (1=active, 0=inactive)",
          labels: [:circuit, :state]
        )

        Prometheus.Gauge.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.bulkhead_active}"),
          help: "Number of active requests in bulkhead",
          labels: [:circuit]
        )

        Prometheus.Gauge.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.bulkhead_queued}"),
          help: "Number of queued requests in bulkhead",
          labels: [:circuit]
        )

        Prometheus.Gauge.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.bulkhead_utilization}"),
          help: "Bulkhead utilization ratio (0-1)",
          labels: [:circuit]
        )

        Prometheus.Gauge.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.health_score}"),
          help: "Circuit breaker health score (0-100)",
          labels: [:circuit]
        )

        Prometheus.Gauge.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.health_level}"),
          help: "Circuit breaker health level (5=excellent, 1=critical)",
          labels: [:circuit, :level]
        )

        # Define histograms
        Prometheus.Histogram.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.request_duration}"),
          help: "Circuit breaker request duration in seconds",
          labels: [:circuit, :result],
          buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
        )

        Prometheus.Histogram.declare(
          name: String.to_atom("#{namespace}_#{@metric_names.state_duration}"),
          help: "Time spent in circuit breaker states in seconds",
          labels: [:circuit, :state],
          buckets: [1, 5, 10, 30, 60, 300, 600, 1800, 3600]
        )

        :ok
      rescue
        error -> {:error, {:prometheus_setup_failed, error}}
      end
    end
  else
    defp setup_prometheus_metrics do
      {:error, :prometheus_not_available}
    end
  end

  if @statsd_available do
    defp setup_statsd_client do
      try do
        config = get_statsd_config()

        # Start StatsD client if not already started
        case Statsd.start_link(config) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, _reason} = error -> error
          other -> {:error, {:unexpected_result, other}}
        end
      rescue
        error -> {:error, {:statsd_setup_failed, error}}
      end
    end
  else
    defp setup_statsd_client do
      {:error, :statsd_not_available}
    end
  end

  defp attach_telemetry_handlers do
    events = [
      [:ex_llm, :circuit_breaker, :call_success],
      [:ex_llm, :circuit_breaker, :call_failure],
      [:ex_llm, :circuit_breaker, :call_timeout],
      [:ex_llm, :circuit_breaker, :state_change],
      [:ex_llm, :circuit_breaker, :bulkhead, :metrics_updated],
      [:ex_llm, :circuit_breaker, :health_check, :completed]
    ]

    :telemetry.attach_many(
      "circuit_breaker_metrics_handler",
      events,
      &handle_telemetry_event/4,
      %{}
    )
  end

  defp handle_telemetry_event(
         [:ex_llm, :circuit_breaker, :call_success],
         measurements,
         metadata,
         _config
       ) do
    circuit_name = metadata.circuit_name
    duration = measurements[:duration] || 0
    record_request(circuit_name, :success, duration)
  end

  defp handle_telemetry_event(
         [:ex_llm, :circuit_breaker, :call_failure],
         measurements,
         metadata,
         _config
       ) do
    circuit_name = metadata.circuit_name
    duration = measurements[:duration] || 0
    record_request(circuit_name, :failure, duration)
  end

  defp handle_telemetry_event(
         [:ex_llm, :circuit_breaker, :call_timeout],
         measurements,
         metadata,
         _config
       ) do
    circuit_name = metadata.circuit_name
    timeout = measurements[:timeout] || 0
    record_request(circuit_name, :timeout, timeout)
  end

  defp handle_telemetry_event(
         [:ex_llm, :circuit_breaker, :state_change],
         _measurements,
         metadata,
         _config
       ) do
    circuit_name = metadata.circuit_name
    old_state = metadata.old_state
    new_state = metadata.new_state
    record_state_change(circuit_name, old_state, new_state)
  end

  defp handle_telemetry_event(
         [:ex_llm, :circuit_breaker, :bulkhead, :metrics_updated],
         _measurements,
         metadata,
         _config
       ) do
    circuit_name = metadata.circuit_name
    metrics = metadata.metrics
    record_bulkhead_metrics(circuit_name, metrics)
  end

  defp handle_telemetry_event(
         [:ex_llm, :circuit_breaker, :health_check, :completed],
         _measurements,
         metadata,
         _config
       ) do
    circuit_name = metadata.circuit_name
    health = metadata.health
    record_health_metrics(circuit_name, health)
  end

  defp handle_telemetry_event(_event, _measurements, _metadata, _config) do
    # Ignore unknown events
    :ok
  end

  defp emit_counter(metric_name, value, labels) do
    backends = get_enabled_backends()

    if :prometheus in backends do
      emit_prometheus_counter(metric_name, value, labels)
    end

    if :statsd in backends do
      emit_statsd_counter(metric_name, value, labels)
    end
  end

  defp emit_gauge(metric_name, value, labels) do
    backends = get_enabled_backends()

    if :prometheus in backends do
      emit_prometheus_gauge(metric_name, value, labels)
    end

    if :statsd in backends do
      emit_statsd_gauge(metric_name, value, labels)
    end
  end

  defp emit_histogram(metric_name, value, labels) do
    backends = get_enabled_backends()

    if :prometheus in backends do
      emit_prometheus_histogram(metric_name, value, labels)
    end

    if :statsd in backends do
      # Convert to ms for StatsD
      emit_statsd_timing(metric_name, value * 1000, labels)
    end
  end

  if @prometheus_available do
    defp emit_prometheus_counter(metric_name, value, labels) do
      try do
        namespace = get_prometheus_namespace()
        full_name = String.to_atom("#{namespace}_#{metric_name}")
        label_values = Map.values(labels)

        Prometheus.Counter.inc([name: full_name, labels: label_values], value)
      rescue
        error ->
          Logger.warning("Failed to emit Prometheus counter: #{inspect(error)}")
      end
    end

    defp emit_prometheus_gauge(metric_name, value, labels) do
      try do
        namespace = get_prometheus_namespace()
        full_name = String.to_atom("#{namespace}_#{metric_name}")
        label_values = Map.values(labels)

        Prometheus.Gauge.set([name: full_name, labels: label_values], value)
      rescue
        error ->
          Logger.warning("Failed to emit Prometheus gauge: #{inspect(error)}")
      end
    end

    defp emit_prometheus_histogram(metric_name, value, labels) do
      try do
        namespace = get_prometheus_namespace()
        full_name = String.to_atom("#{namespace}_#{metric_name}")
        label_values = Map.values(labels)

        Prometheus.Histogram.observe([name: full_name, labels: label_values], value)
      rescue
        error ->
          Logger.warning("Failed to emit Prometheus histogram: #{inspect(error)}")
      end
    end
  else
    defp emit_prometheus_counter(_metric_name, _value, _labels) do
      Logger.debug("Prometheus counter emit skipped - Prometheus not available")
    end

    defp emit_prometheus_gauge(_metric_name, _value, _labels) do
      Logger.debug("Prometheus gauge emit skipped - Prometheus not available")
    end

    defp emit_prometheus_histogram(_metric_name, _value, _labels) do
      Logger.debug("Prometheus histogram emit skipped - Prometheus not available")
    end
  end

  if @statsd_available do
    defp emit_statsd_counter(metric_name, value, labels) do
      try do
        metric_key = build_statsd_key(metric_name, labels)
        Statsd.increment(metric_key, value)
      rescue
        error ->
          Logger.warning("Failed to emit StatsD counter: #{inspect(error)}")
      end
    end

    defp emit_statsd_gauge(metric_name, value, labels) do
      try do
        metric_key = build_statsd_key(metric_name, labels)
        Statsd.gauge(metric_key, value)
      rescue
        error ->
          Logger.warning("Failed to emit StatsD gauge: #{inspect(error)}")
      end
    end

    defp emit_statsd_timing(metric_name, value_ms, labels) do
      try do
        metric_key = build_statsd_key(metric_name, labels)
        Statsd.timing(metric_key, round(value_ms))
      rescue
        error ->
          Logger.warning("Failed to emit StatsD timing: #{inspect(error)}")
      end
    end
  else
    defp emit_statsd_counter(_metric_name, _value, _labels) do
      Logger.debug("StatsD counter emit skipped - StatsD not available")
    end

    defp emit_statsd_gauge(_metric_name, _value, _labels) do
      Logger.debug("StatsD gauge emit skipped - StatsD not available")
    end

    defp emit_statsd_timing(_metric_name, _value_ms, _labels) do
      Logger.debug("StatsD timing emit skipped - StatsD not available")
    end
  end

  # Configuration helper functions - conditionally compiled

  if @prometheus_available do
    defp get_prometheus_namespace do
      Application.get_env(:ex_llm, :circuit_breaker_metrics, [])
      |> get_in([:prometheus, :namespace]) ||
        "ex_llm_circuit_breaker"
    end
  end

  if @statsd_available do
    defp build_statsd_key(metric_name, labels) do
      namespace = get_statsd_namespace()

      label_string =
        labels
        |> Enum.map(fn {k, v} -> "#{k}:#{v}" end)
        |> Enum.join(",")

      if label_string != "" do
        "#{namespace}.#{metric_name}.#{label_string}"
      else
        "#{namespace}.#{metric_name}"
      end
    end

    defp get_statsd_namespace do
      Application.get_env(:ex_llm, :circuit_breaker_metrics, [])
      |> get_in([:statsd, :namespace]) ||
        "ex_llm.circuit_breaker"
    end

    defp get_statsd_config do
      config =
        Application.get_env(:ex_llm, :circuit_breaker_metrics, [])
        |> Keyword.get(:statsd, [])

      [
        host: Keyword.get(config, :host, "localhost"),
        port: Keyword.get(config, :port, 8125)
      ]
    end
  end

  defp calculate_utilization_ratio(%{active_count: active, config: %{max_concurrent: max}})
       when max > 0 do
    active / max
  end

  defp calculate_utilization_ratio(_), do: 0.0

  defp health_level_to_value(:excellent), do: 5
  defp health_level_to_value(:good), do: 4
  defp health_level_to_value(:fair), do: 3
  defp health_level_to_value(:poor), do: 2
  defp health_level_to_value(:critical), do: 1
  defp health_level_to_value(_), do: 0

  defp get_backend_metrics(:prometheus, circuit_name) do
    try do
      # This would typically query Prometheus metrics
      # For now, return placeholder data
      {:ok,
       %{
         type: :prometheus,
         circuit: circuit_name,
         note: "Prometheus metrics backend active"
       }}
    rescue
      error -> {:error, {:prometheus_query_failed, error}}
    end
  end

  defp get_backend_metrics(:statsd, circuit_name) do
    try do
      # StatsD typically doesn't support querying, just sending
      {:ok,
       %{
         type: :statsd,
         circuit: circuit_name,
         note: "StatsD metrics backend active"
       }}
    rescue
      error -> {:error, {:statsd_query_failed, error}}
    end
  end

  defp get_backend_metrics(backend, _circuit_name) do
    {:error, {:unknown_backend, backend}}
  end

  defp get_all_circuits do
    try do
      :ets.tab2list(:ex_llm_circuit_breakers)
      |> Enum.map(fn {name, _state} -> name end)
    rescue
      _ -> []
    end
  end

  defp count_active_circuits(circuits) do
    circuits
    |> Enum.count(fn circuit_name ->
      case ExLLM.Infrastructure.CircuitBreaker.get_stats(circuit_name) do
        {:ok, %{state: state}} when state in [:closed, :half_open] -> true
        _ -> false
      end
    end)
  end
end
