defmodule ExLLM.Plugs.Providers.OpenAIPrepareListModelsRequest do
  @moduledoc """
  Prepares list models request for the OpenAI API.

  Sets up the request path for retrieving available models.
  """

  use ExLLM.Plug

  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    # OpenAI's models endpoint doesn't require a body
    request
    |> Map.put(:provider_request, %{})
    |> ExLLM.Pipeline.Request.assign(:http_method, :get)
    |> ExLLM.Pipeline.Request.assign(:http_path, "/models")
  end
end
