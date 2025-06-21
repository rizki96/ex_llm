defmodule ExLLM.Plugs.Providers.MockListModelsHandler do
  @moduledoc """
  Mock handler for list models requests in the pipeline architecture.

  This handler returns a static list of mock models for testing purposes.
  """

  use ExLLM.Plug
  alias ExLLM.Types.Model

  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, opts) do
    # Check if we should simulate an error
    if error = get_mock_error(request.config, opts) do
      ExLLM.Pipeline.Request.halt_with_error(request, %{
        error: error,
        plug: __MODULE__,
        mock_list_models_handler_called: true
      })
    else
      # Return mock models list
      models = get_mock_models(request.config, opts)

      request
      |> Map.put(:result, models)
      |> ExLLM.Pipeline.Request.put_state(:completed)
      |> ExLLM.Pipeline.Request.assign(:mock_list_models_handler_called, true)
    end
  end

  defp get_mock_error(config, opts) do
    config[:mock_error] || opts[:error] ||
      Application.get_env(:ex_llm, :mock_list_models_error)
  end

  defp get_mock_models(config, opts) do
    # Check for custom models in various places
    custom_models =
      config[:models] ||
        opts[:models] ||
        Application.get_env(:ex_llm, :mock_models)

    if custom_models do
      # Convert custom models to Model structs if they're plain maps
      Enum.map(custom_models, &ensure_model_struct/1)
    else
      # Return default mock models as structs
      [
        %Model{
          id: "mock-model-large",
          name: "Mock Large Model",
          context_window: 128_000,
          max_output_tokens: 4096,
          capabilities: %{
            features: ["chat", "embeddings", "function_calling"]
          },
          pricing: %{
            input_cost_per_token: 0.01 / 1_000_000,
            output_cost_per_token: 0.03 / 1_000_000,
            currency: "USD"
          }
        },
        %Model{
          id: "mock-model-small",
          name: "Mock Small Model",
          context_window: 8192,
          max_output_tokens: 2048,
          capabilities: %{
            features: ["chat"]
          },
          pricing: %{
            input_cost_per_token: 0.001 / 1_000_000,
            output_cost_per_token: 0.002 / 1_000_000,
            currency: "USD"
          }
        },
        %Model{
          id: "mock-embedding-model",
          name: "Mock Embedding Model",
          context_window: 8191,
          capabilities: %{
            features: ["embeddings"],
            dimensions: 384
          },
          pricing: %{
            input_cost_per_token: 0.0001 / 1_000_000,
            output_cost_per_token: nil,
            currency: "USD"
          }
        }
      ]
    end
  end

  defp ensure_model_struct(%Model{} = model), do: model
  defp ensure_model_struct(model_map) when is_map(model_map) do
    %Model{
      id: model_map.id || model_map[:id],
      name: model_map.name || model_map[:name],
      description: model_map.description || model_map[:description],
      context_window: model_map.context_window || model_map[:context_window],
      max_output_tokens: model_map.max_output_tokens || model_map[:max_output_tokens],
      capabilities: normalize_capabilities(model_map.capabilities || model_map[:capabilities]),
      pricing: normalize_pricing(model_map.pricing || model_map[:pricing])
    }
  end

  defp normalize_capabilities(nil), do: nil
  defp normalize_capabilities(capabilities) when is_list(capabilities) do
    %{features: capabilities}
  end
  defp normalize_capabilities(capabilities) when is_map(capabilities), do: capabilities

  defp normalize_pricing(nil), do: nil
  defp normalize_pricing(%{input: input, output: output} = pricing) do
    %{
      input_cost_per_token: (input || 0) / 1_000_000,
      output_cost_per_token: (output || 0) / 1_000_000,
      currency: pricing[:currency] || "USD"
    }
  end
  defp normalize_pricing(pricing) when is_map(pricing), do: pricing
end
