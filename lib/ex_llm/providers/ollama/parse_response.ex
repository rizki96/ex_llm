defmodule ExLLM.Providers.Ollama.ParseResponse do
  @moduledoc """
  Pipeline plug for parsing Ollama API responses.

  Ollama follows OpenAI-compatible response format.
  """

  use ExLLM.Providers.OpenAICompatible.ParseResponse,
    provider: :ollama,
    cost_provider: "ollama"
end
