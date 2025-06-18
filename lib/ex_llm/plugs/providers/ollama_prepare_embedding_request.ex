defmodule ExLLM.Plugs.Providers.OllamaPrepareEmbeddingRequest do
  @moduledoc """
  Prepares embedding requests for the Ollama API.
  
  Transforms the standardized ExLLM embedding request into Ollama's specific
  embedding API format.
  """
  
  use ExLLM.Plug
  
  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    input = get_input_from_request(request)
    config = request.config
    
    # Build Ollama embedding request body
    body = %{
      model: get_model_name(config),
      prompt: prepare_input(input)
    }
    
    # Add optional parameters
    body = maybe_add_options(body, config)
    
    # Set the request path and body
    request
    |> Map.put(:provider_request, body)
    |> ExLLM.Pipeline.Request.assign(:http_method, :post)
    |> ExLLM.Pipeline.Request.assign(:http_path, "/api/embeddings")
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
  
  defp prepare_input(input) when is_binary(input), do: input
  defp prepare_input([single]) when is_binary(single), do: single
  defp prepare_input(input) when is_list(input) do
    # Ollama expects a single prompt, so join multiple inputs
    Enum.join(input, "\n")
  end
  defp prepare_input(_), do: ""
  
  defp maybe_add_options(body, config) do
    body
    |> maybe_add_keep_alive(config)
    |> maybe_add_truncate(config)
  end
  
  defp maybe_add_keep_alive(body, config) do
    case config[:keep_alive] do
      nil -> body
      keep_alive -> Map.put(body, :keep_alive, keep_alive)
    end
  end
  
  defp maybe_add_truncate(body, config) do
    case config[:truncate] do
      nil -> body
      truncate when is_boolean(truncate) -> Map.put(body, :truncate, truncate)
      _ -> body
    end
  end
  
  defp get_model_name(config) do
    config[:model] || "llama3.2"
  end
end