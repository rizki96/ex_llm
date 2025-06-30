defmodule ExLLM.Plugs.Providers.PerplexityPrepareListModelsRequest do
  @moduledoc """
  Prepares list models request for Perplexity API.

  Perplexity uses the /models endpoint without the /v1 prefix.
  """

  use ExLLM.Plug

  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    request
    |> Map.put(:provider_request, %{})
    |> ExLLM.Pipeline.Request.assign(:http_method, :get)
    # No /v1 prefix
    |> ExLLM.Pipeline.Request.assign(:http_path, "/models")
  end
end
