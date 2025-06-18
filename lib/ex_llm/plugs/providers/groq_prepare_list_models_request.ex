defmodule ExLLM.Plugs.Providers.GroqPrepareListModelsRequest do
  @moduledoc """
  Prepares list models request for the Groq API.

  Sets up the request path for retrieving available models.
  """

  use ExLLM.Plug

  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    # Groq's models endpoint follows OpenAI's format
    request
    |> Map.put(:provider_request, %{})
    |> ExLLM.Pipeline.Request.assign(:http_method, :get)
    |> ExLLM.Pipeline.Request.assign(:http_path, "/models")
  end
end
