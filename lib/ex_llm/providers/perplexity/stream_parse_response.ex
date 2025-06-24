defmodule ExLLM.Providers.Perplexity.StreamParseResponse do
  @moduledoc """
  Stream response parser for Perplexity provider.

  Handles parsing of SSE (Server-Sent Events) chunks from Perplexity's streaming API.
  """
  use ExLLM.Providers.OpenAICompatible.StreamParseResponse, provider: :perplexity
end
