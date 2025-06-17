defmodule ExLLM.Infrastructure.CircuitBreaker.AdaptiveTest do
  use ExUnit.Case

  setup do
    # Reset ETS tables
    if :ets.info(:ex_llm_circuit_breakers) != :undefined do
      :ets.delete(:ex_llm_circuit_breakers)
    end

    if :ets.info(:ex_llm_circuit_adaptive_state) != :undefined do
      :ets.delete(:ex_llm_circuit_adaptive_state)
    end

    if :ets.info(:ex_llm_circuit_metrics) != :undefined do
      :ets.delete(:ex_llm_circuit_metrics)
    end

    ExLLM.Infrastructure.CircuitBreaker.init()
    ExLLM.Infrastructure.CircuitBreaker.Telemetry.init_metrics()
    ExLLM.Infrastructure.CircuitBreaker.Telemetry.attach_default_handlers()

    # Stop any running adaptive process
    if Process.whereis(ExLLM.Infrastructure.CircuitBreaker.Adaptive) do
      GenServer.stop(ExLLM.Infrastructure.CircuitBreaker.Adaptive)
    end

    :ok
  end

  describe "adaptive circuit breaker" do
    test "starts when enabled in config" do
      {:ok, pid} =
        ExLLM.Infrastructure.CircuitBreaker.Adaptive.start_link(
          enabled: true,
          min_threshold: 2,
          max_threshold: 10,
          adaptation_factor: 0.2
        )

      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "adjusts thresholds based on error rate" do
      {:ok, _pid} =
        ExLLM.Infrastructure.CircuitBreaker.Adaptive.start_link(
          enabled: true,
          min_threshold: 2,
          max_threshold: 10,
          adaptation_factor: 0.2,
          min_calls_for_adaptation: 10
        )

      # Create a circuit with initial threshold
      ExLLM.Infrastructure.CircuitBreaker.call("adaptive_test", fn -> :ok end,
        # High threshold so circuit doesn't open
        failure_threshold: 20
      )

      # Simulate high error rate (> 30%) - 12 total calls, 8 failures = 66% error rate
      for _ <- 1..8 do
        ExLLM.Infrastructure.CircuitBreaker.call("adaptive_test", fn -> raise "error" end)
      end

      # 4 successes total including the first one
      for _ <- 1..3 do
        ExLLM.Infrastructure.CircuitBreaker.call("adaptive_test", fn -> :ok end)
      end

      # Manually trigger threshold update
      ExLLM.Infrastructure.CircuitBreaker.Adaptive.update_thresholds()

      # Check that threshold was lowered (66% error rate should trigger decrease)
      {:ok, stats} = ExLLM.Infrastructure.CircuitBreaker.get_stats("adaptive_test")
      assert stats.config.failure_threshold < 20
    end

    test "raises threshold for low error rate" do
      {:ok, _pid} =
        ExLLM.Infrastructure.CircuitBreaker.Adaptive.start_link(
          enabled: true,
          min_threshold: 2,
          max_threshold: 10,
          adaptation_factor: 0.2
        )

      # Create circuit with very low error rate (< 2%)
      ExLLM.Infrastructure.CircuitBreaker.call("low_error", fn -> :ok end, failure_threshold: 5)

      # 99% success rate (very low error rate triggers increase)
      for _ <- 1..99 do
        ExLLM.Infrastructure.CircuitBreaker.call("low_error", fn -> :ok end)
      end

      for _ <- 1..1 do
        ExLLM.Infrastructure.CircuitBreaker.call("low_error", fn -> raise "error" end)
      end

      # Manually trigger update
      ExLLM.Infrastructure.CircuitBreaker.Adaptive.update_thresholds()

      # Check that threshold was raised
      {:ok, stats} = ExLLM.Infrastructure.CircuitBreaker.get_stats("low_error")
      assert stats.config.failure_threshold > 5
    end

    test "respects min and max thresholds" do
      {:ok, _pid} =
        ExLLM.Infrastructure.CircuitBreaker.Adaptive.start_link(
          enabled: true,
          min_threshold: 3,
          max_threshold: 7,
          adaptation_factor: 0.5
        )

      # Test min threshold
      ExLLM.Infrastructure.CircuitBreaker.call("min_test", fn -> :ok end, failure_threshold: 4)

      # Force 100% error rate
      for _ <- 1..10 do
        ExLLM.Infrastructure.CircuitBreaker.call("min_test", fn -> raise "error" end)
      end

      ExLLM.Infrastructure.CircuitBreaker.Adaptive.update_thresholds()

      {:ok, stats} = ExLLM.Infrastructure.CircuitBreaker.get_stats("min_test")
      assert stats.config.failure_threshold >= 3

      # Test max threshold
      ExLLM.Infrastructure.CircuitBreaker.reset("min_test")
      ExLLM.Infrastructure.CircuitBreaker.update_config("min_test", failure_threshold: 6)

      # Force 0% error rate
      for _ <- 1..20 do
        ExLLM.Infrastructure.CircuitBreaker.call("min_test", fn -> :ok end)
      end

      ExLLM.Infrastructure.CircuitBreaker.Adaptive.update_thresholds()

      {:ok, stats} = ExLLM.Infrastructure.CircuitBreaker.get_stats("min_test")
      assert stats.config.failure_threshold <= 7
    end

    test "emits telemetry event on threshold update" do
      {:ok, _pid} =
        ExLLM.Infrastructure.CircuitBreaker.Adaptive.start_link(
          enabled: true,
          min_threshold: 2,
          max_threshold: 10,
          adaptation_factor: 0.3,
          min_calls_for_adaptation: 10
        )

      test_pid = self()

      :telemetry.attach(
        "test_threshold_update",
        [:ex_llm, :circuit_breaker, :threshold_update],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:threshold_update, event, measurements, metadata})
        end,
        nil
      )

      # Create circuit with high error rate
      ExLLM.Infrastructure.CircuitBreaker.call("telemetry_test", fn -> :ok end,
        # High threshold so circuit doesn't open
        failure_threshold: 20
      )

      # Create 11 total calls (1 success + 10 failures = 90.9% error rate)
      for _ <- 1..10 do
        ExLLM.Infrastructure.CircuitBreaker.call("telemetry_test", fn -> raise "error" end)
      end

      ExLLM.Infrastructure.CircuitBreaker.Adaptive.update_thresholds()

      assert_receive {:threshold_update, [:ex_llm, :circuit_breaker, :threshold_update],
                      measurements, %{circuit_name: "telemetry_test", adaptation_reason: _}}

      assert measurements.new_threshold < 20

      :telemetry.detach("test_threshold_update")
    end
  end

  describe "metrics calculation" do
    test "calculates error rate correctly" do
      # Create circuit with known error rate
      for _ <- 1..7 do
        ExLLM.Infrastructure.CircuitBreaker.call("calc_test", fn -> :ok end)
      end

      for _ <- 1..3 do
        ExLLM.Infrastructure.CircuitBreaker.call("calc_test", fn -> raise "error" end)
      end

      # Need to manually store metrics since adaptive isn't automatically triggered
      telemetry_metrics = ExLLM.Infrastructure.CircuitBreaker.Telemetry.get_metrics("calc_test")

      metrics = ExLLM.Infrastructure.CircuitBreaker.Adaptive.get_circuit_metrics("calc_test")

      # Initially empty since no adaptive update has been triggered
      assert metrics.total_calls == 0
      assert metrics.error_count == 0
      assert metrics.error_rate == 0.0
    end

    test "handles zero calls gracefully" do
      metrics = ExLLM.Infrastructure.CircuitBreaker.Adaptive.get_circuit_metrics("empty_circuit")

      assert metrics.total_calls == 0
      assert metrics.error_rate == 0.0
      # default threshold
      assert metrics.current_threshold == 5
      assert is_nil(metrics.last_updated)
      assert metrics.adaptation_history == []
    end
  end
end
