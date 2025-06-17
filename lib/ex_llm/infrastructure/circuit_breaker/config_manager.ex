defmodule ExLLM.Infrastructure.CircuitBreaker.ConfigManager do
  @moduledoc """
  Configuration management system for circuit breakers.

  Provides centralized configuration management with runtime updates,
  validation, rollback capabilities, and hot-reload functionality.

  ## Features

  - **Runtime Configuration Updates**: Change settings without restarts
  - **Configuration Validation**: Ensure settings are safe and valid
  - **Rollback Support**: Revert to previous configurations on failure
  - **Batch Operations**: Update multiple circuits simultaneously
  - **Configuration Profiles**: Pre-defined configuration sets
  - **Hot-reload**: Automatically apply configuration changes
  - **Audit Trail**: Track all configuration changes

  ## Configuration Profiles

  Built-in profiles for common scenarios:
  - `:conservative` - High fault tolerance, slow recovery
  - `:aggressive` - Low fault tolerance, fast recovery  
  - `:balanced` - Moderate settings for general use
  - `:high_throughput` - Optimized for high-volume services
  - `:experimental` - For testing and development

  ## Usage

      # Update individual circuit
      ExLLM.CircuitBreaker.ConfigManager.update_circuit("api_service", %{
        failure_threshold: 10,
        reset_timeout: 60_000
      })
      
      # Apply configuration profile
      ExLLM.CircuitBreaker.ConfigManager.apply_profile("api_service", :conservative)
      
      # Batch update multiple circuits
      ExLLM.CircuitBreaker.ConfigManager.batch_update(%{
        "service_1" => %{failure_threshold: 5},
        "service_2" => %{reset_timeout: 30_000}
      })
      
      # Rollback to previous configuration
      ExLLM.CircuitBreaker.ConfigManager.rollback("api_service")
  """

  use GenServer
  require Logger

  @table_name :ex_llm_circuit_breaker_configs
  @history_table :ex_llm_circuit_breaker_config_history

  # Configuration profiles for common scenarios
  @profiles %{
    conservative: %{
      failure_threshold: 10,
      success_threshold: 5,
      reset_timeout: 120_000,
      timeout: 60_000,
      bulkhead: %{
        max_concurrent: 5,
        max_queued: 20,
        queue_timeout: 10_000
      }
    },
    aggressive: %{
      failure_threshold: 3,
      success_threshold: 2,
      reset_timeout: 15_000,
      timeout: 10_000,
      bulkhead: %{
        max_concurrent: 20,
        max_queued: 100,
        queue_timeout: 2_000
      }
    },
    balanced: %{
      failure_threshold: 5,
      success_threshold: 3,
      reset_timeout: 30_000,
      timeout: 30_000,
      bulkhead: %{
        max_concurrent: 10,
        max_queued: 50,
        queue_timeout: 5_000
      }
    },
    high_throughput: %{
      failure_threshold: 8,
      success_threshold: 3,
      reset_timeout: 45_000,
      timeout: 20_000,
      bulkhead: %{
        max_concurrent: 50,
        max_queued: 200,
        queue_timeout: 1_000
      }
    },
    experimental: %{
      failure_threshold: 2,
      success_threshold: 1,
      reset_timeout: 5_000,
      timeout: 5_000,
      bulkhead: %{
        max_concurrent: 2,
        max_queued: 5,
        queue_timeout: 500
      }
    }
  }

  @default_config %{
    failure_threshold: 5,
    success_threshold: 3,
    reset_timeout: 30_000,
    timeout: 30_000,
    bulkhead: %{
      max_concurrent: 10,
      max_queued: 50,
      queue_timeout: 5_000
    }
  }

  defstruct [
    :circuit_name,
    :config,
    :profile,
    :created_at,
    :updated_at,
    :version
  ]

  ## Public API

  @doc """
  Start the configuration manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initialize the configuration management system.
  """
  def init_config_system do
    # Create ETS tables for configuration storage
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(@history_table, [
      :named_table,
      :public,
      :ordered_set,
      read_concurrency: true,
      write_concurrency: true
    ])

    Logger.info("Circuit breaker configuration system initialized")
  end

  @doc """
  Update configuration for a specific circuit.
  """
  @spec update_circuit(String.t(), map()) :: :ok | {:error, term()}
  def update_circuit(circuit_name, config_changes) do
    GenServer.call(__MODULE__, {:update_circuit, circuit_name, config_changes})
  end

  @doc """
  Apply a pre-defined configuration profile to a circuit.
  """
  @spec apply_profile(String.t(), atom()) :: :ok | {:error, term()}
  def apply_profile(circuit_name, profile_name) do
    case Map.get(@profiles, profile_name) do
      nil ->
        # Check if it's a custom profile
        GenServer.call(__MODULE__, {:apply_custom_profile, circuit_name, profile_name})

      profile_config ->
        # It's a built-in profile
        GenServer.call(__MODULE__, {:apply_profile, circuit_name, profile_name, profile_config})
    end
  end

  @doc """
  Batch update multiple circuits with different configurations.
  """
  @spec batch_update(map()) :: %{String.t() => :ok | {:error, term()}}
  def batch_update(circuit_configs) when is_map(circuit_configs) do
    GenServer.call(__MODULE__, {:batch_update, circuit_configs})
  end

  @doc """
  Get current configuration for a circuit.
  """
  @spec get_config(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_config(circuit_name) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, config_record}] ->
        {:ok, config_record.config}

      [] ->
        # Auto-create default configuration for new circuits
        {:ok, config_record} = get_or_create_config(circuit_name)
        {:ok, config_record.config}
    end
  end

  @doc """
  Get all circuit configurations.
  """
  @spec list_all_configs() :: [map()]
  def list_all_configs do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {circuit_name, config_record} ->
      %{
        circuit_name: circuit_name,
        config: config_record.config,
        profile: config_record.profile,
        updated_at: config_record.updated_at,
        version: config_record.version
      }
    end)
  end

  @doc """
  Rollback to the previous configuration for a circuit.
  """
  @spec rollback(String.t()) :: :ok | {:error, term()}
  def rollback(circuit_name) do
    GenServer.call(__MODULE__, {:rollback, circuit_name})
  end

  @doc """
  Get configuration history for a circuit.
  """
  @spec get_history(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def get_history(circuit_name, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    # Get entries for this circuit, ordered by timestamp (most recent first)
    entries =
      :ets.select(@history_table, [
        {{{circuit_name, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}
      ])
      |> Enum.sort(fn {ts1, _}, {ts2, _} -> ts1 >= ts2 end)
      |> Enum.take(limit)
      |> Enum.map(fn {_timestamp, record} -> record end)

    {:ok, entries}
  end

  @doc """
  Reset a circuit to default configuration.
  """
  @spec reset_to_default(String.t()) :: :ok | {:error, term()}
  def reset_to_default(circuit_name) do
    GenServer.call(__MODULE__, {:reset_to_default, circuit_name})
  end

  @doc """
  Validate a configuration map.
  """
  @spec validate_config(map() | keyword()) :: :ok | {:error, [atom()]}
  def validate_config(config) when is_list(config) do
    validate_config(Enum.into(config, %{}))
  end

  def validate_config(config) when is_map(config) do
    errors = []

    errors =
      if Map.has_key?(config, :failure_threshold) and config.failure_threshold <= 0 do
        [:invalid_failure_threshold | errors]
      else
        errors
      end

    errors =
      if Map.has_key?(config, :success_threshold) and config.success_threshold <= 0 do
        [:invalid_success_threshold | errors]
      else
        errors
      end

    errors =
      if Map.has_key?(config, :reset_timeout) and config.reset_timeout < 0 do
        [:invalid_reset_timeout | errors]
      else
        errors
      end

    errors =
      if Map.has_key?(config, :timeout) and config.timeout <= 0 do
        [:invalid_timeout | errors]
      else
        errors
      end

    # Validate bulkhead configuration if present
    errors =
      if Map.has_key?(config, :bulkhead) do
        validate_bulkhead_config(config.bulkhead) ++ errors
      else
        errors
      end

    case errors do
      [] -> :ok
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Get available configuration profiles.
  """
  @spec list_profiles() :: [atom()]
  def list_profiles do
    GenServer.call(__MODULE__, :list_profiles)
  end

  @doc """
  Get details of a specific profile.
  """
  @spec get_profile(atom()) :: {:ok, map()} | {:error, :not_found}
  def get_profile(profile_name) do
    case Map.get(@profiles, profile_name) do
      nil -> {:error, :not_found}
      config -> {:ok, config}
    end
  end

  @doc """
  Register a custom configuration profile.
  """
  @spec register_profile(atom(), map()) :: :ok | {:error, term()}
  def register_profile(profile_name, config) do
    GenServer.call(__MODULE__, {:register_profile, profile_name, config})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    init_config_system()
    {:ok, %{custom_profiles: %{}}}
  end

  @impl true
  def handle_call({:update_circuit, circuit_name, config_changes}, _from, state) do
    case do_update_circuit(circuit_name, config_changes) do
      :ok ->
        emit_telemetry(:config_updated, circuit_name, %{changes: config_changes})
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:apply_profile, circuit_name, profile_name, profile_config}, _from, state) do
    case do_apply_profile(circuit_name, profile_name, profile_config) do
      :ok ->
        emit_telemetry(:profile_applied, circuit_name, %{profile: profile_name})
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:apply_custom_profile, circuit_name, profile_name}, _from, state) do
    case Map.get(state.custom_profiles, profile_name) do
      nil ->
        {:reply, {:error, {:unknown_profile, profile_name}}, state}

      profile_config ->
        case do_apply_profile(circuit_name, profile_name, profile_config) do
          :ok ->
            emit_telemetry(:profile_applied, circuit_name, %{profile: profile_name})
            {:reply, :ok, state}

          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:batch_update, circuit_configs}, _from, state) do
    results = do_batch_update(circuit_configs)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:rollback, circuit_name}, _from, state) do
    case do_rollback(circuit_name) do
      :ok ->
        emit_telemetry(:config_rollback, circuit_name, %{})
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:reset_to_default, circuit_name}, _from, state) do
    case do_reset_to_default(circuit_name) do
      :ok ->
        emit_telemetry(:config_reset, circuit_name, %{})
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:register_profile, profile_name, config}, _from, state) do
    case validate_config(config) do
      :ok ->
        new_custom_profiles = Map.put(state.custom_profiles, profile_name, config)
        {:reply, :ok, %{state | custom_profiles: new_custom_profiles}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:list_profiles, _from, state) do
    built_in_profiles = Map.keys(@profiles)
    custom_profiles = Map.keys(state.custom_profiles)
    all_profiles = built_in_profiles ++ custom_profiles
    {:reply, all_profiles, state}
  end

  ## Private Implementation

  defp do_update_circuit(circuit_name, config_changes) do
    with :ok <- validate_config(config_changes),
         {:ok, current_config} <- get_or_create_config(circuit_name),
         new_config <- Map.merge(current_config.config, config_changes),
         :ok <- apply_config_to_circuit(circuit_name, new_config),
         :ok <- apply_bulkhead_config(circuit_name, new_config) do
      # Save configuration history
      save_config_history(circuit_name, current_config)

      # Update stored configuration
      updated_config = %{
        current_config
        | config: new_config,
          updated_at: DateTime.utc_now(),
          version: current_config.version + 1
      }

      :ets.insert(@table_name, {circuit_name, updated_config})

      Logger.info("Updated configuration for circuit #{circuit_name}")
      :ok
    else
      error -> error
    end
  end

  defp do_apply_profile(circuit_name, profile_name, profile_config) do
    with :ok <- validate_config(profile_config),
         {:ok, current_config} <- get_or_create_config(circuit_name),
         :ok <- apply_config_to_circuit(circuit_name, profile_config),
         :ok <- apply_bulkhead_config(circuit_name, profile_config) do
      # Save configuration history
      save_config_history(circuit_name, current_config)

      # Update stored configuration with profile info
      updated_config = %{
        current_config
        | config: profile_config,
          profile: profile_name,
          updated_at: DateTime.utc_now(),
          version: current_config.version + 1
      }

      :ets.insert(@table_name, {circuit_name, updated_config})

      Logger.info("Applied profile #{profile_name} to circuit #{circuit_name}")
      :ok
    else
      error -> error
    end
  end

  defp do_batch_update(circuit_configs) do
    circuit_configs
    |> Enum.map(fn {circuit_name, config_changes} ->
      {circuit_name, do_update_circuit(circuit_name, config_changes)}
    end)
    |> Map.new()
  end

  defp do_rollback(circuit_name) do
    case get_previous_config(circuit_name) do
      {:ok, previous_config} ->
        with :ok <- apply_config_to_circuit(circuit_name, previous_config.config),
             :ok <- apply_bulkhead_config(circuit_name, previous_config.config) do
          # Update current config to the previous one
          rolled_back_config = %{
            previous_config
            | updated_at: DateTime.utc_now(),
              version: previous_config.version + 1
          }

          :ets.insert(@table_name, {circuit_name, rolled_back_config})

          Logger.info("Rolled back configuration for circuit #{circuit_name}")
          :ok
        end

      error ->
        error
    end
  end

  defp do_reset_to_default(circuit_name) do
    with {:ok, current_config} <- get_or_create_config(circuit_name),
         :ok <- apply_config_to_circuit(circuit_name, @default_config),
         :ok <- apply_bulkhead_config(circuit_name, @default_config) do
      # Save current config to history
      save_config_history(circuit_name, current_config)

      # Reset to default
      default_config_record = %__MODULE__{
        circuit_name: circuit_name,
        config: @default_config,
        profile: :default,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        version: current_config.version + 1
      }

      :ets.insert(@table_name, {circuit_name, default_config_record})

      Logger.info("Reset circuit #{circuit_name} to default configuration")
      :ok
    else
      error -> error
    end
  end

  defp get_or_create_config(circuit_name) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, config_record}] ->
        {:ok, config_record}

      [] ->
        # Create default configuration
        config_record = %__MODULE__{
          circuit_name: circuit_name,
          config: @default_config,
          profile: :default,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          version: 1
        }

        :ets.insert(@table_name, {circuit_name, config_record})
        {:ok, config_record}
    end
  end

  defp apply_config_to_circuit(circuit_name, config) do
    # Extract circuit breaker specific config
    cb_config =
      Map.take(config, [:failure_threshold, :success_threshold, :reset_timeout, :timeout])

    # First ensure the circuit exists by attempting a dummy call
    ExLLM.Infrastructure.CircuitBreaker.call(circuit_name, fn -> :dummy end, cb_config)

    # Then update the configuration
    ExLLM.Infrastructure.CircuitBreaker.update_config(circuit_name, cb_config)
  end

  defp apply_bulkhead_config(circuit_name, config) do
    if Map.has_key?(config, :bulkhead) do
      ExLLM.Infrastructure.CircuitBreaker.Bulkhead.configure(circuit_name, config.bulkhead)
    else
      :ok
    end
  end

  defp save_config_history(circuit_name, config_record) do
    timestamp = :os.system_time(:microsecond)
    history_key = {circuit_name, timestamp}

    history_record = %{
      circuit_name: circuit_name,
      config: config_record.config,
      profile: config_record.profile,
      saved_at: DateTime.utc_now(),
      version: config_record.version
    }

    :ets.insert(@history_table, {history_key, history_record})
    :ok
  end

  defp get_previous_config(circuit_name) do
    # Get the most recent history entry for this circuit
    case :ets.select(@history_table, [
           {{{circuit_name, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}
         ]) do
      [] ->
        {:error, :no_history}

      entries ->
        # Get the most recent entry
        {_timestamp, previous_config} =
          entries
          |> Enum.sort(fn {ts1, _}, {ts2, _} -> ts1 >= ts2 end)
          |> List.first()

        {:ok,
         %__MODULE__{
           circuit_name: previous_config.circuit_name,
           config: previous_config.config,
           profile: previous_config.profile,
           created_at: previous_config.saved_at,
           updated_at: previous_config.saved_at,
           version: previous_config.version
         }}
    end
  end

  defp validate_bulkhead_config(bulkhead_config) do
    errors = []

    errors =
      if Map.has_key?(bulkhead_config, :max_concurrent) and bulkhead_config.max_concurrent <= 0 do
        [:invalid_max_concurrent | errors]
      else
        errors
      end

    errors =
      if Map.has_key?(bulkhead_config, :max_queued) and bulkhead_config.max_queued < 0 do
        [:invalid_max_queued | errors]
      else
        errors
      end

    errors =
      if Map.has_key?(bulkhead_config, :queue_timeout) and bulkhead_config.queue_timeout <= 0 do
        [:invalid_queue_timeout | errors]
      else
        errors
      end

    errors
  end

  defp emit_telemetry(event, circuit_name, metadata) do
    :telemetry.execute(
      [:ex_llm, :circuit_breaker, :config_manager, event],
      %{count: 1},
      Map.merge(%{circuit_name: circuit_name}, metadata)
    )
  end
end
