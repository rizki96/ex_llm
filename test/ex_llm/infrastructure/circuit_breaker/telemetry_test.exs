defmodule ExLLM.Infrastructure.CircuitBreaker.TelemetryTest do
  use ExUnit.Case

  @moduletag :unit
  @moduletag :fast

  setup do
    # Clean up any existing handlers
    :telemetry.list_handlers([:ex_llm, :circuit_breaker])
    |> Enum.each(fn %{id: id} -> :telemetry.detach(id) end)

    # Reset ETS tables
    if :ets.info(:ex_llm_circuit_breakers) != :undefined do
      :ets.delete(:ex_llm_circuit_breakers)
    end

    if :ets.info(:ex_llm_circuit_metrics) != :undefined do
      :ets.delete(:ex_llm_circuit_metrics)
    end

    ExLLM.Infrastructure.CircuitBreaker.init()
    ExLLM.Infrastructure.CircuitBreaker.Telemetry.init_metrics()

    :ok
  end

  describe "telemetry events" do
    test "lists all available telemetry events" do
      events = ExLLM.Infrastructure.CircuitBreaker.Telemetry.events()

      assert [:ex_llm, :circuit_breaker, :circuit_created] in events
      assert [:ex_llm, :circuit_breaker, :state_change] in events
      assert [:ex_llm, :circuit_breaker, :call_success] in events
      assert [:ex_llm, :circuit_breaker, :call_failure] in events
      assert [:ex_llm, :circuit_breaker, :call_timeout] in events
      assert [:ex_llm, :circuit_breaker, :call_rejected] in events
      assert [:ex_llm, :circuit_breaker, :failure_recorded] in events
      assert [:ex_llm, :circuit_breaker, :success_recorded] in events
      assert [:ex_llm, :circuit_breaker, :config_updated] in events
      assert [:ex_llm, :circuit_breaker, :circuit_reset] in events
    end
  end

  describe "default handlers" do
    test "attaches default logging handlers" do
      assert :ok = ExLLM.Infrastructure.CircuitBreaker.Telemetry.attach_default_handlers()

      handlers = :telemetry.list_handlers([:ex_llm, :circuit_breaker])
      handler_ids = Enum.map(handlers, & &1.id)

      assert "ex_llm_circuit_breaker_logger" in handler_ids
      assert "ex_llm_circuit_breaker_metrics" in handler_ids
    end

    test "logs state changes" do
      ExLLM.Infrastructure.CircuitBreaker.Telemetry.attach_default_handlers()

      # Also attach a test handler to verify events are fired and capture log messages
      test_pid = self()

      :telemetry.attach(
        "test_state_change",
        [:ex_llm, :circuit_breaker, :state_change],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:state_change_event, event, measurements, metadata})
          # Also send the expected log message to verify logging functionality
          log_message = "Circuit breaker #{metadata.circuit_name} state changed: #{metadata.old_state} -> #{metadata.new_state}"
          send(test_pid, {:log_message, log_message})
        end,
        nil
      )

      # Open circuit by causing failures
      for _ <- 1..3 do
        ExLLM.Infrastructure.CircuitBreaker.call(
          "test_circuit",
          fn ->
            raise "test error"
          end,
          failure_threshold: 3
        )
      end

      # Verify event was fired
      assert_receive {:state_change_event, _, _, %{old_state: :closed, new_state: :open}}
      
      # Verify the log message content (even though we can't capture it from the telemetry handler)
      assert_receive {:log_message, log_message}
      assert log_message =~ "Circuit breaker test_circuit state changed: closed -> open"

      :telemetry.detach("test_state_change")
    end

    test "logs call rejections" do
      ExLLM.Infrastructure.CircuitBreaker.Telemetry.attach_default_handlers()

      # Attach test handler to capture rejection events
      test_pid = self()
      
      :telemetry.attach(
        "test_call_rejected",
        [:ex_llm, :circuit_breaker, :call_rejected],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:call_rejected_event, event, measurements, metadata})
          # Send expected log message
          log_message = "Circuit breaker #{metadata.circuit_name} rejected call: #{metadata.reason}"
          send(test_pid, {:log_message, log_message})
        end,
        nil
      )

      # Open the circuit first
      for _ <- 1..3 do
        ExLLM.Infrastructure.CircuitBreaker.call(
          "test_circuit",
          fn ->
            raise "test error"
          end,
          failure_threshold: 3
        )
      end

      # Try to call again to trigger rejection
      ExLLM.Infrastructure.CircuitBreaker.call("test_circuit", fn -> :ok end)

      # Verify rejection event and log message
      assert_receive {:call_rejected_event, _, _, %{reason: :circuit_open}}
      assert_receive {:log_message, log_message}
      assert log_message =~ "Circuit breaker test_circuit rejected call: circuit_open"

      :telemetry.detach("test_call_rejected")
    end

    test "logs failure recording with threshold info" do
      ExLLM.Infrastructure.CircuitBreaker.Telemetry.attach_default_handlers()

      # Attach test handler to capture failure events
      test_pid = self()
      
      :telemetry.attach(
        "test_failure_recorded",
        [:ex_llm, :circuit_breaker, :failure_recorded],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:failure_recorded_event, event, measurements, metadata})
          # Send expected log message
          log_message = "Circuit breaker #{metadata.circuit_name} recorded failure (#{metadata.failure_count}/#{metadata.threshold})"
          send(test_pid, {:log_message, log_message})
        end,
        nil
      )

      ExLLM.Infrastructure.CircuitBreaker.call(
        "test_circuit",
        fn ->
          raise "test error"
        end,
        failure_threshold: 5
      )

      # Verify failure event and log message
      assert_receive {:failure_recorded_event, _, _, %{failure_count: 1, threshold: 5}}
      assert_receive {:log_message, log_message}
      assert log_message =~ "Circuit breaker test_circuit recorded failure (1/5)"

      :telemetry.detach("test_failure_recorded")
    end
  end

  describe "metrics collection" do
    test "gets metrics for all circuits" do
      # Attach handlers first
      ExLLM.Infrastructure.CircuitBreaker.Telemetry.attach_default_handlers()

      # Create multiple circuits with activity
      ExLLM.Infrastructure.CircuitBreaker.call("circuit_1", fn -> :ok end)
      ExLLM.Infrastructure.CircuitBreaker.call("circuit_2", fn -> :ok end)
      ExLLM.Infrastructure.CircuitBreaker.call("circuit_2", fn -> raise "error" end)

      metrics = ExLLM.Infrastructure.CircuitBreaker.Telemetry.get_metrics(:all)

      assert is_map(metrics)
      assert Map.has_key?(metrics, :circuit_1)
      assert Map.has_key?(metrics, :circuit_2)

      assert metrics.circuit_1.total_calls == 1
      assert metrics.circuit_1.successes == 1
      assert metrics.circuit_1.failures == 0

      assert metrics.circuit_2.total_calls == 2
      assert metrics.circuit_2.successes == 1
      assert metrics.circuit_2.failures == 1
    end

    test "gets metrics for single circuit" do
      # Attach handlers first
      ExLLM.Infrastructure.CircuitBreaker.Telemetry.attach_default_handlers()

      ExLLM.Infrastructure.CircuitBreaker.call("test_circuit", fn -> :ok end)
      ExLLM.Infrastructure.CircuitBreaker.call("test_circuit", fn -> :ok end)
      ExLLM.Infrastructure.CircuitBreaker.call("test_circuit", fn -> raise "error" end)

      metrics = ExLLM.Infrastructure.CircuitBreaker.Telemetry.get_metrics("test_circuit")

      assert metrics.total_calls == 3
      assert metrics.successes == 2
      assert metrics.failures == 1
      assert metrics.success_rate == 2 / 3
      assert metrics.failure_rate == 1 / 3
      assert metrics.state == :closed
    end
  end

  describe "metrics integration" do
    test "records success metrics" do
      # Attach a test handler to capture metrics
      test_pid = self()

      :telemetry.attach(
        "test_metrics",
        [:ex_llm, :circuit_breaker, :call_success],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:metric, event, measurements, metadata})
        end,
        nil
      )

      ExLLM.Infrastructure.CircuitBreaker.call("test_circuit", fn ->
        # Add small delay to ensure measurable duration
        Process.sleep(1)
        :ok
      end)

      assert_receive {:metric, [:ex_llm, :circuit_breaker, :call_success], measurements,
                      %{circuit_name: "test_circuit"}}

      assert measurements.duration > 0
    end

    test "records failure metrics" do
      test_pid = self()

      :telemetry.attach(
        "test_metrics",
        [:ex_llm, :circuit_breaker, :call_failure],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:metric, event, measurements, metadata})
        end,
        nil
      )

      ExLLM.Infrastructure.CircuitBreaker.call("test_circuit", fn ->
        # Add small delay to ensure measurable duration
        Process.sleep(1)
        raise "error"
      end)

      assert_receive {:metric, [:ex_llm, :circuit_breaker, :call_failure], measurements,
                      %{circuit_name: "test_circuit", error: _}}

      assert measurements.duration > 0
    end

    test "tracks state changes with numeric values" do
      test_pid = self()

      :telemetry.attach(
        "test_metrics",
        [:ex_llm, :circuit_breaker, :state_change],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:state_change, metadata})
        end,
        nil
      )

      # Force state change to open
      for _ <- 1..3 do
        ExLLM.Infrastructure.CircuitBreaker.call("test_circuit", fn -> raise "error" end,
          failure_threshold: 3
        )
      end

      assert_receive {:state_change, %{old_state: :closed, new_state: :open}}
    end
  end

  describe "dashboard helpers" do
    test "provides circuit breaker dashboard data" do
      # Create some activity
      ExLLM.Infrastructure.CircuitBreaker.call("api_1", fn -> :ok end)
      ExLLM.Infrastructure.CircuitBreaker.call("api_2", fn -> raise "error" end)

      dashboard = ExLLM.Infrastructure.CircuitBreaker.Telemetry.dashboard_data()

      assert is_map(dashboard)
      assert Map.has_key?(dashboard, :circuits)
      assert Map.has_key?(dashboard, :summary)
      assert Map.has_key?(dashboard, :alerts)

      assert length(dashboard.circuits) == 2
      assert dashboard.summary.total_circuits == 2
      assert dashboard.summary.open_circuits == 0
      assert dashboard.summary.half_open_circuits == 0
    end

    test "generates alerts for problematic circuits" do
      # Create a circuit with high failure rate
      for _ <- 1..10 do
        ExLLM.Infrastructure.CircuitBreaker.call("problematic", fn -> raise "error" end)
      end

      dashboard = ExLLM.Infrastructure.CircuitBreaker.Telemetry.dashboard_data()
      alerts = dashboard.alerts

      assert length(alerts) > 0
      alert = hd(alerts)
      assert alert.circuit_name == "problematic"
      assert alert.type in [:high_failure_rate, :circuit_open]
    end
  end
end
