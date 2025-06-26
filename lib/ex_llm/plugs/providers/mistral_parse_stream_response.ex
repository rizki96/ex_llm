defmodule ExLLM.Plugs.Providers.MistralParseStreamResponse do
  @moduledoc """
  Parses streaming responses from Mistral API.

  This plug sets up chunk parsing for Server-Sent Events (SSE) format
  used by Mistral's OpenAI-compatible API. It replaces the legacy
  StreamParseResponse module with the modern HTTP.Core-based approach.
  """

  use ExLLM.Plug
  alias ExLLM.Plugs.Providers.OpenAIParseStreamResponse

  @impl true
  def call(request, opts) do
    # Mistral uses OpenAI-compatible format, so delegate to OpenAI parser
    OpenAIParseStreamResponse.call(request, opts)
  end
end
