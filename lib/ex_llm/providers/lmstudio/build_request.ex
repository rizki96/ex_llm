defmodule ExLLM.Providers.LMStudio.BuildRequest do
  @moduledoc """
  Pipeline plug for building LMStudio API requests.

  LMStudio follows OpenAI-compatible format.
  """

  use ExLLM.Providers.OpenAICompatible.BuildRequest,
    provider: :lmstudio,
    base_url_env: "LMSTUDIO_API_BASE",
    default_base_url: "http://localhost:1234/v1",
    api_key_env: "LMSTUDIO_API_KEY"
end
