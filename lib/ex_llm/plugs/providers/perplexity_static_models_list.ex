defmodule ExLLM.Plugs.Providers.PerplexityStaticModelsList do
  @moduledoc """
  Returns a static list of Perplexity models since they don't have a models API.

  This plug bypasses the HTTP request and returns a pre-defined list of models
  available on Perplexity.
  """

  use ExLLM.Plug
  alias ExLLM.Pipeline.Request
  alias ExLLM.Types

  @perplexity_models [
    # Search Models
    %Types.Model{
      id: "sonar",
      name: "Sonar",
      description: "Lightweight, cost-effective search model",
      context_window: 128_000,
      max_output_tokens: 8000,
      capabilities: %{
        supports_streaming: true,
        supports_functions: false,
        supports_vision: false,
        features: ["web_search", "streaming"]
      }
    },
    %Types.Model{
      id: "sonar-pro",
      name: "Sonar Pro",
      description: "Advanced search with grounding for complex queries",
      context_window: 128_000,
      max_output_tokens: 8000,
      capabilities: %{
        supports_streaming: true,
        supports_functions: false,
        supports_vision: false,
        features: ["web_search", "streaming"]
      }
    },
    # Reasoning Models
    %Types.Model{
      id: "sonar-reasoning",
      name: "Sonar Reasoning",
      description: "Chain of thought reasoning with web search",
      context_window: 128_000,
      max_output_tokens: 8000,
      capabilities: %{
        supports_streaming: true,
        supports_functions: false,
        supports_vision: false,
        features: ["web_search", "reasoning", "streaming"]
      }
    },
    %Types.Model{
      id: "sonar-reasoning-pro",
      name: "Sonar Reasoning Pro",
      description: "Premier reasoning model with enhanced capabilities",
      context_window: 128_000,
      max_output_tokens: 8000,
      capabilities: %{
        supports_streaming: true,
        supports_functions: false,
        supports_vision: false,
        features: ["web_search", "reasoning", "streaming"]
      }
    },
    # Research Model
    %Types.Model{
      id: "sonar-deep-research",
      name: "Sonar Deep Research",
      description: "Expert-level research conducting exhaustive searches",
      context_window: 128_000,
      max_output_tokens: 8000,
      capabilities: %{
        supports_streaming: true,
        supports_functions: false,
        supports_vision: false,
        features: ["web_search", "reasoning", "streaming"]
      }
    },
    # R1 Model
    %Types.Model{
      id: "r1-1776",
      name: "R1-1776",
      description: "Advanced reasoning model with structured thinking",
      context_window: 128_000,
      max_output_tokens: 8000,
      capabilities: %{
        supports_streaming: true,
        supports_functions: false,
        supports_vision: false,
        features: ["reasoning", "streaming"]
      }
    }
  ]

  @impl true
  def call(%Request{} = request, _opts) do
    models_response = %{
      "data" => @perplexity_models,
      "object" => "list"
    }

    request
    |> Map.put(:response, %Tesla.Env{status: 200, body: models_response})
    |> Request.assign(:models, @perplexity_models)
    |> Request.put_state(:completed)
  end
end
