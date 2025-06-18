defmodule ExLLM.Plugs.Providers.OpenAIPrepareEmbeddingRequest do
  @moduledoc """
  Prepares embedding requests for the OpenAI API.
  
  Transforms the standardized ExLLM embedding request into OpenAI's specific
  embedding API format.
  """
  
  use ExLLM.Plug
  
  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    input = get_input_from_request(request)
    config = request.config
    
    # Build OpenAI embedding request body
    body = %{
      input: input,
      model: config[:model] || "text-embedding-3-small",
      encoding_format: config[:encoding_format] || "float"
    }
    
    # Add optional parameters
    body = 
      body
      |> maybe_add_dimensions(config)
      |> maybe_add_user(config)
    
    # Set the request path and body
    request
    |> Map.put(:provider_request, body)
    |> ExLLM.Pipeline.Request.assign(:http_method, :post)
    |> ExLLM.Pipeline.Request.assign(:http_path, "/embeddings")
  end
  
  defp get_input_from_request(request) do
    # Input can be in different places depending on how the request was made
    cond do
      request.assigns[:embedding_input] ->
        request.assigns[:embedding_input]
      
      request.options[:input] ->
        request.options[:input]
        
      # For backward compatibility, check if messages contain text content
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
  
  defp maybe_add_dimensions(body, config) do
    case config[:dimensions] do
      nil -> body
      dims when is_integer(dims) -> Map.put(body, :dimensions, dims)
      _ -> body
    end
  end
  
  defp maybe_add_user(body, config) do
    case config[:user] do
      nil -> body
      user when is_binary(user) -> Map.put(body, :user, user)
      _ -> body
    end
  end
end