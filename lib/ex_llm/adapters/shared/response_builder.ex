defmodule ExLLM.Adapters.Shared.ResponseBuilder do
  @moduledoc """
  Shared utilities for building standardized responses across adapters.
  
  Provides consistent response construction for:
  - Chat completions
  - Streaming chunks
  - Function calls
  - Error responses
  - Embeddings
  """
  
  alias ExLLM.{Types, Cost}
  
  @doc """
  Build a standard chat response from provider-specific data.
  
  ## Options
  - `:calculate_cost` - Whether to calculate cost (default: true)
  - `:provider` - Provider name for cost calculation
  
  ## Examples
  
      ResponseBuilder.build_chat_response(%{
        "choices" => [%{"message" => %{"content" => "Hello!"}}],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5}
      }, "gpt-4", provider: :openai)
  """
  @spec build_chat_response(map(), String.t(), keyword()) :: Types.LLMResponse.t()
  def build_chat_response(data, model, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    calculate_cost = Keyword.get(opts, :calculate_cost, true)
    
    # Extract content based on common patterns
    content = extract_content(data)
    usage = extract_usage(data)
    finish_reason = extract_finish_reason(data)
    
    # Calculate cost if requested and we have usage data
    cost = if calculate_cost && usage != nil && provider != nil do
      Cost.calculate(provider, model, usage)
    else
      nil
    end
    
    %Types.LLMResponse{
      content: content,
      model: model,
      usage: usage,
      finish_reason: finish_reason,
      cost: cost,
      id: data["id"]
    }
  end
  
  @doc """
  Build a streaming chunk from provider data.
  """
  @spec build_stream_chunk(map(), keyword()) :: Types.StreamChunk.t() | nil
  def build_stream_chunk(data, opts \\ []) do
    case extract_stream_content(data) do
      nil -> nil
      {content, finish_reason} ->
        %Types.StreamChunk{
          content: content,
          finish_reason: finish_reason,
          model: Keyword.get(opts, :model),
          id: data["id"]
        }
    end
  end
  
  @doc """
  Build an embedding response from provider data.
  """
  @spec build_embedding_response(map(), String.t(), keyword()) :: Types.EmbeddingResponse.t()
  def build_embedding_response(data, model, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    
    embeddings = extract_embeddings(data)
    usage = extract_embedding_usage(data)
    
    cost = if usage != nil && provider != nil do
      Cost.calculate(provider, model, usage)
    else
      nil
    end
    
    %Types.EmbeddingResponse{
      embeddings: embeddings,
      model: model,
      usage: usage,
      cost: cost
    }
  end
  
  @doc """
  Extract and normalize usage data from various formats.
  
  Maps provider-specific field names to standardized ExLLM format:
  - API field names: prompt_tokens, completion_tokens (OpenAI, OpenRouter, etc.)
  - ExLLM field names: input_tokens, output_tokens
  """
  @spec extract_usage(map()) :: map() | nil
  def extract_usage(data) do
    cond do
      # OpenAI/Anthropic format
      usage = data["usage"] ->
        %{
          input_tokens: usage["prompt_tokens"] || usage["input_tokens"] || 0,
          output_tokens: usage["completion_tokens"] || usage["output_tokens"] || 0,
          total_tokens: usage["total_tokens"] || 0
        }
        
      # Gemini format
      metadata = data["usageMetadata"] ->
        %{
          input_tokens: metadata["promptTokenCount"] || 0,
          output_tokens: metadata["candidatesTokenCount"] || 0,
          total_tokens: metadata["totalTokenCount"] || 0
        }
        
      true ->
        nil
    end
  end
  
  # Private extraction functions
  
  defp extract_content(data) do
    cond do
      # OpenAI/Groq format
      choices = data["choices"] ->
        get_in(choices, [Access.at(0), "message", "content"])
        
      # Anthropic format
      content = data["content"] ->
        case content do
          [%{"text" => text} | _] -> text
          text when is_binary(text) -> text
          _ -> nil
        end
        
      # Gemini format
      candidates = data["candidates"] ->
        get_in(candidates, [Access.at(0), "content", "parts", Access.at(0), "text"])
        
      true ->
        nil
    end
  end
  
  defp extract_finish_reason(data) do
    cond do
      # OpenAI format
      choices = data["choices"] ->
        get_in(choices, [Access.at(0), "finish_reason"])
        
      # Anthropic format
      stop_reason = data["stop_reason"] ->
        stop_reason
        
      # Gemini format
      candidates = data["candidates"] ->
        get_in(candidates, [Access.at(0), "finishReason"])
        
      true ->
        nil
    end
  end
  
  
  defp extract_stream_content(data) do
    cond do
      # OpenAI stream format
      choices = data["choices"] ->
        delta = get_in(choices, [Access.at(0), "delta"])
        finish = get_in(choices, [Access.at(0), "finish_reason"])
        {delta["content"], finish}
        
      # Anthropic stream format
      data["type"] == "content_block_delta" ->
        {get_in(data, ["delta", "text"]), nil}
        
      data["type"] == "message_delta" ->
        {nil, get_in(data, ["delta", "stop_reason"])}
        
      # End markers
      data["type"] == "message_stop" ->
        {nil, "stop"}
        
      true ->
        nil
    end
  end
  
  defp extract_embeddings(data) do
    cond do
      # OpenAI format
      embeddings = data["data"] ->
        Enum.map(embeddings, & &1["embedding"])
        
      # Single embedding
      embedding = data["embedding"] ->
        [embedding]
        
      true ->
        []
    end
  end
  
  defp extract_embedding_usage(data) do
    if usage = data["usage"] do
      %{
        input_tokens: usage["prompt_tokens"] || usage["total_tokens"] || 0,
        output_tokens: 0  # Embeddings don't have output tokens
      }
    else
      nil
    end
  end
end