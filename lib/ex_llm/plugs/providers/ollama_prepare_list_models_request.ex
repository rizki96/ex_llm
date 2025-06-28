defmodule ExLLM.Plugs.Providers.OllamaPrepareListModelsRequest do
  @moduledoc """
  Prepares list models request for the Ollama API.

  Sets up the request path for retrieving locally available models.
  """

  use ExLLM.Plug

  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    # Ollama's list endpoint shows locally available models
    request
    |> Map.put(:provider_request, %{})
    |> ExLLM.Pipeline.Request.assign(:http_method, :get)
    |> ExLLM.Pipeline.Request.assign(:http_path, "/api/tags")
  end
end
