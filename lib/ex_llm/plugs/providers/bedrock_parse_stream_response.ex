defmodule ExLLM.Plugs.Providers.BedrockParseStreamResponse do
  @moduledoc """
  Parses streaming responses from AWS Bedrock API.
  
  Bedrock streams events in a specific format with different
  event types for different model families.
  """

  use ExLLM.Plug
  
  alias ExLLM.Pipeline.Request

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Request{assigns: assigns} = request, _opts) do
    model = assigns[:bedrock_model] || ""
    
    # Set up stream parser configuration based on model
    parser_config = %{
      parse_chunk: build_parser(model),
      accumulator: %{
        content: "",
        role: "assistant",
        done: false,
        usage: %{}
      }
    }
    
    request
    |> Request.put_private(:stream_parser, parser_config)
    |> Request.assign(:stream_parser_configured, true)
  end
  
  defp build_parser(model) do
    cond do
      String.contains?(model, "claude") -> &parse_claude_chunk/1
      String.contains?(model, "titan") -> &parse_titan_chunk/1
      String.contains?(model, "llama") -> &parse_llama_chunk/1
      String.contains?(model, "command") -> &parse_cohere_chunk/1
      String.contains?(model, "mistral") -> &parse_mistral_chunk/1
      true -> &parse_claude_chunk/1
    end
  end

  # Claude streaming format
  defp parse_claude_chunk(chunk) when is_binary(chunk) do
    case decode_bedrock_event(chunk) do
      {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
        {:continue, %{content: text}}
        
      {:ok, %{"type" => "message_stop"}} ->
        {:done, %{done: true}}
        
      {:ok, %{"type" => "message_delta", "usage" => usage}} ->
        {:continue, %{usage: parse_usage(usage)}}
        
      _ ->
        {:continue, nil}
    end
  end

  # Titan streaming format
  defp parse_titan_chunk(chunk) when is_binary(chunk) do
    case decode_bedrock_event(chunk) do
      {:ok, %{"chunk" => %{"outputText" => text}}} ->
        {:continue, %{content: text}}
        
      {:ok, %{"completionReason" => reason}} ->
        {:done, %{done: true, finish_reason: reason}}
        
      _ ->
        {:continue, nil}
    end
  end

  # Llama streaming format
  defp parse_llama_chunk(chunk) when is_binary(chunk) do
    case decode_bedrock_event(chunk) do
      {:ok, %{"generation" => text}} ->
        {:continue, %{content: text}}
        
      {:ok, %{"stop_reason" => reason}} ->
        {:done, %{done: true, finish_reason: reason}}
        
      _ ->
        {:continue, nil}
    end
  end

  # Cohere streaming format
  defp parse_cohere_chunk(chunk) when is_binary(chunk) do
    case decode_bedrock_event(chunk) do
      {:ok, %{"text" => text}} ->
        {:continue, %{content: text}}
        
      {:ok, %{"is_finished" => true}} ->
        {:done, %{done: true}}
        
      _ ->
        {:continue, nil}
    end
  end

  # Mistral streaming format
  defp parse_mistral_chunk(chunk) when is_binary(chunk) do
    case decode_bedrock_event(chunk) do
      {:ok, %{"outputs" => [%{"text" => text} | _]}} ->
        {:continue, %{content: text}}
        
      {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} ->
        {:continue, %{content: content}}
        
      {:ok, %{"choices" => [%{"finish_reason" => reason} | _]}} when not is_nil(reason) ->
        {:done, %{done: true, finish_reason: reason}}
        
      _ ->
        {:continue, nil}
    end
  end

  defp decode_bedrock_event(chunk) do
    # Bedrock events come in a specific format
    # :event-type header followed by JSON data
    
    # Try to extract JSON from the chunk
    chunk
    |> String.trim()
    |> extract_json()
    |> decode_json()
  end

  defp extract_json(data) do
    # Bedrock events might have headers we need to skip
    case String.split(data, "\n", parts: 2) do
      [_header, json] -> json
      [json] -> json
    end
  end

  defp decode_json(data) do
    case Jason.decode(data) do
      {:ok, _} = result -> result
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp parse_usage(%{"inputTokens" => input, "outputTokens" => output}) do
    %{
      prompt_tokens: input,
      completion_tokens: output,
      total_tokens: input + output
    }
  end
  
  defp parse_usage(_), do: %{}
end