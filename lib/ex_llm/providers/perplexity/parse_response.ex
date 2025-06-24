defmodule ExLLM.Providers.Perplexity.ParseResponse do
  @moduledoc """
  Pipeline plug for parsing Perplexity API responses.

  Perplexity follows OpenAI-compatible response format.
  """

  use ExLLM.Providers.OpenAICompatible.ParseResponse,
    provider: :perplexity,
    cost_provider: "perplexity"
end
