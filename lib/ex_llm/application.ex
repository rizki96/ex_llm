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

    # Only start ModelLoader if Bumblebee is available
    children =
      if Code.ensure_loaded?(Bumblebee) do
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
end
