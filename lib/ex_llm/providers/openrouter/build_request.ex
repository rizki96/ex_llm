defmodule ExLLM.Providers.OpenRouter.BuildRequest do
  @moduledoc """
  Pipeline plug for building OpenRouter API requests.

  OpenRouter follows OpenAI-compatible format.
  """

  use ExLLM.Providers.OpenAICompatible.BuildRequest,
    provider: :openrouter,
    base_url_env: "OPENROUTER_API_BASE",
    default_base_url: "https://openrouter.ai/api",
    api_key_env: "OPENROUTER_API_KEY"
end
