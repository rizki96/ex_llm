defmodule ExLLM.Providers.LMStudio.ParseResponse do
  @moduledoc """
  Pipeline plug for parsing LMStudio API responses.

  LMStudio follows OpenAI-compatible response format.
  """

  use ExLLM.Providers.OpenAICompatible.ParseResponse,
    provider: :lmstudio,
    cost_provider: "lmstudio"
end
