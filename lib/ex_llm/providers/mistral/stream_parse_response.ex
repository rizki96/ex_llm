defmodule ExLLM.Providers.Mistral.StreamParseResponse do
  @moduledoc """
  Stream response parser for Mistral provider.

  Handles parsing of SSE (Server-Sent Events) chunks from Mistral's streaming API.
  """
  use ExLLM.Providers.OpenAICompatible.StreamParseResponse, provider: :mistral
end
