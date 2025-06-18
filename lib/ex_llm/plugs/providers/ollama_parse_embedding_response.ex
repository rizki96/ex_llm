defmodule ExLLM.Plugs.Providers.OllamaParseEmbeddingResponse do
  @moduledoc """
  Parses embedding responses from the Ollama API.
  
  Transforms Ollama's embedding response format into the standardized
  ExLLM embedding response format.
  """
  
  use ExLLM.Plug
  
  alias ExLLM.Types.EmbeddingResponse
  
  @impl true
  def call(%ExLLM.Pipeline.Request{response: %Tesla.Env{} = response} = request, _opts) do
    case response.status do
      200 ->
        parse_success_response(request, response)
      
      status when status in [400, 404, 422] ->
        parse_error_response(request, response, status)
        
      status when status >= 500 ->
        parse_server_error_response(request, response, status)
        
      _ ->
        parse_unknown_error_response(request, response)
    end
  end
  
  defp parse_success_response(request, response) do
    body = response.body
    
    # Extract embedding data from Ollama's response format
    embeddings = 
      case body["embedding"] do
        embedding when is_list(embedding) ->
          [embedding]
        
        _ ->
          []
      end
    
    # Estimate usage since Ollama doesn't provide detailed usage
    usage = estimate_usage(body, request)
    
    # Build standardized response
    embedding_response = %EmbeddingResponse{
      embeddings: embeddings,
      model: extract_model_name(request),
      usage: usage,
      metadata: %{
        provider: :ollama,
        total_duration: body["total_duration"],
        load_duration: body["load_duration"],
        prompt_eval_count: body["prompt_eval_count"],
        raw_response_keys: Map.keys(body)
      }
    }
    
    request
    |> Map.put(:result, embedding_response)
    |> ExLLM.Pipeline.Request.put_state(:completed)
  end
  
  defp parse_error_response(request, response, status) do
    error_data = %{
      type: :api_error,
      status: status,
      message: extract_error_message(response.body),
      provider: :ollama,
      raw_response: response.body
    }
    
    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end
  
  defp parse_server_error_response(request, response, status) do
    error_data = %{
      type: :server_error,
      status: status,
      message: "Ollama server error (#{status})",
      provider: :ollama,
      retryable: true,
      raw_response: response.body
    }
    
    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end
  
  defp parse_unknown_error_response(request, response) do
    error_data = %{
      type: :unknown_error,
      status: response.status,
      message: "Unexpected response from Ollama",
      provider: :ollama,
      raw_response: response.body
    }
    
    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end
  
  defp estimate_usage(body, request) do
    # Try to get usage from response, otherwise estimate
    prompt_eval_count = body["prompt_eval_count"]
    
    if prompt_eval_count do
      %{
        input_tokens: prompt_eval_count,
        output_tokens: 0,
        total_tokens: prompt_eval_count
      }
    else
      # Estimate based on input
      input_text = get_original_input(request)
      estimated_tokens = estimate_tokens(input_text)
      
      %{
        input_tokens: estimated_tokens,
        output_tokens: 0,
        total_tokens: estimated_tokens
      }
    end
  end
  
  defp get_original_input(request) do
    case request.assigns[:embedding_input] do
      input when is_binary(input) -> input
      input when is_list(input) -> Enum.join(input, " ")
      _ -> ""
    end
  end
  
  defp estimate_tokens(text) do
    # Simple estimation: ~4 characters per token
    max(1, div(String.length(text), 4))
  end
  
  defp extract_model_name(request) do
    request.config[:model] || "llama3.2"
  end
  
  defp extract_error_message(body) when is_map(body) do
    case body do
      %{"error" => error} when is_binary(error) -> error
      %{"message" => message} -> message
      _ -> "Unknown error"
    end
  end
  
  defp extract_error_message(_), do: "Unknown error"
end