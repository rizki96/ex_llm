defmodule ExLLM.Plugs.Providers.GroqPrepareListModelsRequest do
  @moduledoc """
  **DEPRECATED** - Use `ExLLM.Plugs.Providers.OpenAICompatiblePrepareListModelsRequest` instead.

  This module will be removed in v1.1.0. Please use the shared OpenAI-compatible
  implementation which provides the same functionality.
  """

  @deprecated "Use ExLLM.Plugs.Providers.OpenAICompatiblePrepareListModelsRequest instead"

  use ExLLM.Plug
  alias ExLLM.Plugs.Providers.OpenAICompatiblePrepareListModelsRequest

  @impl true
  defdelegate call(request, opts), to: OpenAICompatiblePrepareListModelsRequest
end
