defmodule ExLLM.Plugs.Providers.UnsupportedListModels do
  @moduledoc """
  Plug that returns an error for providers that don't support listing models.
  """

  use ExLLM.Plug

  @impl true
  def call(%ExLLM.Pipeline.Request{provider: provider} = request, _opts) do
    ExLLM.Pipeline.Request.halt_with_error(request, %{
      error: :list_models_not_supported,
      message: "Provider #{provider} does not support listing models",
      plug: __MODULE__
    })
  end
end
