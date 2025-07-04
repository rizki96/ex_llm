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

  @behaviour Tesla.Middleware

  alias ExLLM.Infrastructure.CircuitBreaker
  alias ExLLM.Infrastructure.Logger

  # @impl Tesla.Middleware  
  def call(env, next, opts) do
    circuit_name = opts[:name] || raise ArgumentError, "circuit breaker name is required"
    _provider = opts[:provider]
    timeout = opts[:timeout]

    # Build circuit breaker options
    cb_opts = []
    cb_opts = if timeout, do: [{:timeout, timeout} | cb_opts], else: cb_opts

    Logger.debug(
      "CircuitBreaker middleware: circuit_name=#{circuit_name}, timeout=#{inspect(timeout)}, cb_opts=#{inspect(cb_opts)}"
    )

    # Execute the request through the circuit breaker and return result as-is
    # CircuitBreaker.call already returns the correct {:ok, Tesla.Env} or {:error, reason} format
    CircuitBreaker.call(circuit_name, fn -> Tesla.run(env, next) end, cb_opts)
  end
end
