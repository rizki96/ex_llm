defmodule ExLLM.Plugs.Providers.AnthropicStaticModelsList do
  @moduledoc """
  Returns a static list of Anthropic models since they don't have a models API.
  
  This list is manually maintained and should be updated when Anthropic releases new models.
  """
  
  use ExLLM.Plug
  
  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    models = [
      %{
        id: "claude-3-5-sonnet-20241022",
        name: "Claude 3.5 Sonnet",
        context_window: 200000,
        max_output_tokens: 8192,
        capabilities: ["chat", "vision", "function_calling"],
        pricing: %{
          input: 0.003,
          output: 0.015
        }
      },
      %{
        id: "claude-3-5-haiku-20241022",
        name: "Claude 3.5 Haiku",
        context_window: 200000,
        max_output_tokens: 8192,
        capabilities: ["chat", "vision"],
        pricing: %{
          input: 0.0008,
          output: 0.004
        }
      },
      %{
        id: "claude-3-opus-20240229",
        name: "Claude 3 Opus",
        context_window: 200000,
        max_output_tokens: 4096,
        capabilities: ["chat", "vision", "function_calling"],
        pricing: %{
          input: 0.015,
          output: 0.075
        }
      },
      %{
        id: "claude-3-sonnet-20240229",
        name: "Claude 3 Sonnet",
        context_window: 200000,
        max_output_tokens: 4096,
        capabilities: ["chat", "vision", "function_calling"],
        pricing: %{
          input: 0.003,
          output: 0.015
        }
      },
      %{
        id: "claude-3-haiku-20240307",
        name: "Claude 3 Haiku",
        context_window: 200000,
        max_output_tokens: 4096,
        capabilities: ["chat", "vision"],
        pricing: %{
          input: 0.00025,
          output: 0.00125
        }
      }
    ]
    
    request
    |> Map.put(:result, models)
    |> ExLLM.Pipeline.Request.put_state(:completed)
  end
end