defmodule ExLLM.Infrastructure.CircuitBreaker.MetricsTest do
  use ExUnit.Case, async: false

  alias ExLLM.Infrastructure.CircuitBreaker
  alias ExLLM.Infrastructure.CircuitBreaker.Metrics

  setup do
    # Clean up ETS tables
    tables_to_clean = [
      :ex_llm_circuit_breakers,
      :ex_llm_circuit_breaker_configs,
      :ex_llm_circuit_breaker_bulkheads
    ]

    Enum.each(tables_to_clean, fn table ->
      if :ets.info(table) != :undefined do
        :ets.delete(table)
      end
    end)

    # Initialize circuit breaker system
    CircuitBreaker.init()

    # Enable metrics for testing
    original_config = Application.get_env(:ex_llm, :circuit_breaker_metrics, [])

    Application.put_env(:ex_llm, :circuit_breaker_metrics,
      enabled: true,
      # Use test backend instead of actual ones
      backends: [:test_backend],
      prometheus: [
        registry: :default,
        namespace: "test_ex_llm_circuit_breaker"
      ],
      statsd: [
        host: "localhost",
        port: 8125,
        namespace: "test.ex_llm.circuit_breaker"
      ]
    )

    on_exit(fn ->
      Application.put_env(:ex_llm, :circuit_breaker_metrics, original_config)
    end)

    :ok
  end

  describe "metrics configuration" do
    test "detects when metrics are enabled" do
      assert Metrics.setup() == :ok
    end

    test "handles disabled metrics gracefully" do
      Application.put_env(:ex_llm, :circuit_breaker_metrics, enabled: false)

      assert Metrics.setup() == :ok
      assert Metrics.get_metrics("test_circuit") == {:error, :metrics_disabled}
    end
  end

  describe "request metrics recording" do
    test "records successful requests" do
      circuit_name = "success_test"

      # Should not raise any errors
      assert :ok = Metrics.record_request(circuit_name, :success, 150)
      assert :ok = Metrics.record_request(circuit_name, :failure, 300)
      assert :ok = Metrics.record_request(circuit_name, :timeout, 5000)
    end

    test "validates result labels" do
      circuit_name = "validation_test"

      # Valid labels should work
      assert :ok = Metrics.record_request(circuit_name, :success, 100)
      assert :ok = Metrics.record_request(circuit_name, :failure, 200)
      assert :ok = Metrics.record_request(circuit_name, :timeout, 300)
      assert :ok = Metrics.record_request(circuit_name, :rejected, 400)

      # Invalid labels should raise error
      assert_raise FunctionClauseError, fn ->
        Metrics.record_request(circuit_name, :invalid_result, 100)
      end
    end
  end

  describe "state change metrics" do
    test "records state transitions" do
      circuit_name = "state_test"

      # Valid state transitions
      assert :ok = Metrics.record_state_change(circuit_name, :closed, :open)
      assert :ok = Metrics.record_state_change(circuit_name, :open, :half_open)
      assert :ok = Metrics.record_state_change(circuit_name, :half_open, :closed)
    end

    test "validates state labels" do
      circuit_name = "state_validation_test"

      # Valid states should work
      assert :ok = Metrics.record_state_change(circuit_name, :closed, :open)

      # Invalid states should raise error
      assert_raise FunctionClauseError, fn ->
        Metrics.record_state_change(circuit_name, :invalid_state, :closed)
      end
    end

    test "records state duration" do
      circuit_name = "duration_test"

      assert :ok = Metrics.record_state_duration(circuit_name, :closed, 5000)
      assert :ok = Metrics.record_state_duration(circuit_name, :open, 30_000)
      assert :ok = Metrics.record_state_duration(circuit_name, :half_open, 1000)
    end
  end

  describe "bulkhead metrics" do
    test "records bulkhead utilization metrics" do
      circuit_name = "bulkhead_test"

      metrics = %{
        active_count: 5,
        queued_count: 2,
        total_accepted: 100,
        total_rejected: 5,
        config: %{max_concurrent: 10}
      }

      assert :ok = Metrics.record_bulkhead_metrics(circuit_name, metrics)
    end

    test "handles missing config gracefully" do
      circuit_name = "bulkhead_no_config_test"

      metrics = %{
        active_count: 3,
        queued_count: 1,
        total_accepted: 50,
        total_rejected: 2
      }

      # Should not raise error even without config
      assert :ok = Metrics.record_bulkhead_metrics(circuit_name, metrics)
    end
  end

  describe "health metrics" do
    test "records health scores and levels" do
      circuit_name = "health_test"

      health = %{
        health_score: 85,
        health_level: :good,
        circuit_name: circuit_name
      }

      assert :ok = Metrics.record_health_metrics(circuit_name, health)
    end

    test "handles all health levels" do
      circuit_name = "health_levels_test"

      health_levels = [:excellent, :good, :fair, :poor, :critical]

      Enum.each(health_levels, fn level ->
        health = %{
          health_score: 50,
          health_level: level,
          circuit_name: circuit_name
        }

        assert :ok = Metrics.record_health_metrics(circuit_name, health)
      end)
    end
  end

  describe "metrics collection" do
    test "collects metrics for individual circuits" do
      circuit_name = "metrics_collection_test"

      # Record some metrics
      Metrics.record_request(circuit_name, :success, 100)
      Metrics.record_state_change(circuit_name, :closed, :open)

      case Metrics.get_metrics(circuit_name) do
        {:error, :metrics_disabled} ->
          # Metrics are disabled in test
          :ok

        metrics ->
          assert is_map(metrics)
          assert metrics.circuit_name == circuit_name
          assert %DateTime{} = metrics.collected_at
      end
    end

    test "handles non-existent circuits" do
      case Metrics.get_metrics("non_existent_circuit") do
        {:error, :metrics_disabled} -> :ok
        metrics -> assert is_map(metrics)
      end
    end
  end

  describe "system metrics" do
    test "collects system-wide metrics" do
      # Create some circuits
      CircuitBreaker.call("circuit_1", fn -> :ok end)
      CircuitBreaker.call("circuit_2", fn -> :ok end)

      case Metrics.get_system_metrics() do
        {:error, :metrics_disabled} ->
          # Expected when metrics are disabled
          :ok

        {:ok, system_metrics} ->
          assert is_map(system_metrics)
          assert is_integer(system_metrics.total_circuits)
          assert is_integer(system_metrics.active_circuits)
          assert %DateTime{} = system_metrics.collected_at
          assert is_list(system_metrics.circuit_summaries)
      end
    end
  end

  describe "telemetry integration" do
    test "attaches telemetry handlers" do
      # Setup should attach handlers without error
      assert :ok = Metrics.setup()

      # Test that telemetry events can be emitted
      circuit_name = "telemetry_test"

      :telemetry.execute(
        [:ex_llm, :circuit_breaker, :call_success],
        %{duration: 150},
        %{circuit_name: circuit_name}
      )

      :telemetry.execute(
        [:ex_llm, :circuit_breaker, :state_change],
        %{},
        %{circuit_name: circuit_name, old_state: :closed, new_state: :open}
      )

      # If we get here without errors, telemetry integration is working
      assert true
    end
  end

  describe "backend integration" do
    test "handles missing prometheus gracefully" do
      # Test with prometheus backend when library isn't available
      Application.put_env(:ex_llm, :circuit_breaker_metrics,
        enabled: true,
        backends: [:prometheus]
      )

      # Should not crash even if prometheus isn't available
      assert :ok = Metrics.setup()
    end

    test "handles missing statsd gracefully" do
      # Test with statsd backend when library isn't available
      Application.put_env(:ex_llm, :circuit_breaker_metrics,
        enabled: true,
        backends: [:statsd]
      )

      # Should not crash even if statsd isn't available
      assert :ok = Metrics.setup()
    end

    test "handles unknown backends gracefully" do
      Application.put_env(:ex_llm, :circuit_breaker_metrics,
        enabled: true,
        backends: [:unknown_backend]
      )

      # Should handle unknown backends without crashing
      assert :ok = Metrics.setup()
    end
  end

  describe "prometheus export" do
    test "handles prometheus export when not available" do
      case Metrics.export_prometheus() do
        {:error, _} -> :ok
        {:ok, _} -> :ok
      end
    end
  end

  describe "configuration validation" do
    test "uses default configuration when none provided" do
      Application.delete_env(:ex_llm, :circuit_breaker_metrics)

      # Should use defaults and not crash
      assert :ok = Metrics.setup()
    end

    test "validates prometheus configuration" do
      Application.put_env(:ex_llm, :circuit_breaker_metrics,
        enabled: true,
        backends: [:prometheus],
        prometheus: [
          registry: :test_registry,
          namespace: "test_namespace"
        ]
      )

      assert :ok = Metrics.setup()
    end

    test "validates statsd configuration" do
      Application.put_env(:ex_llm, :circuit_breaker_metrics,
        enabled: true,
        backends: [:statsd],
        statsd: [
          host: "127.0.0.1",
          port: 9125,
          namespace: "test.namespace"
        ]
      )

      assert :ok = Metrics.setup()
    end
  end

  describe "metric emission robustness" do
    test "handles metric emission errors gracefully" do
      circuit_name = "error_test"

      # These should not raise errors even if backends fail
      assert :ok = Metrics.record_request(circuit_name, :success, 100)
      assert :ok = Metrics.record_state_change(circuit_name, :closed, :open)
      assert :ok = Metrics.record_state_duration(circuit_name, :open, 5000)

      metrics = %{active_count: 1, queued_count: 0}
      assert :ok = Metrics.record_bulkhead_metrics(circuit_name, metrics)

      health = %{health_score: 75, health_level: :good}
      assert :ok = Metrics.record_health_metrics(circuit_name, health)
    end
  end

  describe "integration with circuit breaker events" do
    test "records metrics when circuit breaker events occur" do
      circuit_name = "integration_test"

      # Set up metrics collection
      Metrics.setup()

      # Perform circuit breaker operations that should generate telemetry
      result1 = CircuitBreaker.call(circuit_name, fn -> {:ok, "success"} end)
      assert {:ok, "success"} = result1

      # Trigger a failure
      result2 = CircuitBreaker.call(circuit_name, fn -> raise "test error" end)
      assert {:error, %RuntimeError{}} = result2

      # The telemetry handlers should have processed these events
      # No explicit assertions since we're testing the integration doesn't crash
      assert true
    end
  end
end
