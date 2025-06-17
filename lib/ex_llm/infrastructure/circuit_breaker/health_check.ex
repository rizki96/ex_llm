defmodule ExLLM.Infrastructure.CircuitBreaker.HealthCheck do
  @moduledoc """
  Health check and monitoring system for circuit breakers.

  Provides comprehensive health assessment for both individual circuits and the overall
  circuit breaker system. Includes health scoring, issue detection, and recommendations
  for maintaining optimal fault tolerance.

  ## Health Scoring

  Health scores range from 0-100:
  - **90-100**: Excellent - Circuit is performing optimally
  - **70-89**: Good - Circuit is stable with minor concerns
  - **50-69**: Fair - Circuit has issues that should be monitored
  - **30-49**: Poor - Circuit requires attention
  - **0-29**: Critical - Circuit needs immediate intervention

  ## Health Factors

  - **State**: Circuit breaker state (closed/open/half-open)
  - **Failure Rate**: Recent failure percentage
  - **Recovery Time**: Time circuits spend in open state
  - **Frequency**: How often circuits are being triggered
  - **Bulkhead Utilization**: Concurrency and queue usage
  - **Configuration**: Threshold appropriateness

  ## Usage

      # Check overall system health
      ExLLM.Infrastructure.CircuitBreaker.HealthCheck.system_health()
      
      # Check specific circuit health
      ExLLM.Infrastructure.CircuitBreaker.HealthCheck.circuit_health("api_service")
      
      # Get health summary for all circuits
      ExLLM.Infrastructure.CircuitBreaker.HealthCheck.health_summary()
      
      # Get detailed health report
      ExLLM.Infrastructure.CircuitBreaker.HealthCheck.health_report()
  """

  require Logger

  alias ExLLM.Infrastructure.CircuitBreaker

  # Health score thresholds
  @excellent_threshold 90
  @good_threshold 70
  @fair_threshold 50
  @poor_threshold 30

  # Health check configuration
  # 5 minutes in milliseconds
  @default_time_window 300_000
  # 50% failure rate is critical
  @critical_failure_rate 0.5
  # 20% failure rate is concerning
  @warning_failure_rate 0.2
  # 1 minute in open state
  @max_acceptable_open_time 60_000

  @type health_level :: :excellent | :good | :fair | :poor | :critical
  @type health_score :: 0..100

  @type circuit_health :: %{
          circuit_name: String.t(),
          health_score: health_score(),
          health_level: health_level(),
          state: :closed | :open | :half_open,
          issues: [String.t()],
          recommendations: [String.t()],
          metrics: map(),
          last_updated: DateTime.t()
        }

  @type system_health :: %{
          overall_score: health_score(),
          overall_level: health_level(),
          total_circuits: non_neg_integer(),
          healthy_circuits: non_neg_integer(),
          unhealthy_circuits: non_neg_integer(),
          critical_circuits: non_neg_integer(),
          issues: [String.t()],
          recommendations: [String.t()],
          last_updated: DateTime.t()
        }

  ## Public API

  @doc """
  Get comprehensive health status for the entire circuit breaker system.
  """
  @spec system_health(keyword()) :: {:ok, system_health()} | {:error, term()}
  def system_health(opts \\ []) do
    try do
      time_window = Keyword.get(opts, :time_window, @default_time_window)

      circuits = get_all_circuits()

      circuit_healths =
        Enum.map(circuits, fn {name, _state} ->
          case circuit_health(name, time_window: time_window) do
            {:ok, health} -> health
            {:error, _} -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {overall_score, overall_level} = calculate_system_health_score(circuit_healths)

      health_summary = %{
        overall_score: overall_score,
        overall_level: overall_level,
        total_circuits: length(circuit_healths),
        healthy_circuits: count_circuits_by_level(circuit_healths, [:excellent, :good]),
        unhealthy_circuits: count_circuits_by_level(circuit_healths, [:fair, :poor]),
        critical_circuits: count_circuits_by_level(circuit_healths, [:critical]),
        issues: detect_system_issues(circuit_healths),
        recommendations: generate_system_recommendations(circuit_healths),
        last_updated: DateTime.utc_now()
      }

      {:ok, health_summary}
    rescue
      error -> {:error, {:health_check_failed, error}}
    end
  end

  @doc """
  Get detailed health status for a specific circuit.
  """
  @spec circuit_health(String.t(), keyword()) :: {:ok, circuit_health()} | {:error, term()}
  def circuit_health(circuit_name, opts \\ []) do
    time_window = Keyword.get(opts, :time_window, @default_time_window)

    with {:ok, circuit_stats} <- CircuitBreaker.get_stats(circuit_name),
         {:ok, telemetry_metrics} <- get_telemetry_metrics(circuit_name, time_window),
         {:ok, bulkhead_metrics} <- get_bulkhead_metrics(circuit_name) do
      health_score =
        calculate_circuit_health_score(circuit_stats, telemetry_metrics, bulkhead_metrics)

      health_level = score_to_level(health_score)
      issues = detect_circuit_issues(circuit_stats, telemetry_metrics, bulkhead_metrics)

      recommendations =
        generate_circuit_recommendations(
          circuit_stats,
          telemetry_metrics,
          bulkhead_metrics,
          issues
        )

      health_data = %{
        circuit_name: circuit_name,
        health_score: health_score,
        health_level: health_level,
        state: circuit_stats.state,
        issues: issues,
        recommendations: recommendations,
        metrics: %{
          circuit: circuit_stats,
          telemetry: telemetry_metrics,
          bulkhead: bulkhead_metrics
        },
        last_updated: DateTime.utc_now()
      }

      {:ok, health_data}
    else
      {:error, :circuit_not_found} ->
        {:error, :circuit_not_found}

      error ->
        {:error, {:health_check_failed, error}}
    end
  end

  @doc """
  Get a summary of health status for all circuits.
  """
  @spec health_summary(keyword()) :: {:ok, [map()]} | {:error, term()}
  def health_summary(opts \\ []) do
    time_window = Keyword.get(opts, :time_window, @default_time_window)

    circuits = get_all_circuits()

    summary =
      Enum.map(circuits, fn {name, _state} ->
        case circuit_health(name, time_window: time_window) do
          {:ok, health} ->
            %{
              circuit_name: health.circuit_name,
              health_score: health.health_score,
              health_level: health.health_level,
              state: health.state,
              issue_count: length(health.issues),
              recommendation_count: length(health.recommendations)
            }

          {:error, _} ->
            %{
              circuit_name: name,
              health_score: 0,
              health_level: :critical,
              state: :unknown,
              issue_count: 1,
              recommendation_count: 1
            }
        end
      end)

    {:ok, summary}
  end

  @doc """
  Get a detailed health report for dashboard/monitoring systems.
  """
  @spec health_report(keyword()) :: {:ok, map()} | {:error, term()}
  def health_report(opts \\ []) do
    with {:ok, system_health} <- system_health(opts),
         {:ok, circuit_summaries} <- health_summary(opts) do
      report = %{
        system: system_health,
        circuits: circuit_summaries,
        trends: calculate_health_trends(opts),
        alerts: generate_health_alerts(system_health, circuit_summaries),
        report_generated_at: DateTime.utc_now()
      }

      {:ok, report}
    end
  end

  @doc """
  Check if the circuit breaker system is healthy overall.
  """
  @spec healthy?(keyword()) :: boolean()
  def healthy?(opts \\ []) do
    case system_health(opts) do
      {:ok, %{overall_level: level}} when level in [:excellent, :good] -> true
      _ -> false
    end
  end

  @doc """
  Get circuits that need immediate attention.
  """
  @spec critical_circuits(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def critical_circuits(opts \\ []) do
    case health_summary(opts) do
      {:ok, summaries} ->
        critical =
          summaries
          |> Enum.filter(fn %{health_level: level} -> level == :critical end)
          |> Enum.map(fn %{circuit_name: name} -> name end)

        {:ok, critical}

      error ->
        error
    end
  end

  ## Private Implementation

  defp get_all_circuits do
    :ets.tab2list(:ex_llm_circuit_breakers)
  end

  defp get_circuit_state(circuit_name) do
    case :ets.lookup(:ex_llm_circuit_breakers, circuit_name) do
      [{^circuit_name, circuit_state}] -> circuit_state.state
      [] -> :unknown
    end
  end

  defp get_telemetry_metrics(circuit_name, time_window) do
    try do
      metrics = ExLLM.Infrastructure.CircuitBreaker.Telemetry.get_metrics(circuit_name)

      # Calculate time-windowed metrics
      windowed_metrics = %{
        total_calls: metrics.total_calls,
        failure_rate: metrics.failure_rate,
        average_response_time: metrics.average_response_time,
        success_rate: 1.0 - metrics.failure_rate,
        calls_per_minute: calculate_calls_per_minute(metrics, time_window)
      }

      {:ok, windowed_metrics}
    rescue
      _error ->
        # When telemetry data is unavailable, determine default metrics based on circuit state
        # This provides safer defaults for monitoring systems
        default_failure_rate =
          case get_circuit_state(circuit_name) do
            # Open circuits should be treated as failing
            :open -> 1.0
            # Half-open circuits are uncertain
            :half_open -> 0.5
            # Closed circuits are likely healthy
            :closed -> 0.0
            # Unknown state should be treated as critical
            _ -> 1.0
          end

        {:ok,
         %{
           total_calls: 0,
           failure_rate: default_failure_rate,
           average_response_time: 0,
           success_rate: 1.0 - default_failure_rate,
           calls_per_minute: 0
         }}
    end
  end

  defp get_bulkhead_metrics(circuit_name) do
    try do
      # Check if bulkhead system is initialized first
      if Process.whereis(ExLLM.Infrastructure.CircuitBreaker.Bulkhead.Registry) do
        metrics = ExLLM.Infrastructure.CircuitBreaker.Bulkhead.get_metrics(circuit_name)

        enhanced_metrics = %{
          active_count: metrics.active_count,
          queued_count: metrics.queued_count,
          total_accepted: metrics.total_accepted,
          total_rejected: metrics.total_rejected,
          utilization_ratio: calculate_utilization_ratio(metrics),
          queue_utilization: calculate_queue_utilization(metrics)
        }

        {:ok, enhanced_metrics}
      else
        {:ok,
         %{
           active_count: 0,
           queued_count: 0,
           total_accepted: 0,
           total_rejected: 0,
           utilization_ratio: 0.0,
           queue_utilization: 0.0
         }}
      end
    rescue
      _error ->
        {:ok,
         %{
           active_count: 0,
           queued_count: 0,
           total_accepted: 0,
           total_rejected: 0,
           utilization_ratio: 0.0,
           queue_utilization: 0.0
         }}
    end
  end

  defp calculate_circuit_health_score(circuit_stats, telemetry_metrics, bulkhead_metrics) do
    state_score = calculate_state_score(circuit_stats.state)
    failure_score = calculate_failure_score(telemetry_metrics.failure_rate)
    recovery_score = calculate_recovery_score(circuit_stats)
    utilization_score = calculate_utilization_score(bulkhead_metrics)

    # Weighted average of different health factors - state is most important
    weights = %{state: 0.5, failure: 0.3, recovery: 0.1, utilization: 0.1}

    round(
      state_score * weights.state +
        failure_score * weights.failure +
        recovery_score * weights.recovery +
        utilization_score * weights.utilization
    )
  end

  defp calculate_state_score(:closed), do: 100
  defp calculate_state_score(:half_open), do: 50
  defp calculate_state_score(:open), do: 0

  defp calculate_failure_score(failure_rate) when failure_rate <= 0.01, do: 100
  defp calculate_failure_score(failure_rate) when failure_rate <= 0.05, do: 90
  defp calculate_failure_score(failure_rate) when failure_rate <= 0.10, do: 80
  defp calculate_failure_score(failure_rate) when failure_rate <= 0.20, do: 60
  defp calculate_failure_score(failure_rate) when failure_rate <= 0.50, do: 30
  defp calculate_failure_score(_failure_rate), do: 0

  defp calculate_recovery_score(%{state: :open, last_failure_time: nil}), do: 50

  defp calculate_recovery_score(%{state: :open, last_failure_time: last_failure}) do
    time_open = System.monotonic_time(:millisecond) - last_failure

    cond do
      time_open < @max_acceptable_open_time -> 80
      time_open < @max_acceptable_open_time * 2 -> 60
      time_open < @max_acceptable_open_time * 5 -> 40
      true -> 20
    end
  end

  defp calculate_recovery_score(_), do: 100

  defp calculate_utilization_score(%{utilization_ratio: ratio, queue_utilization: queue_ratio}) do
    utilization_score =
      cond do
        ratio <= 0.5 -> 100
        ratio <= 0.7 -> 90
        ratio <= 0.85 -> 80
        ratio <= 0.95 -> 60
        true -> 40
      end

    queue_score =
      cond do
        queue_ratio <= 0.3 -> 100
        queue_ratio <= 0.6 -> 80
        queue_ratio <= 0.8 -> 60
        true -> 30
      end

    # Average of utilization and queue scores
    div(utilization_score + queue_score, 2)
  end

  defp calculate_system_health_score([]),
    do: {100, :excellent}

  defp calculate_system_health_score(circuit_healths) do
    average_score =
      circuit_healths
      |> Enum.map(fn %{health_score: score} -> score end)
      |> Enum.sum()
      |> div(length(circuit_healths))

    # Penalize systems with critical circuits
    critical_count = count_circuits_by_level(circuit_healths, [:critical])
    penalty = min(critical_count * 10, 50)

    adjusted_score = max(0, average_score - penalty)
    {adjusted_score, score_to_level(adjusted_score)}
  end

  defp score_to_level(score) when score >= @excellent_threshold, do: :excellent
  defp score_to_level(score) when score >= @good_threshold, do: :good
  defp score_to_level(score) when score >= @fair_threshold, do: :fair
  defp score_to_level(score) when score >= @poor_threshold, do: :poor
  defp score_to_level(_score), do: :critical

  defp count_circuits_by_level(circuit_healths, target_levels) do
    circuit_healths
    |> Enum.count(fn %{health_level: level} -> level in target_levels end)
  end

  defp detect_circuit_issues(circuit_stats, telemetry_metrics, bulkhead_metrics) do
    issues = []

    issues =
      if circuit_stats.state == :open do
        ["Circuit is in OPEN state - blocking all requests" | issues]
      else
        issues
      end

    issues =
      if telemetry_metrics.failure_rate > @critical_failure_rate do
        ["High failure rate: #{Float.round(telemetry_metrics.failure_rate * 100, 1)}%" | issues]
      else
        issues
      end

    issues =
      if telemetry_metrics.failure_rate > @warning_failure_rate do
        [
          "Elevated failure rate: #{Float.round(telemetry_metrics.failure_rate * 100, 1)}%"
          | issues
        ]
      else
        issues
      end

    issues =
      if bulkhead_metrics.utilization_ratio > 0.9 do
        [
          "High bulkhead utilization: #{Float.round(bulkhead_metrics.utilization_ratio * 100, 1)}%"
          | issues
        ]
      else
        issues
      end

    issues =
      if bulkhead_metrics.queue_utilization > 0.8 do
        [
          "High queue utilization: #{Float.round(bulkhead_metrics.queue_utilization * 100, 1)}%"
          | issues
        ]
      else
        issues
      end

    issues =
      if circuit_stats.failure_count > circuit_stats.config.failure_threshold * 0.8 do
        [
          "Approaching failure threshold: #{circuit_stats.failure_count}/#{circuit_stats.config.failure_threshold}"
          | issues
        ]
      else
        issues
      end

    Enum.reverse(issues)
  end

  defp generate_circuit_recommendations(
         _circuit_stats,
         telemetry_metrics,
         bulkhead_metrics,
         issues
       ) do
    recommendations = []

    recommendations =
      if telemetry_metrics.failure_rate > @warning_failure_rate do
        ["Consider investigating root cause of failures" | recommendations]
      else
        recommendations
      end

    recommendations =
      if bulkhead_metrics.utilization_ratio > 0.8 do
        ["Consider increasing bulkhead concurrency limits" | recommendations]
      else
        recommendations
      end

    recommendations =
      if bulkhead_metrics.queue_utilization > 0.7 do
        ["Consider increasing bulkhead queue size or reducing queue timeout" | recommendations]
      else
        recommendations
      end

    recommendations =
      if length(issues) > 2 do
        ["Circuit requires immediate attention due to multiple issues" | recommendations]
      else
        recommendations
      end

    recommendations =
      if Enum.empty?(issues) do
        ["Circuit is operating normally" | recommendations]
      else
        recommendations
      end

    Enum.reverse(recommendations)
  end

  defp detect_system_issues(circuit_healths) do
    issues = []

    critical_count = count_circuits_by_level(circuit_healths, [:critical])

    issues =
      if critical_count > 0 do
        ["#{critical_count} circuit(s) in critical state" | issues]
      else
        issues
      end

    unhealthy_count = count_circuits_by_level(circuit_healths, [:poor, :critical])
    total_count = length(circuit_healths)
    unhealthy_ratio = if total_count > 0, do: unhealthy_count / total_count, else: 0

    issues =
      if unhealthy_ratio > 0.3 do
        [
          "High percentage of unhealthy circuits: #{Float.round(unhealthy_ratio * 100, 1)}%"
          | issues
        ]
      else
        issues
      end

    issues =
      if total_count == 0 do
        ["No active circuits found" | issues]
      else
        issues
      end

    Enum.reverse(issues)
  end

  defp generate_system_recommendations(circuit_healths) do
    recommendations = []

    critical_count = count_circuits_by_level(circuit_healths, [:critical])

    recommendations =
      if critical_count > 0 do
        ["Investigate and resolve critical circuit issues immediately" | recommendations]
      else
        recommendations
      end

    unhealthy_count = count_circuits_by_level(circuit_healths, [:poor, :critical])

    recommendations =
      if unhealthy_count > 0 do
        ["Review configuration and thresholds for unhealthy circuits" | recommendations]
      else
        recommendations
      end

    total_count = length(circuit_healths)
    healthy_count = count_circuits_by_level(circuit_healths, [:excellent, :good])

    recommendations =
      if total_count > 0 and healthy_count == total_count do
        ["System is operating optimally" | recommendations]
      else
        recommendations
      end

    recommendations =
      if total_count > 10 do
        ["Consider implementing circuit grouping for better management" | recommendations]
      else
        recommendations
      end

    Enum.reverse(recommendations)
  end

  defp calculate_calls_per_minute(metrics, time_window) do
    window_minutes = time_window / 60_000

    if window_minutes > 0 do
      Float.round(metrics.total_calls / window_minutes, 2)
    else
      0
    end
  end

  defp calculate_utilization_ratio(%{active_count: active, config: %{max_concurrent: max}})
       when max > 0 do
    Float.round(active / max, 3)
  end

  defp calculate_utilization_ratio(_), do: 0.0

  defp calculate_queue_utilization(%{queued_count: queued, config: %{max_queued: max}})
       when max > 0 do
    Float.round(queued / max, 3)
  end

  defp calculate_queue_utilization(_), do: 0.0

  defp calculate_health_trends(opts) do
    time_window = Keyword.get(opts, :time_window, @default_time_window)

    # For now, return placeholder trends
    # In a full implementation, this would analyze historical data
    %{
      trend_period: "#{div(time_window, 60_000)} minutes",
      overall_trend: :stable,
      circuits_improving: 0,
      circuits_degrading: 0,
      note: "Historical trend analysis requires time-series data storage"
    }
  end

  defp generate_health_alerts(system_health, circuit_summaries) do
    alerts = []

    alerts =
      if system_health.overall_level == :critical do
        [
          %{
            level: :critical,
            message: "System-wide circuit breaker health is critical",
            action_required: true,
            circuits_affected: :all
          }
          | alerts
        ]
      else
        alerts
      end

    critical_circuits =
      circuit_summaries
      |> Enum.filter(fn %{health_level: level} -> level == :critical end)
      |> Enum.map(fn %{circuit_name: name} -> name end)

    alerts =
      if length(critical_circuits) > 0 do
        [
          %{
            level: :critical,
            message: "#{length(critical_circuits)} circuit(s) require immediate attention",
            action_required: true,
            circuits_affected: critical_circuits
          }
          | alerts
        ]
      else
        alerts
      end

    poor_circuits =
      circuit_summaries
      |> Enum.filter(fn %{health_level: level} -> level == :poor end)
      |> Enum.map(fn %{circuit_name: name} -> name end)

    alerts =
      if length(poor_circuits) > 0 do
        [
          %{
            level: :warning,
            message: "#{length(poor_circuits)} circuit(s) showing poor health",
            action_required: false,
            circuits_affected: poor_circuits
          }
          | alerts
        ]
      else
        alerts
      end

    if Enum.empty?(alerts) do
      [
        %{
          level: :info,
          message: "All circuits are operating within acceptable parameters",
          action_required: false,
          circuits_affected: []
        }
      ]
    else
      Enum.reverse(alerts)
    end
  end
end
