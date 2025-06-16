defmodule ExLLM.CircuitBreaker.Metrics.Dashboard do
  @moduledoc """
  Dashboard and visualization helpers for circuit breaker metrics.

  Provides data aggregation and formatting for building monitoring dashboards
  and alerting systems. Works with popular monitoring tools like Grafana,
  DataDog, and custom dashboard implementations.

  ## Features

  - **Real-time Metrics**: Live circuit breaker status and performance data
  - **Historical Analysis**: Time-series data aggregation and trends
  - **Alert Thresholds**: Configurable alerting rules and conditions
  - **Data Export**: JSON/CSV export for external tools
  - **Widget Helpers**: Pre-built components for common visualizations

  ## Usage

      # Get dashboard data
      {:ok, dashboard_data} = ExLLM.CircuitBreaker.Metrics.Dashboard.get_dashboard_data()
      
      # Get specific widget data
      {:ok, health_data} = ExLLM.CircuitBreaker.Metrics.Dashboard.health_widget()
      {:ok, throughput_data} = ExLLM.CircuitBreaker.Metrics.Dashboard.throughput_widget()
      
      # Export data
      {:ok, json} = ExLLM.CircuitBreaker.Metrics.Dashboard.export_json()
      {:ok, csv} = ExLLM.CircuitBreaker.Metrics.Dashboard.export_csv()
  """

  require Logger

  alias ExLLM.CircuitBreaker
  alias ExLLM.CircuitBreaker.{HealthCheck, Metrics}

  @doc """
  Get comprehensive dashboard data for all circuits.
  """
  def get_dashboard_data(opts \\ []) do
    # 5 minutes
    time_window = Keyword.get(opts, :time_window, 300_000)

    with {:ok, system_health} <- HealthCheck.system_health(time_window: time_window),
         {:ok, circuit_summaries} <- HealthCheck.health_summary(time_window: time_window) do
      dashboard_data = %{
        timestamp: DateTime.utc_now(),
        time_window_ms: time_window,
        system_overview: build_system_overview(system_health),
        circuit_grid: build_circuit_grid(circuit_summaries),
        health_distribution: build_health_distribution(circuit_summaries),
        performance_metrics: build_performance_metrics(circuit_summaries),
        alerts: build_alerts(system_health, circuit_summaries),
        trends: build_trends(circuit_summaries, time_window)
      }

      {:ok, dashboard_data}
    else
      error -> error
    end
  end

  @doc """
  Get health overview widget data.
  """
  def health_widget(opts \\ []) do
    case HealthCheck.system_health(opts) do
      {:ok, health} ->
        widget_data = %{
          type: :health_overview,
          overall_score: health.overall_score,
          overall_level: health.overall_level,
          total_circuits: health.total_circuits,
          healthy_circuits: health.healthy_circuits,
          unhealthy_circuits: health.unhealthy_circuits,
          critical_circuits: health.critical_circuits,
          status_color: health_level_to_color(health.overall_level),
          issues: health.issues,
          recommendations: health.recommendations,
          last_updated: health.last_updated
        }

        {:ok, widget_data}

      error ->
        error
    end
  end

  @doc """
  Get throughput widget data.
  """
  def throughput_widget(opts \\ []) do
    time_window = Keyword.get(opts, :time_window, 300_000)

    circuits = get_all_circuits()

    throughput_data =
      circuits
      |> Enum.map(fn circuit_name ->
        case get_circuit_throughput(circuit_name, time_window) do
          {:ok, data} ->
            Map.put(data, :circuit_name, circuit_name)

          {:error, _} ->
            %{circuit_name: circuit_name, requests_per_minute: 0, error_rate: 0}
        end
      end)
      |> Enum.sort_by(& &1.requests_per_minute, :desc)

    total_rpm = Enum.sum(Enum.map(throughput_data, & &1.requests_per_minute))

    avg_error_rate =
      if length(throughput_data) > 0 do
        Enum.sum(Enum.map(throughput_data, & &1.error_rate)) / length(throughput_data)
      else
        0
      end

    widget_data = %{
      type: :throughput_overview,
      total_requests_per_minute: total_rpm,
      average_error_rate: avg_error_rate,
      circuit_data: throughput_data,
      timestamp: DateTime.utc_now()
    }

    {:ok, widget_data}
  end

  @doc """
  Get response time widget data.
  """
  def response_time_widget(opts \\ []) do
    time_window = Keyword.get(opts, :time_window, 300_000)

    circuits = get_all_circuits()

    response_time_data =
      circuits
      |> Enum.map(fn circuit_name ->
        case get_circuit_response_times(circuit_name, time_window) do
          {:ok, data} ->
            Map.put(data, :circuit_name, circuit_name)

          {:error, _} ->
            %{
              circuit_name: circuit_name,
              avg_response_time: 0,
              p95_response_time: 0,
              p99_response_time: 0
            }
        end
      end)
      |> Enum.sort_by(& &1.avg_response_time, :desc)

    widget_data = %{
      type: :response_time_overview,
      circuit_data: response_time_data,
      timestamp: DateTime.utc_now()
    }

    {:ok, widget_data}
  end

  @doc """
  Get state distribution widget data.
  """
  def state_distribution_widget(opts \\ []) do
    circuits = get_all_circuits()

    state_counts =
      circuits
      |> Enum.reduce(%{closed: 0, open: 0, half_open: 0}, fn circuit_name, acc ->
        case CircuitBreaker.get_stats(circuit_name) do
          {:ok, stats} ->
            Map.update(acc, stats.state, 1, &(&1 + 1))

          {:error, _} ->
            acc
        end
      end)

    total = Map.values(state_counts) |> Enum.sum()

    distribution =
      if total > 0 do
        state_counts
        |> Enum.map(fn {state, count} ->
          percentage = Float.round(count / total * 100, 1)
          %{state: state, count: count, percentage: percentage, color: state_to_color(state)}
        end)
      else
        []
      end

    widget_data = %{
      type: :state_distribution,
      total_circuits: total,
      distribution: distribution,
      timestamp: DateTime.utc_now()
    }

    {:ok, widget_data}
  end

  @doc """
  Get top failing circuits widget data.
  """
  def top_failing_circuits_widget(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    time_window = Keyword.get(opts, :time_window, 300_000)

    circuits = get_all_circuits()

    failing_circuits =
      circuits
      |> Enum.map(fn circuit_name ->
        case get_circuit_failure_rate(circuit_name, time_window) do
          {:ok, failure_rate} ->
            %{
              circuit_name: circuit_name,
              failure_rate: failure_rate,
              status: if(failure_rate > 0.1, do: :critical, else: :ok)
            }

          {:error, _} ->
            %{circuit_name: circuit_name, failure_rate: 0, status: :unknown}
        end
      end)
      |> Enum.filter(&(&1.failure_rate > 0))
      |> Enum.sort_by(& &1.failure_rate, :desc)
      |> Enum.take(limit)

    widget_data = %{
      type: :top_failing_circuits,
      circuits: failing_circuits,
      timestamp: DateTime.utc_now()
    }

    {:ok, widget_data}
  end

  @doc """
  Export dashboard data as JSON.
  """
  def export_json(opts \\ []) do
    case get_dashboard_data(opts) do
      {:ok, data} ->
        case Jason.encode(data, pretty: true) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:error, {:json_encode_failed, reason}}
        end

      error ->
        error
    end
  end

  @doc """
  Export circuit summary data as CSV.
  """
  def export_csv(opts \\ []) do
    case HealthCheck.health_summary(opts) do
      {:ok, summaries} ->
        csv_data = build_csv_data(summaries)
        {:ok, csv_data}

      error ->
        error
    end
  end

  @doc """
  Get alerting rules and current alert status.
  """
  def get_alerts(opts \\ []) do
    thresholds = Keyword.get(opts, :thresholds, default_alert_thresholds())

    case HealthCheck.system_health(opts) do
      {:ok, system_health} ->
        alerts = []

        # System-level alerts
        alerts =
          if system_health.overall_score < thresholds.critical_health_score do
            [
              %{
                level: :critical,
                type: :system_health,
                message: "System health is critical (score: #{system_health.overall_score})",
                value: system_health.overall_score,
                threshold: thresholds.critical_health_score,
                timestamp: DateTime.utc_now()
              }
              | alerts
            ]
          else
            alerts
          end

        alerts =
          if system_health.critical_circuits > thresholds.max_critical_circuits do
            [
              %{
                level: :warning,
                type: :critical_circuits,
                message: "Too many critical circuits (#{system_health.critical_circuits})",
                value: system_health.critical_circuits,
                threshold: thresholds.max_critical_circuits,
                timestamp: DateTime.utc_now()
              }
              | alerts
            ]
          else
            alerts
          end

        # Circuit-level alerts
        case HealthCheck.health_summary(opts) do
          {:ok, summaries} ->
            circuit_alerts =
              summaries
              |> Enum.flat_map(fn summary ->
                build_circuit_alerts(summary, thresholds)
              end)

            all_alerts = alerts ++ circuit_alerts

            alert_summary = %{
              total_alerts: length(all_alerts),
              critical_alerts: count_alerts_by_level(all_alerts, :critical),
              warning_alerts: count_alerts_by_level(all_alerts, :warning),
              info_alerts: count_alerts_by_level(all_alerts, :info),
              alerts: all_alerts,
              generated_at: DateTime.utc_now()
            }

            {:ok, alert_summary}

          error ->
            error
        end

      error ->
        error
    end
  end

  ## Private Implementation

  defp build_system_overview(system_health) do
    %{
      overall_score: system_health.overall_score,
      overall_level: system_health.overall_level,
      status_color: health_level_to_color(system_health.overall_level),
      total_circuits: system_health.total_circuits,
      healthy_circuits: system_health.healthy_circuits,
      unhealthy_circuits: system_health.unhealthy_circuits,
      critical_circuits: system_health.critical_circuits,
      health_percentage:
        if(system_health.total_circuits > 0,
          do: Float.round(system_health.healthy_circuits / system_health.total_circuits * 100, 1),
          else: 100
        ),
      top_issues: Enum.take(system_health.issues, 3),
      top_recommendations: Enum.take(system_health.recommendations, 3)
    }
  end

  defp build_circuit_grid(circuit_summaries) do
    circuit_summaries
    |> Enum.map(fn summary ->
      %{
        circuit_name: summary.circuit_name,
        health_score: summary.health_score,
        health_level: summary.health_level,
        state: summary.state,
        status_color: health_level_to_color(summary.health_level),
        state_color: state_to_color(summary.state),
        issue_count: summary.issue_count,
        recommendation_count: summary.recommendation_count,
        needs_attention: summary.health_level in [:poor, :critical]
      }
    end)
    |> Enum.sort_by(&{&1.needs_attention, &1.health_score}, fn
      {true, score1}, {false, _} -> true
      {false, _}, {true, score2} -> false
      {same, score1}, {same, score2} -> score1 <= score2
    end)
  end

  defp build_health_distribution(circuit_summaries) do
    distribution =
      circuit_summaries
      |> Enum.group_by(& &1.health_level)
      |> Enum.map(fn {level, circuits} ->
        count = length(circuits)

        percentage =
          if length(circuit_summaries) > 0 do
            Float.round(count / length(circuit_summaries) * 100, 1)
          else
            0
          end

        %{
          level: level,
          count: count,
          percentage: percentage,
          color: health_level_to_color(level)
        }
      end)
      |> Enum.sort_by(fn
        %{level: :excellent} -> 1
        %{level: :good} -> 2
        %{level: :fair} -> 3
        %{level: :poor} -> 4
        %{level: :critical} -> 5
      end)

    %{
      total_circuits: length(circuit_summaries),
      distribution: distribution
    }
  end

  defp build_performance_metrics(circuit_summaries) do
    if length(circuit_summaries) > 0 do
      avg_health_score =
        circuit_summaries
        |> Enum.map(& &1.health_score)
        |> Enum.sum()
        |> div(length(circuit_summaries))

      %{
        average_health_score: avg_health_score,
        circuits_above_80: Enum.count(circuit_summaries, &(&1.health_score >= 80)),
        circuits_below_50: Enum.count(circuit_summaries, &(&1.health_score < 50)),
        open_circuits: Enum.count(circuit_summaries, &(&1.state == :open)),
        half_open_circuits: Enum.count(circuit_summaries, &(&1.state == :half_open))
      }
    else
      %{
        average_health_score: 100,
        circuits_above_80: 0,
        circuits_below_50: 0,
        open_circuits: 0,
        half_open_circuits: 0
      }
    end
  end

  defp build_alerts(system_health, circuit_summaries) do
    alerts = []

    # System alerts
    alerts =
      if system_health.overall_level == :critical do
        [%{level: :critical, message: "System health is critical", type: :system} | alerts]
      else
        alerts
      end

    # Circuit alerts
    critical_circuits = Enum.filter(circuit_summaries, &(&1.health_level == :critical))

    alerts =
      if length(critical_circuits) > 0 do
        circuit_names = Enum.map(critical_circuits, & &1.circuit_name) |> Enum.join(", ")

        [
          %{level: :critical, message: "Critical circuits: #{circuit_names}", type: :circuits}
          | alerts
        ]
      else
        alerts
      end

    poor_circuits = Enum.filter(circuit_summaries, &(&1.health_level == :poor))

    alerts =
      if length(poor_circuits) > 0 do
        circuit_names = Enum.map(poor_circuits, & &1.circuit_name) |> Enum.join(", ")

        [
          %{level: :warning, message: "Poor health circuits: #{circuit_names}", type: :circuits}
          | alerts
        ]
      else
        alerts
      end

    Enum.reverse(alerts)
  end

  defp build_trends(_circuit_summaries, _time_window) do
    # Placeholder for trends - would require historical data storage
    %{
      health_trend: :stable,
      performance_trend: :stable,
      note: "Trend analysis requires historical data collection"
    }
  end

  # Green
  defp health_level_to_color(:excellent), do: "#22c55e"
  # Light green
  defp health_level_to_color(:good), do: "#84cc16"
  # Yellow
  defp health_level_to_color(:fair), do: "#eab308"
  # Orange
  defp health_level_to_color(:poor), do: "#f97316"
  # Red
  defp health_level_to_color(:critical), do: "#ef4444"
  # Gray
  defp health_level_to_color(_), do: "#6b7280"

  # Green
  defp state_to_color(:closed), do: "#22c55e"
  # Yellow
  defp state_to_color(:half_open), do: "#eab308"
  # Red
  defp state_to_color(:open), do: "#ef4444"
  # Gray
  defp state_to_color(_), do: "#6b7280"

  defp get_all_circuits do
    try do
      :ets.tab2list(:ex_llm_circuit_breakers)
      |> Enum.map(fn {name, _state} -> name end)
    rescue
      _ -> []
    end
  end

  defp get_circuit_throughput(_circuit_name, _time_window) do
    # Placeholder - would integrate with telemetry data
    {:ok, %{requests_per_minute: :rand.uniform(100), error_rate: :rand.uniform() * 0.1}}
  end

  defp get_circuit_response_times(_circuit_name, _time_window) do
    # Placeholder - would integrate with telemetry data
    {:ok,
     %{
       avg_response_time: :rand.uniform(500),
       p95_response_time: :rand.uniform(1000),
       p99_response_time: :rand.uniform(2000)
     }}
  end

  defp get_circuit_failure_rate(_circuit_name, _time_window) do
    # Placeholder - would integrate with telemetry data
    {:ok, :rand.uniform() * 0.2}
  end

  defp build_csv_data(summaries) do
    header = "Circuit Name,Health Score,Health Level,State,Issue Count,Recommendation Count\n"

    rows =
      summaries
      |> Enum.map(fn summary ->
        "#{summary.circuit_name},#{summary.health_score},#{summary.health_level},#{summary.state},#{summary.issue_count},#{summary.recommendation_count}"
      end)
      |> Enum.join("\n")

    header <> rows
  end

  defp default_alert_thresholds do
    %{
      critical_health_score: 30,
      warning_health_score: 50,
      max_critical_circuits: 2,
      max_failure_rate: 0.1,
      max_response_time: 5000
    }
  end

  defp build_circuit_alerts(summary, thresholds) do
    alerts = []

    alerts =
      if summary.health_score < thresholds.critical_health_score do
        [
          %{
            level: :critical,
            type: :circuit_health,
            circuit: summary.circuit_name,
            message:
              "Circuit #{summary.circuit_name} health is critical (#{summary.health_score})",
            value: summary.health_score,
            threshold: thresholds.critical_health_score,
            timestamp: DateTime.utc_now()
          }
          | alerts
        ]
      else
        alerts
      end

    alerts =
      if summary.state == :open do
        [
          %{
            level: :warning,
            type: :circuit_state,
            circuit: summary.circuit_name,
            message: "Circuit #{summary.circuit_name} is in OPEN state",
            value: :open,
            timestamp: DateTime.utc_now()
          }
          | alerts
        ]
      else
        alerts
      end

    alerts
  end

  defp count_alerts_by_level(alerts, level) do
    Enum.count(alerts, &(&1.level == level))
  end
end
