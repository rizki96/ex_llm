defmodule ExLLM.Providers.XAI.StreamParseResponse do
  @moduledoc """
  Stream response parser for xAI provider.

  Handles parsing of SSE (Server-Sent Events) chunks from xAI's streaming API.
  """
  use ExLLM.Providers.OpenAICompatible.StreamParseResponse, provider: :xai
end
