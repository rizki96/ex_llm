defmodule ExLLM.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Start StreamRecovery for all adapters
        ExLLM.StreamRecovery,
        # Start Cache if enabled
        cache_child_spec()
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
