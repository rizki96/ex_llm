defmodule ExLLM.Providers.Perplexity.BuildRequest do
  @moduledoc """
  Pipeline plug for building Perplexity API requests.

  Perplexity follows OpenAI-compatible format.
  """

  use ExLLM.Providers.OpenAICompatible.BuildRequest,
    provider: :perplexity,
    base_url_env: "PERPLEXITY_API_BASE",
    default_base_url: "https://api.perplexity.ai",
    api_key_env: "PERPLEXITY_API_KEY"
end
