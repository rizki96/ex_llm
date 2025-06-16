defmodule Mix.Tasks.ExLlm.Config do
  @moduledoc """
  Circuit breaker configuration management tasks.

  ## Available commands:

      mix ex_llm.config list                    # List all circuit configurations
      mix ex_llm.config show CIRCUIT           # Show specific circuit configuration
      mix ex_llm.config update CIRCUIT KEY=VALUE [KEY=VALUE ...]  # Update circuit configuration
      mix ex_llm.config profile CIRCUIT PROFILE  # Apply configuration profile
      mix ex_llm.config reset CIRCUIT          # Reset circuit to default configuration
      mix ex_llm.config rollback CIRCUIT       # Rollback to previous configuration
      mix ex_llm.config history CIRCUIT        # Show configuration history
      mix ex_llm.config profiles               # List available profiles
      mix ex_llm.config validate CONFIG_JSON   # Validate configuration

  ## Examples:

      # List all circuits and their configurations
      mix ex_llm.config list
      
      # Show configuration for specific circuit
      mix ex_llm.config show api_service
      
      # Update circuit configuration
      mix ex_llm.config update api_service failure_threshold=10 reset_timeout=60000
      
      # Apply conservative profile
      mix ex_llm.config profile api_service conservative
      
      # Reset to defaults
      mix ex_llm.config reset api_service
      
      # Show configuration history
      mix ex_llm.config history api_service
      
      # List available profiles
      mix ex_llm.config profiles
      
      # Validate configuration JSON
      mix ex_llm.config validate '{"failure_threshold": 5, "timeout": 30000}'
  """

  use Mix.Task

  alias ExLLM.CircuitBreaker.ConfigManager

  @shortdoc "Manage circuit breaker configurations"

  def run([]), do: run(["help"])

  def run(["help"]) do
    Mix.shell().info(@moduledoc)
  end

  def run(["list"]) do
    ensure_app_started()

    configs = ConfigManager.list_all_configs()

    if Enum.empty?(configs) do
      Mix.shell().info("No circuit configurations found.")
    else
      Mix.shell().info("Circuit Configurations:")
      Mix.shell().info("")

      Enum.each(configs, fn config ->
        Mix.shell().info("#{config.circuit_name}:")
        Mix.shell().info("  Profile: #{config.profile || "custom"}")
        Mix.shell().info("  Version: #{config.version}")
        Mix.shell().info("  Updated: #{format_datetime(config.updated_at)}")
        Mix.shell().info("  Failure Threshold: #{config.config.failure_threshold}")
        Mix.shell().info("  Success Threshold: #{config.config.success_threshold}")
        Mix.shell().info("  Reset Timeout: #{config.config.reset_timeout}ms")
        Mix.shell().info("  Request Timeout: #{config.config.timeout}ms")

        if Map.has_key?(config.config, :bulkhead) do
          bulkhead = config.config.bulkhead
          Mix.shell().info("  Bulkhead:")
          Mix.shell().info("    Max Concurrent: #{bulkhead.max_concurrent}")
          Mix.shell().info("    Max Queued: #{bulkhead.max_queued}")
          Mix.shell().info("    Queue Timeout: #{bulkhead.queue_timeout}ms")
        end

        Mix.shell().info("")
      end)
    end
  end

  def run(["show", circuit_name]) do
    ensure_app_started()

    case ConfigManager.get_config(circuit_name) do
      {:ok, config} ->
        Mix.shell().info("Configuration for circuit '#{circuit_name}':")
        print_config(config)

      {:error, :not_found} ->
        Mix.shell().error("Circuit '#{circuit_name}' not found.")
        exit({:shutdown, 1})
    end
  end

  def run(["update", circuit_name | config_pairs]) do
    ensure_app_started()

    config_changes = parse_config_pairs(config_pairs)

    case ConfigManager.update_circuit(circuit_name, config_changes) do
      :ok ->
        Mix.shell().info("Successfully updated configuration for circuit '#{circuit_name}'.")

        {:ok, updated_config} = ConfigManager.get_config(circuit_name)
        Mix.shell().info("New configuration:")
        print_config(updated_config)

      {:error, errors} when is_list(errors) ->
        Mix.shell().error("Configuration validation failed:")

        Enum.each(errors, fn error ->
          Mix.shell().error("  - #{format_error(error)}")
        end)

        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Failed to update configuration: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  def run(["profile", circuit_name, profile_name]) do
    ensure_app_started()

    profile_atom = String.to_atom(profile_name)

    case ConfigManager.apply_profile(circuit_name, profile_atom) do
      :ok ->
        Mix.shell().info(
          "Successfully applied profile '#{profile_name}' to circuit '#{circuit_name}'."
        )

        {:ok, updated_config} = ConfigManager.get_config(circuit_name)
        Mix.shell().info("New configuration:")
        print_config(updated_config)

      {:error, {:unknown_profile, _}} ->
        Mix.shell().error("Unknown profile '#{profile_name}'.")
        Mix.shell().info("Available profiles:")

        Enum.each(ConfigManager.list_profiles(), fn profile ->
          Mix.shell().info("  - #{profile}")
        end)

        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Failed to apply profile: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  def run(["reset", circuit_name]) do
    ensure_app_started()

    case ConfigManager.reset_to_default(circuit_name) do
      :ok ->
        Mix.shell().info("Successfully reset circuit '#{circuit_name}' to default configuration.")

        {:ok, default_config} = ConfigManager.get_config(circuit_name)
        Mix.shell().info("Default configuration:")
        print_config(default_config)

      {:error, reason} ->
        Mix.shell().error("Failed to reset configuration: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  def run(["rollback", circuit_name]) do
    ensure_app_started()

    case ConfigManager.rollback(circuit_name) do
      :ok ->
        Mix.shell().info("Successfully rolled back configuration for circuit '#{circuit_name}'.")

        {:ok, rolled_back_config} = ConfigManager.get_config(circuit_name)
        Mix.shell().info("Rolled back configuration:")
        print_config(rolled_back_config)

      {:error, :no_history} ->
        Mix.shell().error("No configuration history found for circuit '#{circuit_name}'.")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Failed to rollback configuration: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  def run(["history", circuit_name]) do
    ensure_app_started()

    case ConfigManager.get_history(circuit_name, limit: 20) do
      {:ok, []} ->
        Mix.shell().info("No configuration history found for circuit '#{circuit_name}'.")

      {:ok, history} ->
        Mix.shell().info("Configuration history for circuit '#{circuit_name}':")
        Mix.shell().info("")

        Enum.with_index(history, 1)
        |> Enum.each(fn {entry, index} ->
          Mix.shell().info("#{index}. Version #{entry.version} (#{entry.profile || "custom"})")
          Mix.shell().info("   Saved: #{format_datetime(entry.saved_at)}")
          Mix.shell().info("   Failure Threshold: #{entry.config.failure_threshold}")
          Mix.shell().info("   Reset Timeout: #{entry.config.reset_timeout}ms")
          Mix.shell().info("")
        end)

      {:error, reason} ->
        Mix.shell().error("Failed to get history: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  def run(["profiles"]) do
    ensure_app_started()

    Mix.shell().info("Available configuration profiles:")
    Mix.shell().info("")

    Enum.each(ConfigManager.list_profiles(), fn profile ->
      case ConfigManager.get_profile(profile) do
        {:ok, config} ->
          Mix.shell().info("#{profile}:")
          Mix.shell().info("  Failure Threshold: #{config.failure_threshold}")
          Mix.shell().info("  Success Threshold: #{config.success_threshold}")
          Mix.shell().info("  Reset Timeout: #{config.reset_timeout}ms")
          Mix.shell().info("  Request Timeout: #{config.timeout}ms")

          if Map.has_key?(config, :bulkhead) do
            bulkhead = config.bulkhead

            Mix.shell().info(
              "  Bulkhead - Max Concurrent: #{bulkhead.max_concurrent}, Max Queued: #{bulkhead.max_queued}"
            )
          end

          Mix.shell().info("")

        {:error, _} ->
          Mix.shell().info("#{profile}: (details unavailable)")
          Mix.shell().info("")
      end
    end)
  end

  def run(["validate", config_json]) do
    case Jason.decode(config_json) do
      {:ok, config_map} ->
        config_atoms = convert_keys_to_atoms(config_map)

        case ConfigManager.validate_config(config_atoms) do
          :ok ->
            Mix.shell().info("✓ Configuration is valid.")

          {:error, errors} ->
            Mix.shell().error("✗ Configuration validation failed:")

            Enum.each(errors, fn error ->
              Mix.shell().error("  - #{format_error(error)}")
            end)

            exit({:shutdown, 1})
        end

      {:error, reason} ->
        Mix.shell().error("Invalid JSON: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  def run([command | _]) do
    Mix.shell().error("Unknown command: #{command}")
    Mix.shell().info("Run 'mix ex_llm.config help' for usage information.")
    exit({:shutdown, 1})
  end

  ## Private Helpers

  defp ensure_app_started do
    {:ok, _} = Application.ensure_all_started(:ex_llm)
  end

  defp parse_config_pairs(pairs) do
    Enum.reduce(pairs, %{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] ->
          parsed_value = parse_value(value)
          atom_key = String.to_atom(key)
          Map.put(acc, atom_key, parsed_value)

        _ ->
          Mix.shell().error("Invalid config pair: #{pair}")
          Mix.shell().info("Format: key=value")
          exit({:shutdown, 1})
      end
    end)
  end

  defp parse_value(value) do
    cond do
      # Try to parse as integer
      Regex.match?(~r/^\d+$/, value) ->
        String.to_integer(value)

      # Try to parse as float
      Regex.match?(~r/^\d+\.\d+$/, value) ->
        String.to_float(value)

      # Try to parse as boolean
      value in ["true", "false"] ->
        String.to_atom(value)

      # Keep as string
      true ->
        value
    end
  end

  defp print_config(config) do
    Mix.shell().info("  Failure Threshold: #{config.failure_threshold}")
    Mix.shell().info("  Success Threshold: #{config.success_threshold}")
    Mix.shell().info("  Reset Timeout: #{config.reset_timeout}ms")
    Mix.shell().info("  Request Timeout: #{config.timeout}ms")

    if Map.has_key?(config, :bulkhead) do
      bulkhead = config.bulkhead
      Mix.shell().info("  Bulkhead:")
      Mix.shell().info("    Max Concurrent: #{bulkhead.max_concurrent}")
      Mix.shell().info("    Max Queued: #{bulkhead.max_queued}")
      Mix.shell().info("    Queue Timeout: #{bulkhead.queue_timeout}ms")
    end
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_error(:invalid_failure_threshold), do: "failure_threshold must be positive"
  defp format_error(:invalid_success_threshold), do: "success_threshold must be positive"
  defp format_error(:invalid_reset_timeout), do: "reset_timeout must be non-negative"
  defp format_error(:invalid_timeout), do: "timeout must be positive"
  defp format_error(:invalid_max_concurrent), do: "bulkhead max_concurrent must be positive"
  defp format_error(:invalid_max_queued), do: "bulkhead max_queued must be non-negative"
  defp format_error(:invalid_queue_timeout), do: "bulkhead queue_timeout must be positive"
  defp format_error(error), do: "#{error}"

  defp convert_keys_to_atoms(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {String.to_atom(k), convert_keys_to_atoms(v)} end)
    |> Map.new()
  end

  defp convert_keys_to_atoms(value), do: value
end
