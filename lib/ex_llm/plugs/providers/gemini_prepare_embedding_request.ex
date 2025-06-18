defmodule ExLLM.Plugs.Providers.GeminiPrepareEmbeddingRequest do
  @moduledoc """
  Prepares embedding requests for the Gemini API.
  
  Transforms the standardized ExLLM embedding request into Gemini's specific
  embedding API format.
  """
  
  use ExLLM.Plug
  
  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    input = get_input_from_request(request)
    config = request.config
    
    # Build Gemini embedding request body
    body = %{
      requests: build_embedding_requests(input, config)
    }
    
    # Set the request path and body
    request
    |> Map.put(:provider_request, body)
    |> ExLLM.Pipeline.Request.assign(:http_method, :post)
    |> ExLLM.Pipeline.Request.assign(:http_path, "/v1/models/#{get_model_name(config)}:batchEmbedContents")
  end
  
  defp get_input_from_request(request) do
    cond do
      request.assigns[:embedding_input] ->
        request.assigns[:embedding_input]
      
      request.options[:input] ->
        request.options[:input]
        
      length(request.messages) > 0 ->
        request.messages 
        |> Enum.map(fn msg -> 
          case msg do
            %{content: content} when is_binary(content) -> content
            %{"content" => content} when is_binary(content) -> content
            _ -> ""
          end
        end)
        |> Enum.filter(&(&1 != ""))
        
      true ->
        []
    end
  end
  
  defp build_embedding_requests(input, config) when is_binary(input) do
    [build_single_request(input, config)]
  end
  
  defp build_embedding_requests(input, config) when is_list(input) do
    Enum.map(input, &build_single_request(&1, config))
  end
  
  defp build_single_request(text, config) do
    request = %{
      content: %{
        parts: [%{text: text}]
      }
    }
    
    # Add optional parameters
    request
    |> maybe_add_task_type(config)
    |> maybe_add_title(config)
  end
  
  defp maybe_add_task_type(request, config) do
    case config[:task_type] do
      nil -> request
      task_type when task_type in [
        "RETRIEVAL_QUERY", "RETRIEVAL_DOCUMENT", "SEMANTIC_SIMILARITY", 
        "CLASSIFICATION", "CLUSTERING", "QUESTION_ANSWERING", "FACT_VERIFICATION"
      ] ->
        Map.put(request, :taskType, task_type)
      _ -> request
    end
  end
  
  defp maybe_add_title(request, config) do
    case config[:title] do
      nil -> request
      title when is_binary(title) -> Map.put(request, :title, title)
      _ -> request
    end
  end
  
  defp get_model_name(config) do
    config[:model] || "text-embedding-004"
  end
end