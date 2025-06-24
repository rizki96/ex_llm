defmodule ExLLM.Providers.OpenRouter.ParseResponse do
  @moduledoc """
  Pipeline plug for parsing OpenRouter API responses.

  OpenRouter follows OpenAI-compatible response format.
  """

  use ExLLM.Providers.OpenAICompatible.ParseResponse,
    provider: :openrouter,
    cost_provider: "openrouter"
end
