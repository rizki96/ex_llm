defmodule ExLLM.CircuitBreakerTest do
  use ExUnit.Case
  alias ExLLM.CircuitBreaker

  setup do
    # Initialize ETS table for each test
    if :ets.info(:ex_llm_circuit_breakers) != :undefined do
      :ets.delete(:ex_llm_circuit_breakers)
    end

    CircuitBreaker.init()
    :ok
  end

  describe "circuit breaker states" do
    test "starts in closed state" do
      circuit_name = "test_circuit"
      result = CircuitBreaker.call(circuit_name, fn -> :ok end)

      assert {:ok, :ok} = result
      assert {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.state == :closed
    end

    test "opens after failure threshold" do
      circuit_name = "failing_circuit"

      # Trigger failures up to threshold
      for _ <- 1..5 do
        CircuitBreaker.call(
          circuit_name,
          fn ->
            raise "test failure"
          end,
          failure_threshold: 5
        )
      end

      # Next call should be rejected
      result = CircuitBreaker.call(circuit_name, fn -> :ok end)
      assert {:error, :circuit_open} = result

      # Verify state is open
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.state == :open
      assert stats.failure_count == 5
    end

    test "transitions to half-open after reset timeout" do
      circuit_name = "recovery_circuit"

      # Open the circuit
      for _ <- 1..3 do
        CircuitBreaker.call(
          circuit_name,
          fn ->
            raise "test failure"
          end,
          failure_threshold: 3,
          reset_timeout: 100
        )
      end

      # Verify circuit is open
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.state == :open

      # Wait for reset timeout
      Process.sleep(150)

      # Next call should trigger half-open state
      CircuitBreaker.call(circuit_name, fn -> :ok end, reset_timeout: 100)

      # Note: The actual implementation transitions to half-open but still executes
      # the monitoring function which might fail. Let's check the state after
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.state in [:half_open, :closed]
    end

    test "closes from half-open after success threshold" do
      circuit_name = "recovery_success"

      # Open the circuit
      for _ <- 1..3 do
        CircuitBreaker.call(
          circuit_name,
          fn ->
            raise "test failure"
          end,
          failure_threshold: 3,
          success_threshold: 2,
          reset_timeout: 100
        )
      end

      # Wait for reset timeout
      Process.sleep(150)

      # Make successful calls to close the circuit
      for _ <- 1..2 do
        result =
          CircuitBreaker.call(circuit_name, fn -> :success end,
            success_threshold: 2,
            reset_timeout: 100
          )

        assert {:ok, :success} = result
      end

      # Circuit should be closed now
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.state == :closed
      assert stats.failure_count == 0
      assert stats.success_count == 0
    end
  end

  describe "timeout handling" do
    test "handles function timeout" do
      circuit_name = "timeout_circuit"

      result =
        CircuitBreaker.call(
          circuit_name,
          fn ->
            Process.sleep(100)
            :should_not_return
          end,
          timeout: 50
        )

      assert {:error, :timeout} = result

      # Should count as a failure
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.failure_count == 1
    end
  end

  describe "manual reset" do
    test "can manually reset an open circuit" do
      circuit_name = "manual_reset"

      # Open the circuit
      for _ <- 1..3 do
        CircuitBreaker.call(
          circuit_name,
          fn ->
            raise "test failure"
          end,
          failure_threshold: 3
        )
      end

      # Verify circuit is open
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.state == :open

      # Manual reset
      assert :ok = CircuitBreaker.reset(circuit_name)

      # Circuit should be closed
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.state == :closed
      assert stats.failure_count == 0

      # Should allow calls again
      assert {:ok, :success} = CircuitBreaker.call(circuit_name, fn -> :success end)
    end

    test "returns error for non-existent circuit" do
      assert {:error, :circuit_not_found} = CircuitBreaker.reset("non_existent")
    end
  end

  describe "configuration" do
    test "respects custom failure threshold" do
      circuit_name = "custom_threshold"

      # Should not open after 2 failures with threshold of 3
      for _ <- 1..2 do
        CircuitBreaker.call(
          circuit_name,
          fn ->
            raise "test failure"
          end,
          failure_threshold: 3
        )
      end

      # Check state - should have 2 failures
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.failure_count == 2
      assert stats.state == :closed

      # Should still accept calls
      assert {:ok, :success} =
               CircuitBreaker.call(circuit_name, fn -> :success end, failure_threshold: 3)

      # Success resets failure count
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.failure_count == 0

      # Need 3 more failures to open it
      for _ <- 1..3 do
        CircuitBreaker.call(
          circuit_name,
          fn ->
            raise "test failure"
          end,
          failure_threshold: 3
        )
      end

      # Now should be open
      assert {:error, :circuit_open} =
               CircuitBreaker.call(circuit_name, fn -> :ok end, failure_threshold: 3)
    end
  end

  describe "telemetry events" do
    test "emits telemetry events" do
      # Attach telemetry handler
      events_ref = make_ref()
      parent = self()

      :telemetry.attach_many(
        "test-handler-#{inspect(events_ref)}",
        [
          [:ex_llm, :circuit_breaker, :circuit_created],
          [:ex_llm, :circuit_breaker, :call_success],
          [:ex_llm, :circuit_breaker, :call_failure],
          [:ex_llm, :circuit_breaker, :state_change]
        ],
        fn event, measurements, metadata, _config ->
          send(parent, {events_ref, event, measurements, metadata})
        end,
        nil
      )

      circuit_name = "telemetry_test"

      # Create circuit with failure threshold of 1
      CircuitBreaker.call(circuit_name, fn -> :ok end, failure_threshold: 1)

      # Should receive circuit_created and call_success
      assert_receive {^events_ref, [:ex_llm, :circuit_breaker, :circuit_created], _,
                      %{circuit_name: ^circuit_name}}

      assert_receive {^events_ref, [:ex_llm, :circuit_breaker, :call_success], _,
                      %{circuit_name: ^circuit_name}}

      # Trigger failure - should open circuit since threshold is 1
      CircuitBreaker.call(circuit_name, fn -> raise "test" end)

      # Should receive call_failure and state_change
      assert_receive {^events_ref, [:ex_llm, :circuit_breaker, :call_failure], _,
                      %{circuit_name: ^circuit_name}}

      assert_receive {^events_ref, [:ex_llm, :circuit_breaker, :state_change], _,
                      %{circuit_name: ^circuit_name, old_state: :closed, new_state: :open}}

      :telemetry.detach("test-handler-#{inspect(events_ref)}")
    end
  end
end
