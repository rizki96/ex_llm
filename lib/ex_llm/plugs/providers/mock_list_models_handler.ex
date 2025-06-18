defmodule ExLLM.Plugs.Providers.MockListModelsHandler do
  @moduledoc """
  Mock handler for list models requests in the pipeline architecture.
  
  This handler returns a static list of mock models for testing purposes.
  """
  
  use ExLLM.Plug
  
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
      custom_models
    else
      # Return default mock models
      [
        %{
          id: "mock-model-large",
          name: "Mock Large Model",
          context_window: 128000,
          max_output_tokens: 4096,
          capabilities: ["chat", "embeddings", "function_calling"],
          pricing: %{
            input: 0.01,
            output: 0.03
          }
        },
        %{
          id: "mock-model-small",
          name: "Mock Small Model",
          context_window: 8192,
          max_output_tokens: 2048,
          capabilities: ["chat"],
          pricing: %{
            input: 0.001,
            output: 0.002
          }
        },
        %{
          id: "mock-embedding-model",
          name: "Mock Embedding Model",
          context_window: 8191,
          dimensions: 384,
          capabilities: ["embeddings"],
          pricing: %{
            input: 0.0001
          }
        }
      ]
    end
  end
end