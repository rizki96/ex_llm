defmodule ExLLM.Providers.Groq.StreamParseResponse do
  @moduledoc """
  Stream response parser for Groq provider.

  Handles parsing of SSE (Server-Sent Events) chunks from Groq's streaming API.
  """
  use ExLLM.Providers.OpenAICompatible.StreamParseResponse, provider: :groq
end
