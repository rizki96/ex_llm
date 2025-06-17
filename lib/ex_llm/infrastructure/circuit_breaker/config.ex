defmodule ExLLM.Infrastructure.CircuitBreaker.Config do
  @moduledoc """
  Public API for circuit breaker configuration management.

  This module provides a simplified interface to the ConfigManager,
  with convenience functions for common operations.
  """

  alias ExLLM.Infrastructure.CircuitBreaker.ConfigManager

  @doc """
  Register a configuration preset.

  ## Parameters
  - `name` - Preset name (atom)
  - `config` - Configuration map or keyword list

  ## Examples

      Config.register_preset(:fast_fail, failure_threshold: 1, reset_timeout: 5_000)
  """
  def register_preset(name, config) when is_atom(name) do
    ConfigManager.register_profile(name, config)
  end

  @doc """
  Apply a preset to a circuit.

  ## Parameters
  - `circuit_name` - Circuit identifier
  - `preset_name` - Preset to apply

  ## Examples

      Config.apply_preset("my_circuit", :fast_fail)
  """
  def apply_preset(circuit_name, preset_name) do
    ConfigManager.apply_profile(circuit_name, preset_name)
  end

  @doc """
  List all available presets.

  ## Returns
  List of preset names (atoms).

  ## Examples

      [:fast_fail, :conservative, :default] = Config.list_presets()
  """
  def list_presets do
    ConfigManager.list_profiles()
  end

  @doc """
  Set dynamic configuration for a circuit.

  ## Parameters
  - `circuit_name` - Circuit identifier
  - `config_fn` - Function that returns configuration based on current state

  ## Examples

      Config.set_dynamic("api_circuit", fn _state ->
        if :rand.uniform() > 0.5 do
          %{failure_threshold: 3, reset_timeout: 30_000}
        else
          %{failure_threshold: 5, reset_timeout: 60_000}
        end
      end)
  """
  def set_dynamic(circuit_name, config_fn) when is_function(config_fn, 0) do
    # Store the dynamic config function
    # For now, just apply it immediately - this could be enhanced
    # to store the function for periodic refresh
    current_config = config_fn.()
    ConfigManager.update_circuit(circuit_name, current_config)
  end

  def set_dynamic(circuit_name, config_fn) when is_function(config_fn, 1) do
    # Store the dynamic config function
    # For now, just apply it immediately - this could be enhanced
    # to store the function for periodic refresh
    current_config = config_fn.(%{})
    ConfigManager.update_circuit(circuit_name, current_config)
  end

  @doc """
  Refresh dynamic configuration for a circuit.

  ## Parameters
  - `circuit_name` - Circuit identifier

  ## Examples

      Config.refresh_dynamic("api_circuit")
  """
  def refresh_dynamic(circuit_name) do
    # For now, this is a no-op since we don't store dynamic functions
    # In a full implementation, this would re-evaluate stored functions
    {:ok, _config} = ConfigManager.get_config(circuit_name)
    :ok
  end

  @doc """
  Refresh all dynamic configurations.

  ## Examples

      Config.refresh_all_dynamic()
  """
  def refresh_all_dynamic do
    # For now, this is a no-op since we don't store dynamic functions
    :ok
  end

  @doc """
  Export all circuit configurations.

  ## Returns
  Map of circuit configurations.

  ## Examples

      configs = Config.export_all()
  """
  def export_all do
    # Get all circuits from the CircuitBreaker's ETS table
    table_name = :ex_llm_circuit_breakers

    case :ets.info(table_name) do
      :undefined ->
        %{}

      _ ->
        :ets.tab2list(table_name)
        |> Enum.map(fn {circuit_name, circuit_state} ->
          {circuit_name, circuit_state.config}
        end)
        |> Map.new()
    end
  end

  @doc """
  Import circuit configurations.

  ## Parameters
  - `config_data` - Map of circuit configurations

  ## Returns
  Map of import results.

  ## Examples

      results = Config.import_all(exported_configs)
  """
  def import_all(config_data) when is_map(config_data) do
    config_data
    |> Enum.map(fn {circuit_name, circuit_config} ->
      # First ensure the circuit exists by creating it with a dummy call
      ExLLM.Infrastructure.CircuitBreaker.call(circuit_name, fn -> :ok end, circuit_config)

      # Return the result
      {circuit_name, :ok}
    end)
    |> Map.new()
  end

  @doc """
  Get configuration for a circuit.

  ## Parameters
  - `circuit_name` - Circuit identifier

  ## Returns
  `{:ok, config}` or `{:error, reason}`.
  """
  def get_config(circuit_name) do
    ConfigManager.get_config(circuit_name)
  end

  @doc """
  Update circuit configuration.

  ## Parameters
  - `circuit_name` - Circuit identifier
  - `config_changes` - Configuration changes to apply

  ## Returns
  `:ok` or `{:error, reason}`.
  """
  def update_circuit(circuit_name, config_changes) do
    ConfigManager.update_circuit(circuit_name, config_changes)
  end

  @doc """
  Reset circuit to default configuration.

  ## Parameters
  - `circuit_name` - Circuit identifier

  ## Returns
  `:ok` or `{:error, reason}`.
  """
  def reset_to_default(circuit_name) do
    ConfigManager.reset_to_default(circuit_name)
  end

  @doc """
  Rollback circuit configuration.

  ## Parameters
  - `circuit_name` - Circuit identifier

  ## Returns
  `:ok` or `{:error, reason}`.
  """
  def rollback(circuit_name) do
    ConfigManager.rollback(circuit_name)
  end
end
