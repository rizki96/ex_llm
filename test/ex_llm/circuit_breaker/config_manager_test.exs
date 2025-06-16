defmodule ExLLM.CircuitBreaker.ConfigManagerTest do
  use ExUnit.Case, async: false

  alias ExLLM.CircuitBreaker
  alias ExLLM.CircuitBreaker.ConfigManager

  setup do
    # Clean up ETS tables
    tables_to_clean = [
      :ex_llm_circuit_breakers,
      :ex_llm_circuit_breaker_configs,
      :ex_llm_circuit_breaker_config_history,
      :ex_llm_circuit_breaker_bulkheads
    ]

    Enum.each(tables_to_clean, fn table ->
      if :ets.info(table) != :undefined do
        :ets.delete(table)
      end
    end)

    # Clean up any existing processes
    cleanup_processes()

    # Initialize systems
    CircuitBreaker.init()
    ExLLM.CircuitBreaker.Bulkhead.init()

    # Start configuration manager
    {:ok, _pid} = ConfigManager.start_link()

    :ok
  end

  defp cleanup_processes do
    processes_to_stop = [
      ExLLM.CircuitBreaker.Bulkhead.Registry,
      ExLLM.CircuitBreaker.Bulkhead.Supervisor,
      ExLLM.CircuitBreaker.ConfigManager
    ]

    Enum.each(processes_to_stop, fn process_name ->
      if pid = Process.whereis(process_name) do
        try do
          GenServer.stop(pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    # Give processes time to shut down
    Process.sleep(10)
  end

  describe "configuration initialization" do
    test "creates ETS tables for configuration storage" do
      assert :ets.info(:ex_llm_circuit_breaker_configs) != :undefined
      assert :ets.info(:ex_llm_circuit_breaker_config_history) != :undefined
    end

    test "provides default configuration for new circuits" do
      assert {:ok, config} = ConfigManager.get_config("new_circuit")

      assert config.failure_threshold == 5
      assert config.success_threshold == 3
      assert config.reset_timeout == 30_000
      assert config.timeout == 30_000
      assert config.bulkhead.max_concurrent == 10
      assert config.bulkhead.max_queued == 50
      assert config.bulkhead.queue_timeout == 5_000
    end
  end

  describe "configuration updates" do
    test "updates circuit configuration successfully" do
      circuit_name = "test_circuit"

      # Update configuration
      new_config = %{
        failure_threshold: 10,
        reset_timeout: 60_000
      }

      assert :ok = ConfigManager.update_circuit(circuit_name, new_config)

      # Verify configuration was updated
      {:ok, config} = ConfigManager.get_config(circuit_name)
      assert config.failure_threshold == 10
      assert config.reset_timeout == 60_000
      # Other values should remain default
      assert config.success_threshold == 3
      assert config.timeout == 30_000
    end

    test "validates configuration before applying" do
      circuit_name = "validation_test"

      # Invalid configuration should be rejected
      invalid_config = %{
        failure_threshold: -1,
        success_threshold: 0
      }

      assert {:error, errors} = ConfigManager.update_circuit(circuit_name, invalid_config)
      assert :invalid_failure_threshold in errors
      assert :invalid_success_threshold in errors
    end

    test "updates both circuit breaker and bulkhead configuration" do
      circuit_name = "full_config_test"

      new_config = %{
        failure_threshold: 8,
        bulkhead: %{
          max_concurrent: 20,
          max_queued: 100
        }
      }

      assert :ok = ConfigManager.update_circuit(circuit_name, new_config)

      # Verify circuit breaker configuration
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.config.failure_threshold == 8

      # Verify bulkhead configuration
      bulkhead_config = ExLLM.CircuitBreaker.Bulkhead.get_config(circuit_name)
      assert bulkhead_config.max_concurrent == 20
      assert bulkhead_config.max_queued == 100
    end

    test "maintains configuration version history" do
      circuit_name = "version_test"

      # Initial update
      ConfigManager.update_circuit(circuit_name, %{failure_threshold: 3})

      # Second update
      ConfigManager.update_circuit(circuit_name, %{failure_threshold: 7})

      # Check version incremented
      configs = ConfigManager.list_all_configs()
      circuit_config = Enum.find(configs, fn c -> c.circuit_name == circuit_name end)
      # Default creation (1) + 2 updates
      assert circuit_config.version == 3

      # Check history exists
      {:ok, history} = ConfigManager.get_history(circuit_name)
      # Two previous versions saved
      assert length(history) == 2
    end
  end

  describe "configuration profiles" do
    test "lists available profiles" do
      profiles = ConfigManager.list_profiles()

      expected_profiles = [:conservative, :aggressive, :balanced, :high_throughput, :experimental]

      Enum.each(expected_profiles, fn profile ->
        assert profile in profiles
      end)
    end

    test "gets profile details" do
      {:ok, conservative_config} = ConfigManager.get_profile(:conservative)

      assert conservative_config.failure_threshold == 10
      assert conservative_config.success_threshold == 5
      assert conservative_config.reset_timeout == 120_000
    end

    test "applies profile to circuit" do
      circuit_name = "profile_test"

      assert :ok = ConfigManager.apply_profile(circuit_name, :aggressive)

      {:ok, config} = ConfigManager.get_config(circuit_name)

      assert config.failure_threshold == 3
      assert config.success_threshold == 2
      assert config.reset_timeout == 15_000
      assert config.bulkhead.max_concurrent == 20
      assert config.bulkhead.max_queued == 100
    end

    test "rejects unknown profiles" do
      circuit_name = "unknown_profile_test"

      assert {:error, {:unknown_profile, :nonexistent}} =
               ConfigManager.apply_profile(circuit_name, :nonexistent)
    end

    test "registers custom profile" do
      custom_config = %{
        failure_threshold: 12,
        success_threshold: 4,
        reset_timeout: 90_000,
        timeout: 45_000,
        bulkhead: %{
          max_concurrent: 15,
          max_queued: 75,
          queue_timeout: 7_500
        }
      }

      assert :ok = ConfigManager.register_profile(:custom_test, custom_config)

      # Apply the custom profile
      circuit_name = "custom_profile_test"
      assert :ok = ConfigManager.apply_profile(circuit_name, :custom_test)

      {:ok, config} = ConfigManager.get_config(circuit_name)
      assert config.failure_threshold == 12
      assert config.bulkhead.max_concurrent == 15
    end
  end

  describe "batch operations" do
    test "updates multiple circuits simultaneously" do
      circuit_configs = %{
        "circuit_1" => %{failure_threshold: 8},
        "circuit_2" => %{reset_timeout: 45_000},
        "circuit_3" => %{bulkhead: %{max_concurrent: 25}}
      }

      results = ConfigManager.batch_update(circuit_configs)

      # All updates should succeed
      assert results["circuit_1"] == :ok
      assert results["circuit_2"] == :ok
      assert results["circuit_3"] == :ok

      # Verify configurations
      {:ok, config1} = ConfigManager.get_config("circuit_1")
      assert config1.failure_threshold == 8

      {:ok, config2} = ConfigManager.get_config("circuit_2")
      assert config2.reset_timeout == 45_000

      {:ok, config3} = ConfigManager.get_config("circuit_3")
      assert config3.bulkhead.max_concurrent == 25
    end

    test "handles partial failures in batch operations" do
      circuit_configs = %{
        "valid_circuit" => %{failure_threshold: 6},
        # Invalid
        "invalid_circuit" => %{failure_threshold: -1}
      }

      results = ConfigManager.batch_update(circuit_configs)

      assert results["valid_circuit"] == :ok
      assert {:error, _} = results["invalid_circuit"]
    end
  end

  describe "configuration rollback" do
    test "rolls back to previous configuration" do
      circuit_name = "rollback_test"

      # Initial configuration
      ConfigManager.update_circuit(circuit_name, %{failure_threshold: 5})

      # Update configuration
      ConfigManager.update_circuit(circuit_name, %{failure_threshold: 10})

      # Verify current configuration
      {:ok, config} = ConfigManager.get_config(circuit_name)
      assert config.failure_threshold == 10

      # Rollback
      assert :ok = ConfigManager.rollback(circuit_name)

      # Verify rollback worked
      {:ok, rolled_back_config} = ConfigManager.get_config(circuit_name)
      assert rolled_back_config.failure_threshold == 5
    end

    test "handles rollback when no history exists" do
      circuit_name = "no_history_rollback"

      # Try to rollback a circuit with no history
      assert {:error, :no_history} = ConfigManager.rollback(circuit_name)
    end
  end

  describe "configuration reset" do
    test "resets circuit to default configuration" do
      circuit_name = "reset_test"

      # Apply custom configuration
      ConfigManager.update_circuit(circuit_name, %{
        failure_threshold: 15,
        reset_timeout: 120_000,
        bulkhead: %{max_concurrent: 30}
      })

      # Reset to default
      assert :ok = ConfigManager.reset_to_default(circuit_name)

      # Verify reset worked
      {:ok, config} = ConfigManager.get_config(circuit_name)
      # Default
      assert config.failure_threshold == 5
      # Default
      assert config.reset_timeout == 30_000
      # Default
      assert config.bulkhead.max_concurrent == 10
    end
  end

  describe "configuration listing and inspection" do
    test "lists all circuit configurations" do
      # Create some circuits with different configurations
      ConfigManager.update_circuit("circuit_1", %{failure_threshold: 3})
      ConfigManager.apply_profile("circuit_2", :conservative)
      ConfigManager.update_circuit("circuit_3", %{reset_timeout: 60_000})

      configs = ConfigManager.list_all_configs()

      assert length(configs) == 3

      # Check that each circuit is represented
      circuit_names = Enum.map(configs, & &1.circuit_name)
      assert "circuit_1" in circuit_names
      assert "circuit_2" in circuit_names
      assert "circuit_3" in circuit_names

      # Check profile information
      circuit_2_config = Enum.find(configs, fn c -> c.circuit_name == "circuit_2" end)
      assert circuit_2_config.profile == :conservative
    end

    test "gets configuration history with limit" do
      circuit_name = "history_limit_test"

      # Create multiple configuration changes
      for threshold <- 1..15 do
        ConfigManager.update_circuit(circuit_name, %{failure_threshold: threshold})
      end

      # Get limited history
      {:ok, history} = ConfigManager.get_history(circuit_name, limit: 5)
      assert length(history) == 5

      # Get all history
      {:ok, full_history} = ConfigManager.get_history(circuit_name, limit: 100)
      assert length(full_history) == 15
    end
  end

  describe "configuration validation" do
    test "validates complete configuration" do
      valid_config = %{
        failure_threshold: 5,
        success_threshold: 3,
        reset_timeout: 30_000,
        timeout: 15_000,
        bulkhead: %{
          max_concurrent: 10,
          max_queued: 50,
          queue_timeout: 5_000
        }
      }

      assert :ok = ConfigManager.validate_config(valid_config)
    end

    test "catches multiple validation errors" do
      invalid_config = %{
        failure_threshold: -1,
        success_threshold: 0,
        reset_timeout: -500,
        timeout: 0,
        bulkhead: %{
          max_concurrent: -5,
          max_queued: -10,
          queue_timeout: 0
        }
      }

      assert {:error, errors} = ConfigManager.validate_config(invalid_config)

      expected_errors = [
        :invalid_failure_threshold,
        :invalid_success_threshold,
        :invalid_reset_timeout,
        :invalid_timeout,
        :invalid_max_concurrent,
        :invalid_max_queued,
        :invalid_queue_timeout
      ]

      Enum.each(expected_errors, fn error ->
        assert error in errors
      end)
    end
  end

  describe "integration with circuit breaker system" do
    test "configuration changes affect circuit behavior" do
      circuit_name = "behavior_test"

      # Configure circuit with low failure threshold
      ConfigManager.update_circuit(circuit_name, %{failure_threshold: 2})

      # Trigger failures to open circuit
      CircuitBreaker.call(circuit_name, fn -> raise "error" end)
      CircuitBreaker.call(circuit_name, fn -> raise "error" end)

      # Circuit should now be open
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.state == :open

      # Update configuration to higher threshold and reset
      ConfigManager.update_circuit(circuit_name, %{failure_threshold: 10})
      CircuitBreaker.reset(circuit_name)

      # Circuit should handle more failures now
      CircuitBreaker.call(circuit_name, fn -> raise "error" end)
      CircuitBreaker.call(circuit_name, fn -> raise "error" end)
      CircuitBreaker.call(circuit_name, fn -> raise "error" end)

      # Should still be closed due to higher threshold
      {:ok, stats} = CircuitBreaker.get_stats(circuit_name)
      assert stats.state == :closed
    end

    test "bulkhead configuration changes affect concurrency" do
      circuit_name = "bulkhead_behavior_test"

      # Configure with very low concurrency
      ConfigManager.update_circuit(circuit_name, %{
        bulkhead: %{max_concurrent: 1, max_queued: 0}
      })

      parent = self()

      # Start a long-running task
      task1 =
        Task.async(fn ->
          ExLLM.CircuitBreaker.call_with_bulkhead(circuit_name, fn ->
            send(parent, :task1_started)
            Process.sleep(100)
            :ok
          end)
        end)

      # Wait for first task to start
      assert_receive :task1_started

      # Second task should be rejected due to low concurrency
      result =
        ExLLM.CircuitBreaker.call_with_bulkhead(circuit_name, fn ->
          :should_not_execute
        end)

      assert {:error, :bulkhead_full} = result

      # Update to higher concurrency
      ConfigManager.update_circuit(circuit_name, %{
        bulkhead: %{max_concurrent: 5, max_queued: 10}
      })

      # Wait for first task to complete
      Task.await(task1)

      # Now multiple tasks should be able to run
      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            ExLLM.CircuitBreaker.call_with_bulkhead(circuit_name, fn ->
              Process.sleep(10)
              {:ok, i}
            end)
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      Enum.each(results, fn result ->
        assert {:ok, _} = result
      end)
    end
  end
end
