defmodule ExLLM.Infrastructure.CircuitBreaker.HealthCheckTest do
  use ExUnit.Case, async: false

  alias ExLLM.Infrastructure.CircuitBreaker
  alias ExLLM.Infrastructure.CircuitBreaker.HealthCheck

  setup do
    # Reset ETS tables
    if :ets.info(:ex_llm_circuit_breakers) != :undefined do
      :ets.delete(:ex_llm_circuit_breakers)
    end

    # Clean up any existing Registry and DynamicSupervisor from bulkhead system
    registry_name = ExLLM.Infrastructure.CircuitBreaker.Bulkhead.Registry
    supervisor_name = ExLLM.Infrastructure.CircuitBreaker.Bulkhead.Supervisor

    if Process.whereis(registry_name) do
      try do
        GenServer.stop(registry_name, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end

    if Process.whereis(supervisor_name) do
      try do
        GenServer.stop(supervisor_name, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end

    # Initialize circuit breaker system
    CircuitBreaker.init()

    # Initialize bulkhead system for health checks
    ExLLM.Infrastructure.CircuitBreaker.Bulkhead.init()

    # Initialize telemetry metrics
    ExLLM.Infrastructure.CircuitBreaker.Telemetry.init_metrics()

    :ok
  end

  describe "system health" do
    test "returns excellent health for empty system" do
      assert {:ok, health} = HealthCheck.system_health()

      assert health.overall_score == 100
      assert health.overall_level == :excellent
      assert health.total_circuits == 0
      assert health.healthy_circuits == 0
      assert health.unhealthy_circuits == 0
      assert health.critical_circuits == 0
      assert health.issues == ["No active circuits found"]
    end

    test "calculates health for system with healthy circuits" do
      # Create some healthy circuits
      create_healthy_circuit("service_1")
      create_healthy_circuit("service_2")

      assert {:ok, health} = HealthCheck.system_health()

      assert health.overall_score >= 90
      assert health.overall_level in [:excellent, :good]
      assert health.total_circuits == 2
      assert health.healthy_circuits == 2
      assert health.critical_circuits == 0
    end

    test "detects system issues with unhealthy circuits" do
      # Create mix of healthy and unhealthy circuits
      create_healthy_circuit("healthy_service")
      create_unhealthy_circuit("unhealthy_service")

      assert {:ok, health} = HealthCheck.system_health()

      assert health.total_circuits == 2
      assert health.critical_circuits > 0
      assert length(health.issues) > 0
      assert length(health.recommendations) > 0
    end
  end

  describe "circuit health" do
    test "returns health for non-existent circuit" do
      assert {:error, :circuit_not_found} = HealthCheck.circuit_health("non_existent")
    end

    test "calculates health for healthy closed circuit" do
      circuit_name = "healthy_circuit"
      create_healthy_circuit(circuit_name)

      assert {:ok, health} = HealthCheck.circuit_health(circuit_name)

      assert health.circuit_name == circuit_name
      assert health.health_score >= 90
      assert health.health_level in [:excellent, :good]
      assert health.state == :closed
      assert is_list(health.issues)
      assert is_list(health.recommendations)
      assert is_map(health.metrics)
      assert %DateTime{} = health.last_updated
    end

    test "detects issues with open circuit" do
      circuit_name = "open_circuit"
      create_open_circuit(circuit_name)

      assert {:ok, health} = HealthCheck.circuit_health(circuit_name)

      assert health.state == :open
      assert health.health_score < 50
      assert health.health_level in [:poor, :critical]

      # Should have issue about being open
      open_issue =
        Enum.find(health.issues, fn issue ->
          String.contains?(issue, "OPEN state")
        end)

      assert open_issue != nil
    end

    test "provides recommendations for problematic circuits" do
      circuit_name = "problematic_circuit"
      create_problematic_circuit(circuit_name)

      assert {:ok, health} = HealthCheck.circuit_health(circuit_name)

      assert length(health.recommendations) > 0
      assert length(health.issues) > 0
    end
  end

  describe "health summary" do
    test "returns empty summary for no circuits" do
      assert {:ok, summary} = HealthCheck.health_summary()
      assert summary == []
    end

    test "returns summary for multiple circuits" do
      create_healthy_circuit("service_1")
      create_healthy_circuit("service_2")
      create_unhealthy_circuit("service_3")

      assert {:ok, summary} = HealthCheck.health_summary()

      assert length(summary) == 3

      # Check summary structure
      summary_item = List.first(summary)
      assert Map.has_key?(summary_item, :circuit_name)
      assert Map.has_key?(summary_item, :health_score)
      assert Map.has_key?(summary_item, :health_level)
      assert Map.has_key?(summary_item, :state)
      assert Map.has_key?(summary_item, :issue_count)
      assert Map.has_key?(summary_item, :recommendation_count)
    end
  end

  describe "health report" do
    test "generates comprehensive health report" do
      create_healthy_circuit("service_1")
      create_unhealthy_circuit("service_2")

      assert {:ok, report} = HealthCheck.health_report()

      # Check report structure
      assert Map.has_key?(report, :system)
      assert Map.has_key?(report, :circuits)
      assert Map.has_key?(report, :trends)
      assert Map.has_key?(report, :alerts)
      assert Map.has_key?(report, :report_generated_at)

      # Check system section
      assert is_map(report.system)
      assert Map.has_key?(report.system, :overall_score)
      assert Map.has_key?(report.system, :overall_level)

      # Check circuits section
      assert is_list(report.circuits)
      assert length(report.circuits) == 2

      # Check alerts section
      assert is_list(report.alerts)
      assert length(report.alerts) > 0
    end
  end

  describe "convenience functions" do
    test "healthy? returns true for healthy system" do
      create_healthy_circuit("service_1")
      create_healthy_circuit("service_2")

      assert HealthCheck.healthy?() == true
    end

    test "healthy? returns false for unhealthy system" do
      create_unhealthy_circuit("failing_service")

      assert HealthCheck.healthy?() == false
    end

    test "critical_circuits returns circuits needing attention" do
      create_healthy_circuit("healthy_service")
      create_unhealthy_circuit("critical_service")

      assert {:ok, critical} = HealthCheck.critical_circuits()
      assert "critical_service" in critical
      assert "healthy_service" not in critical
    end
  end

  describe "health scoring" do
    test "scores closed circuits highly" do
      circuit_name = "closed_circuit"
      create_healthy_circuit(circuit_name)

      {:ok, health} = HealthCheck.circuit_health(circuit_name)
      assert health.health_score >= 80
    end

    test "scores open circuits poorly" do
      circuit_name = "open_circuit"
      create_open_circuit(circuit_name)

      {:ok, health} = HealthCheck.circuit_health(circuit_name)
      assert health.health_score <= 50
    end

    test "scores half-open circuits moderately" do
      circuit_name = "half_open_circuit"
      create_half_open_circuit(circuit_name)

      {:ok, health} = HealthCheck.circuit_health(circuit_name)
      assert health.health_score >= 30
      assert health.health_score <= 80
    end
  end

  describe "time window support" do
    test "accepts custom time window for health checks" do
      create_healthy_circuit("service_1")

      # Test with different time windows
      assert {:ok, _health1} = HealthCheck.circuit_health("service_1", time_window: 60_000)
      assert {:ok, _health2} = HealthCheck.system_health(time_window: 300_000)
      assert {:ok, _summary} = HealthCheck.health_summary(time_window: 600_000)
    end
  end

  ## Helper Functions

  defp create_healthy_circuit(name) do
    # Create a circuit in closed state with good configuration
    CircuitBreaker.call(name, fn -> {:ok, "success"} end,
      failure_threshold: 5,
      success_threshold: 3,
      reset_timeout: 30_000
    )
  end

  defp create_unhealthy_circuit(name) do
    # Create a circuit and trigger failures to open it
    for _ <- 1..6 do
      CircuitBreaker.call(
        name,
        fn ->
          raise "simulated failure"
        end,
        failure_threshold: 5
      )
    end
  end

  defp create_open_circuit(name) do
    # Create a circuit and force it to open state
    create_unhealthy_circuit(name)
  end

  defp create_half_open_circuit(name) do
    # Create an open circuit and manually transition to half-open
    create_open_circuit(name)

    # Manually modify the circuit state to half-open for testing
    case :ets.lookup(:ex_llm_circuit_breakers, name) do
      [{^name, state}] ->
        new_state = %{state | state: :half_open, success_count: 0}
        :ets.insert(:ex_llm_circuit_breakers, {name, new_state})

      [] ->
        :ok
    end
  end

  defp create_problematic_circuit(name) do
    # Create a circuit with multiple issues
    create_unhealthy_circuit(name)

    # Could also configure bulkhead with high utilization
    ExLLM.Infrastructure.CircuitBreaker.Bulkhead.configure(name,
      max_concurrent: 1,
      max_queued: 1
    )
  end
end
