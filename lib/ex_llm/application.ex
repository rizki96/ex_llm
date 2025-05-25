defmodule ExLLM.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    # Only start ModelLoader if Bumblebee is available
    children =
      if Code.ensure_loaded?(Bumblebee) do
        children ++ [ExLLM.Local.ModelLoader]
      else
        children
      end

    opts = [strategy: :one_for_one, name: ExLLM.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
