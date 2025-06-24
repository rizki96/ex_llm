defmodule ExLLM.Providers.XAI.BuildRequest do
  @moduledoc """
  Pipeline plug for building XAI (Grok) API requests.

  XAI follows OpenAI-compatible format.
  """

  use ExLLM.Providers.OpenAICompatible.BuildRequest,
    provider: :xai,
    base_url_env: "XAI_API_BASE",
    default_base_url: "https://api.x.ai/v1",
    api_key_env: "XAI_API_KEY"
end
