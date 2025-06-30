defmodule ExLLM.Tesla.Middleware.CircuitBreaker do
  @moduledoc """
  Tesla middleware that integrates with ExLLM's circuit breaker infrastructure.

  This middleware wraps HTTP requests with circuit breaker protection, preventing
  cascading failures when a provider is experiencing issues.

  ## Options

    * `:name` - The circuit breaker name (required)
    * `:provider` - The provider atom for metrics (optional)
    * `:timeout` - Override circuit breaker timeout (optional)
    
  ## Examples

      plug ExLLM.Tesla.Middleware.CircuitBreaker,
        name: "openai_circuit",
        provider: :openai
  """

  # @behaviour Tesla.Middleware  # Commented to avoid dialyzer callback_info_missing warnings

  alias ExLLM.Infrastructure.CircuitBreaker
  alias ExLLM.Infrastructure.Logger

  # @impl Tesla.Middleware  
  def call(env, next, opts) do
    circuit_name = opts[:name] || raise ArgumentError, "circuit breaker name is required"
    provider = opts[:provider]
    timeout = opts[:timeout]

    # Build circuit breaker options
    cb_opts = []
    cb_opts = if timeout, do: [{:timeout, timeout} | cb_opts], else: cb_opts

    Logger.debug(
      "CircuitBreaker middleware: circuit_name=#{circuit_name}, timeout=#{inspect(timeout)}, cb_opts=#{inspect(cb_opts)}"
    )

    # Execute the request through the circuit breaker
    case CircuitBreaker.call(circuit_name, fn -> Tesla.run(env, next) end, cb_opts) do
      {:ok, result} ->
        # Circuit breaker succeeded, return the result
        result

      {:error, :circuit_open} ->
        # Circuit is open, return a standardized error
        {:error, build_circuit_open_error(provider)}

      {:error, :timeout} ->
        # Circuit breaker timeout
        {:error, :circuit_breaker_timeout}

      {:error, reason} ->
        # Other circuit breaker errors
        Logger.warning("Circuit breaker error for #{circuit_name}: #{inspect(reason)}")
        {:error, {:circuit_breaker_error, reason}}
    end
  end

  defp build_circuit_open_error(provider) do
    %{
      reason: :circuit_open,
      message: "Circuit breaker is open for provider #{provider}. Too many recent failures.",
      provider: provider,
      retry_after: calculate_retry_after()
    }
  end

  defp calculate_retry_after do
    # Simple exponential backoff hint
    # In a real implementation, this would check the circuit breaker's state
    60
  end
end
