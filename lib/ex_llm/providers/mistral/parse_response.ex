defmodule ExLLM.Providers.Mistral.ParseResponse do
  @moduledoc """
  Pipeline plug for parsing Mistral API responses.

  Mistral follows OpenAI-compatible response format.
  """

  use ExLLM.Providers.OpenAICompatible.ParseResponse,
    provider: :mistral,
    cost_provider: "mistral"
end
