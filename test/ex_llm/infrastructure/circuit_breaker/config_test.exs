defmodule ExLLM.Infrastructure.CircuitBreaker.ConfigTest do
  use ExUnit.Case, async: false

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
    ExLLM.Infrastructure.CircuitBreaker.init()
    ExLLM.Infrastructure.CircuitBreaker.Bulkhead.init()

    # Start configuration manager
    case ExLLM.Infrastructure.CircuitBreaker.ConfigManager.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  defp cleanup_processes do
    processes_to_stop = [
      ExLLM.Infrastructure.CircuitBreaker.Bulkhead.Registry,
      ExLLM.Infrastructure.CircuitBreaker.Bulkhead.Supervisor,
      ExLLM.Infrastructure.CircuitBreaker.ConfigManager
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

  describe "configuration management" do
    test "updates circuit configuration at runtime" do
      # Create circuit with initial config
      ExLLM.Infrastructure.CircuitBreaker.call("config_test", fn -> :ok end,
        failure_threshold: 5,
        reset_timeout: 30_000
      )

      {:ok, initial} = ExLLM.Infrastructure.CircuitBreaker.get_stats("config_test")
      assert initial.config.failure_threshold == 5
      assert initial.config.reset_timeout == 30_000

      # Update configuration
      :ok =
        ExLLM.Infrastructure.CircuitBreaker.update_config("config_test",
          failure_threshold: 10,
          reset_timeout: 60_000
        )

      {:ok, updated} = ExLLM.Infrastructure.CircuitBreaker.get_stats("config_test")
      assert updated.config.failure_threshold == 10
      assert updated.config.reset_timeout == 60_000
    end

    test "emits telemetry event on config update" do
      test_pid = self()

      :telemetry.attach(
        "config_update_test",
        [:ex_llm, :circuit_breaker, :config_updated],
        fn event, _measurements, metadata, _config ->
          send(test_pid, {:config_updated, event, metadata})
        end,
        nil
      )

      # Create and update circuit
      ExLLM.Infrastructure.CircuitBreaker.call("telemetry_config", fn -> :ok end)

      ExLLM.Infrastructure.CircuitBreaker.update_config("telemetry_config",
        failure_threshold: 7
      )

      assert_receive {:config_updated, [:ex_llm, :circuit_breaker, :config_updated],
                      %{circuit_name: "telemetry_config", config: config}}

      assert config.failure_threshold == 7

      :telemetry.detach("config_update_test")
    end

    test "validates configuration values" do
      ExLLM.Infrastructure.CircuitBreaker.call("validation_test", fn -> :ok end)

      # Invalid failure threshold
      assert {:error, {:invalid_config, :failure_threshold}} =
               ExLLM.Infrastructure.CircuitBreaker.update_config("validation_test",
                 failure_threshold: 0
               )

      # Invalid reset timeout
      assert {:error, {:invalid_config, :reset_timeout}} =
               ExLLM.Infrastructure.CircuitBreaker.update_config("validation_test",
                 reset_timeout: -1000
               )

      # Invalid success threshold
      assert {:error, {:invalid_config, :success_threshold}} =
               ExLLM.Infrastructure.CircuitBreaker.update_config("validation_test",
                 success_threshold: 0
               )
    end

    test "preserves state during config update" do
      # Create circuit with some failures
      for _ <- 1..2 do
        ExLLM.Infrastructure.CircuitBreaker.call(
          "state_preserve",
          fn ->
            raise "error"
          end,
          failure_threshold: 5
        )
      end

      {:ok, before} = ExLLM.Infrastructure.CircuitBreaker.get_stats("state_preserve")
      assert before.failure_count == 2
      assert before.state == :closed

      # Update config
      ExLLM.Infrastructure.CircuitBreaker.update_config("state_preserve",
        failure_threshold: 10
      )

      {:ok, after_update} = ExLLM.Infrastructure.CircuitBreaker.get_stats("state_preserve")
      assert after_update.failure_count == 2
      assert after_update.state == :closed
      assert after_update.config.failure_threshold == 10
    end
  end

  describe "batch configuration" do
    test "updates multiple circuits at once" do
      # Create multiple circuits
      circuits = ["batch1", "batch2", "batch3"]

      Enum.each(circuits, fn circuit ->
        ExLLM.Infrastructure.CircuitBreaker.call(circuit, fn -> :ok end)
      end)

      # Batch update
      results =
        ExLLM.Infrastructure.CircuitBreaker.batch_update_config(circuits,
          failure_threshold: 8,
          reset_timeout: 45_000
        )

      assert map_size(results) == 3

      Enum.each(results, fn {circuit, result} ->
        assert result == :ok
        {:ok, stats} = ExLLM.Infrastructure.CircuitBreaker.get_stats(circuit)
        assert stats.config.failure_threshold == 8
        assert stats.config.reset_timeout == 45_000
      end)
    end

    test "handles partial failures in batch update" do
      # Create some circuits
      ExLLM.Infrastructure.CircuitBreaker.call("exists1", fn -> :ok end)
      ExLLM.Infrastructure.CircuitBreaker.call("exists2", fn -> :ok end)

      results =
        ExLLM.Infrastructure.CircuitBreaker.batch_update_config(
          ["exists1", "exists2", "not_exists"],
          failure_threshold: 6
        )

      assert results["exists1"] == :ok
      assert results["exists2"] == :ok
      assert {:error, :circuit_not_found} = results["not_exists"]
    end
  end

  describe "configuration presets" do
    test "applies provider-specific presets" do
      presets = %{
        strict: %{failure_threshold: 3, reset_timeout: 60_000},
        normal: %{failure_threshold: 5, reset_timeout: 30_000},
        lenient: %{failure_threshold: 10, reset_timeout: 15_000}
      }

      # Register presets
      Enum.each(presets, fn {name, config} ->
        ExLLM.Infrastructure.CircuitBreaker.Config.register_preset(name, config)
      end)

      # Apply preset to circuit
      ExLLM.Infrastructure.CircuitBreaker.call("preset_test", fn -> :ok end)
      :ok = ExLLM.Infrastructure.CircuitBreaker.Config.apply_preset("preset_test", :strict)

      {:ok, stats} = ExLLM.Infrastructure.CircuitBreaker.get_stats("preset_test")
      assert stats.config.failure_threshold == 3
      assert stats.config.reset_timeout == 60_000
    end

    test "lists available presets" do
      ExLLM.Infrastructure.CircuitBreaker.Config.register_preset(:fast_fail,
        failure_threshold: 1,
        reset_timeout: 5_000
      )

      presets = ExLLM.Infrastructure.CircuitBreaker.Config.list_presets()
      assert :fast_fail in presets
    end
  end

  describe "dynamic configuration" do
    test "supports configuration functions" do
      # Config function based on time of day
      dynamic_config = fn ->
        hour = DateTime.utc_now().hour

        if hour >= 9 and hour <= 17 do
          # Business hours - stricter
          %{failure_threshold: 3}
        else
          # Off hours - more lenient
          %{failure_threshold: 10}
        end
      end

      ExLLM.Infrastructure.CircuitBreaker.call("dynamic", fn -> :ok end)
      ExLLM.Infrastructure.CircuitBreaker.Config.set_dynamic("dynamic", dynamic_config)

      # Apply dynamic config
      ExLLM.Infrastructure.CircuitBreaker.Config.refresh_dynamic("dynamic")

      {:ok, stats} = ExLLM.Infrastructure.CircuitBreaker.get_stats("dynamic")
      assert stats.config.failure_threshold in [3, 10]
    end

    test "refreshes all dynamic configs" do
      test_pid = self()

      dynamic1 = fn ->
        send(test_pid, :dynamic1_called)
        %{failure_threshold: 4}
      end

      dynamic2 = fn ->
        send(test_pid, :dynamic2_called)
        %{failure_threshold: 6}
      end

      ExLLM.Infrastructure.CircuitBreaker.call("dyn1", fn -> :ok end)
      ExLLM.Infrastructure.CircuitBreaker.call("dyn2", fn -> :ok end)

      ExLLM.Infrastructure.CircuitBreaker.Config.set_dynamic("dyn1", dynamic1)
      ExLLM.Infrastructure.CircuitBreaker.Config.set_dynamic("dyn2", dynamic2)

      ExLLM.Infrastructure.CircuitBreaker.Config.refresh_all_dynamic()

      assert_receive :dynamic1_called
      assert_receive :dynamic2_called
    end
  end

  describe "configuration export/import" do
    test "exports circuit configurations" do
      # Create circuits with different configs
      ExLLM.Infrastructure.CircuitBreaker.call("export1", fn -> :ok end,
        failure_threshold: 4,
        reset_timeout: 20_000
      )

      ExLLM.Infrastructure.CircuitBreaker.call("export2", fn -> :ok end,
        failure_threshold: 6,
        reset_timeout: 40_000
      )

      exported = ExLLM.Infrastructure.CircuitBreaker.Config.export_all()

      assert exported["export1"].failure_threshold == 4
      assert exported["export1"].reset_timeout == 20_000
      assert exported["export2"].failure_threshold == 6
      assert exported["export2"].reset_timeout == 40_000
    end

    test "imports circuit configurations" do
      config_data = %{
        "import1" => %{failure_threshold: 7, reset_timeout: 25_000},
        "import2" => %{failure_threshold: 9, reset_timeout: 35_000}
      }

      # Import configs (creates circuits if needed)
      results = ExLLM.Infrastructure.CircuitBreaker.Config.import_all(config_data)

      assert results["import1"] == :ok
      assert results["import2"] == :ok

      # Verify imported configs
      {:ok, stats1} = ExLLM.Infrastructure.CircuitBreaker.get_stats("import1")
      assert stats1.config.failure_threshold == 7

      {:ok, stats2} = ExLLM.Infrastructure.CircuitBreaker.get_stats("import2")
      assert stats2.config.failure_threshold == 9
    end
  end
end
