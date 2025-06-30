defmodule ExLLM.Plugs.Providers.OpenAICompatiblePrepareListModelsRequest do
  @moduledoc """
  Shared preparation for list models requests for OpenAI-compatible providers.

  This plug provides common functionality for providers that follow OpenAI's
  API format for listing models:
  - OpenAI
  - Groq  
  - OpenRouter
  - Mistral (when compatible)
  - XAI (when compatible)
  - LM Studio

  All these providers use the same pattern:
  - GET request to /models endpoint
  - No request body required
  - Standard OpenAI-format response
  """

  use ExLLM.Plug

  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    # OpenAI-compatible providers don't require a body for list models
    request
    |> Map.put(:provider_request, %{})
    |> ExLLM.Pipeline.Request.assign(:http_method, :get)
    |> ExLLM.Pipeline.Request.assign(:http_path, "/v1/models")
  end
end
