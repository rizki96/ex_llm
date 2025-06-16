defmodule ExLLM.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize circuit breaker ETS table
    ExLLM.CircuitBreaker.init()

    # Initialize metrics system
    ExLLM.CircuitBreaker.Metrics.setup()

    children =
      [
        # Start StreamRecovery for all adapters
        ExLLM.StreamRecovery,
        # Start Cache if enabled
        cache_child_spec(),
        # Start Circuit Breaker Configuration Manager
        ExLLM.CircuitBreaker.ConfigManager,
        # Start Circuit Breaker Metrics system if enabled
        metrics_child_spec()
      ]
      |> Enum.filter(& &1)

    # Only start ModelLoader if Bumblebee is available and not in test env
    # Check if we're in test mode by looking for ExUnit
    in_test = Code.ensure_loaded?(ExUnit)

    children =
      if Code.ensure_loaded?(Bumblebee) and not in_test do
        children ++ [ExLLM.Bumblebee.ModelLoader]
      else
        children
      end

    opts = [strategy: :one_for_one, name: ExLLM.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp cache_child_spec do
    if Application.get_env(:ex_llm, :cache_enabled, false) do
      ExLLM.Cache
    else
      nil
    end
  end

  defp metrics_child_spec do
    config = Application.get_env(:ex_llm, :circuit_breaker_metrics, [])

    if Keyword.get(config, :enabled, false) and :statsd in Keyword.get(config, :backends, []) do
      ExLLM.CircuitBreaker.Metrics.StatsDReporter
    else
      nil
    end
  end

  defp env do
    # Check if we're in escript mode by checking if Mix is available
    if Code.ensure_loaded?(Mix) do
      Mix.env()
    else
      # Default to :prod when Mix is not available (escript mode)
      :prod
    end
  end
end
