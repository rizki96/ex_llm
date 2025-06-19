defmodule ExLLM.Plugs.Providers.OpenRouterPrepareListModelsRequest do
  @moduledoc """
  Prepares the list models request for OpenRouter.

  OpenRouter uses a similar endpoint to OpenAI but provides additional 
  metadata and supports models from multiple providers.
  """

  use ExLLM.Plug

  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    # OpenRouter's models endpoint doesn't require a body (similar to OpenAI)
    request
    |> Map.put(:provider_request, %{})
    |> ExLLM.Pipeline.Request.assign(:http_method, :get)
    |> ExLLM.Pipeline.Request.assign(:http_path, "/models")
  end
end
