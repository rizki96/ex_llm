defmodule ExLLM.Providers.Ollama.BuildRequest do
  @moduledoc """
  Pipeline plug for building Ollama API requests.

  Ollama follows OpenAI-compatible format.
  """

  use ExLLM.Providers.OpenAICompatible.BuildRequest,
    provider: :ollama,
    base_url_env: "OLLAMA_API_BASE",
    default_base_url: "http://localhost:11434/v1",
    api_key_env: "OLLAMA_API_KEY"
end
