defmodule ExLLM.Plugs.Providers.AnthropicStaticModelsList do
  @moduledoc """
  Returns a static list of Anthropic models since they don't have a models API.

  This list is manually maintained and should be updated when Anthropic releases new models.
  """

  use ExLLM.Plug
  alias ExLLM.Types.Model

  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    models = [
      %Model{
        id: "claude-3-5-sonnet-20241022",
        name: "Claude 3.5 Sonnet",
        context_window: 200_000,
        max_output_tokens: 8192,
        capabilities: %{
          features: ["chat", "vision", "function_calling", "streaming"]
        },
        pricing: %{
          input_cost_per_token: 0.003 / 1_000_000,
          output_cost_per_token: 0.015 / 1_000_000,
          currency: "USD"
        }
      },
      %Model{
        id: "claude-3-5-haiku-20241022",
        name: "Claude 3.5 Haiku",
        context_window: 200_000,
        max_output_tokens: 8192,
        capabilities: %{
          features: ["chat", "vision", "streaming"]
        },
        pricing: %{
          input_cost_per_token: 0.0008 / 1_000_000,
          output_cost_per_token: 0.004 / 1_000_000,
          currency: "USD"
        }
      },
      %Model{
        id: "claude-3-opus-20240229",
        name: "Claude 3 Opus",
        context_window: 200_000,
        max_output_tokens: 4096,
        capabilities: %{
          features: ["chat", "vision", "function_calling", "streaming"]
        },
        pricing: %{
          input_cost_per_token: 0.015 / 1_000_000,
          output_cost_per_token: 0.075 / 1_000_000,
          currency: "USD"
        }
      },
      %Model{
        id: "claude-3-sonnet-20240229",
        name: "Claude 3 Sonnet",
        context_window: 200_000,
        max_output_tokens: 4096,
        capabilities: %{
          features: ["chat", "vision", "function_calling", "streaming"]
        },
        pricing: %{
          input_cost_per_token: 0.003 / 1_000_000,
          output_cost_per_token: 0.015 / 1_000_000,
          currency: "USD"
        }
      },
      %Model{
        id: "claude-3-haiku-20240307",
        name: "Claude 3 Haiku",
        context_window: 200_000,
        max_output_tokens: 4096,
        capabilities: %{
          features: ["chat", "vision", "streaming"]
        },
        pricing: %{
          input_cost_per_token: 0.00025 / 1_000_000,
          output_cost_per_token: 0.00125 / 1_000_000,
          currency: "USD"
        }
      }
    ]

    %{request | result: models}
    |> ExLLM.Pipeline.Request.put_state(:completed)
  end
end
