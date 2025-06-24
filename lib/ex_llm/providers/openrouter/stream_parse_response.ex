defmodule ExLLM.Providers.OpenRouter.StreamParseResponse do
  @moduledoc """
  Stream response parser for OpenRouter provider.

  Handles parsing of SSE (Server-Sent Events) chunks from OpenRouter's streaming API.
  """
  use ExLLM.Providers.OpenAICompatible.StreamParseResponse, provider: :openrouter
end
