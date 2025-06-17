defmodule ExLLM.Infrastructure.CircuitBreaker.Bulkhead do
  @moduledoc """
  Bulkhead pattern implementation for circuit breaker concurrency limiting.

  The bulkhead pattern isolates resources by limiting the number of concurrent
  requests to prevent cascading failures and resource exhaustion.

  ## Features

  - **Concurrency limiting**: Enforce maximum concurrent requests per circuit
  - **Request queuing**: Queue requests when bulkhead is full
  - **Timeout handling**: Timeout queued requests after configurable period
  - **Metrics tracking**: Monitor active, queued, and rejected requests
  - **Provider-specific limits**: Different limits per provider/circuit
  - **Integration**: Works seamlessly with circuit breaker states

  ## Configuration

  - `max_concurrent`: Maximum concurrent requests (default: 10)
  - `max_queued`: Maximum queued requests (default: 50)
  - `queue_timeout`: Queue timeout in milliseconds (default: 5000)

  ## Usage

      # Configure bulkhead for a circuit
      ExLLM.Infrastructure.CircuitBreaker.Bulkhead.configure("api_circuit",
        max_concurrent: 5,
        max_queued: 20,
        queue_timeout: 3000
      )
      
      # Execute with bulkhead protection
      ExLLM.Infrastructure.CircuitBreaker.call_with_bulkhead("api_circuit", fn ->
        # Your API call here
        HTTPClient.get("/api/data")
      end)
  """

  require Logger

  alias ExLLM.Infrastructure.CircuitBreaker.BulkheadWorker

  # Registry name for this bulkhead system
  @registry_name __MODULE__.Registry

  # DynamicSupervisor name for this bulkhead system
  @supervisor_name __MODULE__.Supervisor

  # Default configuration
  @default_config %{
    max_concurrent: 10,
    max_queued: 50,
    queue_timeout: 5000
  }

  ## Public API

  @doc """
  Initialize the bulkhead system.
  """
  def init do
    # Start the Registry for worker name lookup
    case Process.whereis(@registry_name) do
      nil ->
        case Registry.start_link(keys: :unique, name: @registry_name) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

      _ ->
        :ok
    end

    # Start the DynamicSupervisor for worker management  
    case Process.whereis(@supervisor_name) do
      nil ->
        case DynamicSupervisor.start_link(name: @supervisor_name, strategy: :one_for_one) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Configure bulkhead settings for a circuit.
  """
  def configure(circuit_name, opts) do
    config = Map.merge(@default_config, Map.new(opts))

    case find_worker(circuit_name) do
      {:ok, pid} ->
        # Update existing worker configuration
        BulkheadWorker.update_config(pid, config)

      {:error, :not_found} ->
        # Start new worker
        case DynamicSupervisor.start_child(
               @supervisor_name,
               {BulkheadWorker, [circuit_config: {circuit_name, config}]}
             ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Get bulkhead configuration for a circuit.
  """
  def get_config(circuit_name) do
    case find_worker(circuit_name) do
      {:ok, pid} ->
        metrics = BulkheadWorker.get_metrics(pid)
        metrics.config

      {:error, :not_found} ->
        @default_config
    end
  end

  @doc """
  Get bulkhead metrics for a circuit.
  """
  def get_metrics(circuit_name) do
    case find_worker(circuit_name) do
      {:ok, pid} ->
        BulkheadWorker.get_metrics(pid)

      {:error, :not_found} ->
        %{
          active_count: 0,
          queued_count: 0,
          total_accepted: 0,
          total_rejected: 0,
          total_timeouts: 0,
          config: @default_config
        }
    end
  end

  @doc """
  Execute a function with bulkhead protection.

  This is the main entry point that combines circuit breaker and bulkhead logic.
  """
  def execute(circuit_name, fun, opts \\ []) when is_function(fun, 0) do
    # First check circuit breaker state
    case ExLLM.Infrastructure.CircuitBreaker.get_stats(circuit_name) do
      {:ok, stats} when stats.state == :open ->
        {:error, :circuit_open}

      _ ->
        # Circuit is closed or half-open, proceed with bulkhead
        execute_with_bulkhead(circuit_name, fun, opts)
    end
  end

  ## Private Implementation

  defp execute_with_bulkhead(circuit_name, fun, opts) do
    timeout = Keyword.get(opts, :queue_timeout, @default_config.queue_timeout)

    case find_or_start_worker(circuit_name) do
      {:ok, pid} ->
        BulkheadWorker.execute(pid, fun, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_or_start_worker(circuit_name) do
    case find_worker(circuit_name) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, :not_found} ->
        # Worker doesn't exist, create it with default config
        case configure(circuit_name, []) do
          :ok -> find_worker(circuit_name)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp find_worker(circuit_name) do
    case Registry.lookup(@registry_name, circuit_name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
