defmodule ExLLM.Plugs.Providers.GeminiParseStreamResponse do
  @moduledoc """
  Parses streaming responses from Google's Gemini API.
  
  Gemini uses a different streaming format than OpenAI, returning
  JSON objects separated by commas in an array-like structure.
  """

  use ExLLM.Plug
  
  alias ExLLM.Pipeline.Request

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Request{} = request, _opts) do
    # Set up stream parser configuration
    parser_config = %{
      parse_chunk: &parse_gemini_chunk/1,
      accumulator: %{
        content: "",
        role: "model",
        finish_reason: nil,
        usage: %{}
      }
    }
    
    request
    |> Request.put_private(:stream_parser, parser_config)
    |> Request.assign(:stream_parser_configured, true)
  end
  
  defp parse_gemini_chunk(chunk) when is_binary(chunk) do
    case Jason.decode(chunk) do
      {:ok, data} ->
        parse_gemini_data(data)
      {:error, _} ->
        # Try to clean up the chunk (remove array markers)
        cleaned = chunk
          |> String.trim()
          |> String.trim_leading("[")
          |> String.trim_trailing(",")
          |> String.trim_trailing("]")
          
        case Jason.decode(cleaned) do
          {:ok, data} -> parse_gemini_data(data)
          {:error, _} -> {:continue, nil}
        end
    end
  end
  
  defp parse_gemini_data(%{"candidates" => [candidate | _]} = data) do
    content = extract_content(candidate)
    finish_reason = candidate["finishReason"]
    usage = data["usageMetadata"]
    
    chunk_data = %{
      content: content || "",
      finish_reason: finish_reason
    }
    
    if finish_reason do
      {:done, Map.put(chunk_data, :usage, parse_usage(usage))}
    else
      {:continue, chunk_data}
    end
  end
  
  defp parse_gemini_data(_), do: {:continue, nil}
  
  defp extract_content(%{"content" => %{"parts" => parts}}) when is_list(parts) do
    parts
    |> Enum.map(&extract_part_text/1)
    |> Enum.join("")
  end
  
  defp extract_content(_), do: nil
  
  defp extract_part_text(%{"text" => text}), do: text
  defp extract_part_text(_), do: ""
  
  defp parse_usage(%{"promptTokenCount" => prompt, "candidatesTokenCount" => completion} = usage) do
    %{
      prompt_tokens: prompt,
      completion_tokens: completion,
      total_tokens: usage["totalTokenCount"] || (prompt + completion)
    }
  end
  
  defp parse_usage(_), do: %{}
end