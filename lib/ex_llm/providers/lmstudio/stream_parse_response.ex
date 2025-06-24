defmodule ExLLM.Providers.LMStudio.StreamParseResponse do
  @moduledoc """
  Stream response parser for LM Studio provider.

  Handles parsing of SSE (Server-Sent Events) chunks from LM Studio's streaming API.
  """
  use ExLLM.Providers.OpenAICompatible.StreamParseResponse, provider: :lmstudio
end
