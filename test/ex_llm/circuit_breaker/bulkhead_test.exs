defmodule ExLLM.CircuitBreaker.BulkheadTest do
  use ExUnit.Case

  setup do
    # Reset ETS tables
    if :ets.info(:ex_llm_circuit_breakers) != :undefined do
      :ets.delete(:ex_llm_circuit_breakers)
    end

    if :ets.info(:ex_llm_circuit_breaker_bulkheads) != :undefined do
      :ets.delete(:ex_llm_circuit_breaker_bulkheads)
    end

    # Clean up any existing Registry and DynamicSupervisor
    registry_name = ExLLM.CircuitBreaker.Bulkhead.Registry
    supervisor_name = ExLLM.CircuitBreaker.Bulkhead.Supervisor

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

    # Initialize systems
    ExLLM.CircuitBreaker.init()
    ExLLM.CircuitBreaker.Bulkhead.init()

    :ok
  end

  describe "bulkhead initialization" do
    test "creates Registry for bulkhead workers" do
      assert Process.whereis(ExLLM.CircuitBreaker.Bulkhead.Registry) != nil
    end

    test "configures default concurrency limits" do
      config = ExLLM.CircuitBreaker.Bulkhead.get_config("test_circuit")

      assert config.max_concurrent == 10
      assert config.max_queued == 50
      assert config.queue_timeout == 5000
    end
  end

  describe "concurrency limiting" do
    test "enforces max concurrent requests" do
      # Configure low limit for testing
      ExLLM.CircuitBreaker.Bulkhead.configure("limited",
        max_concurrent: 2,
        max_queued: 0
      )

      # Start 3 concurrent requests
      parent = self()

      task1 =
        Task.async(fn ->
          ExLLM.CircuitBreaker.call_with_bulkhead("limited", fn ->
            send(parent, {:started, 1})
            Process.sleep(100)
            :ok
          end)
        end)

      task2 =
        Task.async(fn ->
          ExLLM.CircuitBreaker.call_with_bulkhead("limited", fn ->
            send(parent, {:started, 2})
            Process.sleep(100)
            :ok
          end)
        end)

      # Give tasks time to start
      Process.sleep(10)

      # Third request should be rejected
      result =
        ExLLM.CircuitBreaker.call_with_bulkhead("limited", fn ->
          send(parent, {:started, 3})
          :ok
        end)

      assert {:error, :bulkhead_full} = result
      assert_receive {:started, 1}
      assert_receive {:started, 2}
      refute_receive {:started, 3}

      Task.await(task1)
      Task.await(task2)
    end

    test "queues requests when bulkhead is full" do
      ExLLM.CircuitBreaker.Bulkhead.configure("queued",
        max_concurrent: 1,
        max_queued: 2,
        queue_timeout: 1000
      )

      parent = self()

      # First request holds the bulkhead
      task1 =
        Task.async(fn ->
          ExLLM.CircuitBreaker.call_with_bulkhead("queued", fn ->
            send(parent, {:started, 1})
            # Block for long enough to ensure second task gets queued
            Process.sleep(200)
            {:ok, 1}
          end)
        end)

      # Wait for first to start
      assert_receive {:started, 1}

      # Verify bulkhead is occupied
      metrics = ExLLM.CircuitBreaker.Bulkhead.get_metrics("queued")
      assert metrics.active_count == 1

      # Second request should queue
      task2 =
        Task.async(fn ->
          ExLLM.CircuitBreaker.call_with_bulkhead("queued", fn ->
            send(parent, {:started, 2})
            {:ok, 2}
          end)
        end)

      # Give time for queueing
      Process.sleep(10)

      # Verify task2 is queued
      metrics = ExLLM.CircuitBreaker.Bulkhead.get_metrics("queued")
      assert metrics.active_count == 1
      assert metrics.queued_count == 1

      # Second shouldn't start yet
      refute_receive {:started, 2}

      # First task will complete on its own after sleep

      # Wait for first to complete
      assert {:ok, 1} = Task.await(task1)

      # Second should now execute
      assert_receive {:started, 2}
      assert {:ok, 2} = Task.await(task2)
    end

    test "rejects requests when queue is full" do
      ExLLM.CircuitBreaker.Bulkhead.configure("full_queue",
        max_concurrent: 1,
        max_queued: 1,
        queue_timeout: 1000
      )

      parent = self()

      # Fill bulkhead with a blocking process
      _task1 =
        Task.async(fn ->
          ExLLM.CircuitBreaker.call_with_bulkhead("full_queue", fn ->
            send(parent, {:started, 1})
            # Block for longer to ensure it holds the bulkhead
            receive do
              :release -> :ok
            after
              2000 -> :timeout
            end
          end)
        end)

      assert_receive {:started, 1}

      # Fill queue (this will be queued)
      _task2 =
        Task.async(fn ->
          ExLLM.CircuitBreaker.call_with_bulkhead("full_queue", fn ->
            send(parent, {:started, 2})
            :ok
          end)
        end)

      # Give task2 time to get queued
      Process.sleep(10)

      # Verify that we have 1 active and 1 queued
      metrics = ExLLM.CircuitBreaker.Bulkhead.get_metrics("full_queue")
      assert metrics.active_count == 1
      assert metrics.queued_count == 1

      # This should be rejected (bulkhead full, queue full)
      result =
        ExLLM.CircuitBreaker.call_with_bulkhead("full_queue", fn ->
          send(parent, {:should_not_execute})
          :ok
        end)

      assert {:error, :bulkhead_queue_full} = result
      refute_receive {:should_not_execute}
    end

    test "times out queued requests" do
      ExLLM.CircuitBreaker.Bulkhead.configure("timeout_test",
        max_concurrent: 1,
        max_queued: 1,
        queue_timeout: 50
      )

      parent = self()

      # Hold bulkhead with a blocking process
      task1 =
        Task.async(fn ->
          ExLLM.CircuitBreaker.call_with_bulkhead("timeout_test", fn ->
            send(parent, {:task1_started})
            # Block forever until test finishes
            receive do
              :release -> :ok
            after
              5000 -> :timeout
            end
          end)
        end)

      # Wait for first task to actually start
      assert_receive {:task1_started}

      # Verify the bulkhead is actually occupied
      metrics = ExLLM.CircuitBreaker.Bulkhead.get_metrics("timeout_test")
      assert metrics.active_count == 1

      # This will queue and timeout
      result =
        ExLLM.CircuitBreaker.call_with_bulkhead("timeout_test", fn ->
          send(parent, {:should_not_execute})
          :should_not_execute
        end)

      assert {:error, :bulkhead_timeout} = result
      refute_receive {:should_not_execute}

      # Clean up - allow first task to finish
      Task.shutdown(task1, :brutal_kill)
    end
  end

  describe "bulkhead metrics" do
    test "tracks active and queued requests" do
      ExLLM.CircuitBreaker.Bulkhead.configure("metrics_test",
        max_concurrent: 2,
        max_queued: 5
      )

      parent = self()

      # Start concurrent requests
      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            ExLLM.CircuitBreaker.call_with_bulkhead("metrics_test", fn ->
              send(parent, {:started, i})
              Process.sleep(50)
              :ok
            end)
          end)
        end

      # Wait for some to start
      Process.sleep(10)

      metrics = ExLLM.CircuitBreaker.Bulkhead.get_metrics("metrics_test")

      assert metrics.active_count > 0
      assert metrics.queued_count >= 0
      assert metrics.total_accepted > 0
      assert metrics.total_rejected == 0

      # Wait for all to complete
      Enum.each(tasks, &Task.await/1)

      final_metrics = ExLLM.CircuitBreaker.Bulkhead.get_metrics("metrics_test")
      assert final_metrics.active_count == 0
      assert final_metrics.queued_count == 0
    end

    test "tracks rejection metrics" do
      ExLLM.CircuitBreaker.Bulkhead.configure("reject_metrics",
        max_concurrent: 1,
        max_queued: 0
      )

      # Fill bulkhead
      _task =
        Task.async(fn ->
          ExLLM.CircuitBreaker.call_with_bulkhead("reject_metrics", fn ->
            Process.sleep(50)
            :ok
          end)
        end)

      Process.sleep(10)

      # Attempt rejected call
      ExLLM.CircuitBreaker.call_with_bulkhead("reject_metrics", fn -> :ok end)

      metrics = ExLLM.CircuitBreaker.Bulkhead.get_metrics("reject_metrics")
      assert metrics.total_rejected > 0
    end
  end

  describe "integration with circuit breaker" do
    test "bulkhead works with circuit breaker states" do
      ExLLM.CircuitBreaker.Bulkhead.configure("integrated",
        max_concurrent: 2
      )

      # Circuit breaker + bulkhead
      result =
        ExLLM.CircuitBreaker.call_with_bulkhead("integrated", fn ->
          {:ok, "success"}
        end)

      assert {:ok, "success"} = result

      # Open circuit
      for _ <- 1..3 do
        ExLLM.CircuitBreaker.call(
          "integrated",
          fn ->
            raise "error"
          end,
          failure_threshold: 3
        )
      end

      # Bulkhead should still reject when circuit is open
      result =
        ExLLM.CircuitBreaker.call_with_bulkhead("integrated", fn ->
          :should_not_execute
        end)

      assert {:error, :circuit_open} = result
    end
  end

  describe "provider-specific bulkheads" do
    test "configures different limits per provider" do
      providers = %{
        openai: %{max_concurrent: 5, max_queued: 20},
        anthropic: %{max_concurrent: 3, max_queued: 10},
        groq: %{max_concurrent: 10, max_queued: 50}
      }

      Enum.each(providers, fn {provider, config} ->
        circuit = "#{provider}_circuit"
        ExLLM.CircuitBreaker.Bulkhead.configure(circuit, config)

        actual = ExLLM.CircuitBreaker.Bulkhead.get_config(circuit)
        assert actual.max_concurrent == config.max_concurrent
        assert actual.max_queued == config.max_queued
      end)
    end
  end
end
