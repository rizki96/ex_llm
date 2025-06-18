defmodule ExLLM.Plugs.Providers.OllamaParseStreamResponse do
  @moduledoc """
  Parses streaming responses from Ollama API.
  
  Ollama streams JSON objects, one per line, without SSE formatting.
  Each line is a complete JSON object with the response data.
  """

  use ExLLM.Plug
  
  alias ExLLM.Pipeline.Request

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Request{} = request, _opts) do
    # Set up stream parser configuration
    parser_config = %{
      parse_chunk: &parse_ollama_chunk/1,
      accumulator: %{
        content: "",
        role: "assistant",
        model: nil,
        done: false
      }
    }
    
    request
    |> Request.put_private(:stream_parser, parser_config)
    |> Request.assign(:stream_parser_configured, true)
  end
  
  defp parse_ollama_chunk(chunk) when is_binary(chunk) do
    # Ollama sends newline-delimited JSON
    chunk
    |> String.trim()
    |> String.split("\n")
    |> Enum.reduce({:continue, nil}, fn line, acc ->
      case acc do
        {:done, _} -> acc
        _ -> parse_single_line(line)
      end
    end)
  end
  
  defp parse_single_line(""), do: {:continue, nil}
  
  defp parse_single_line(line) do
    case Jason.decode(line) do
      {:ok, data} ->
        parse_ollama_data(data)
      {:error, _} ->
        {:continue, nil}
    end
  end
  
  defp parse_ollama_data(%{"done" => true} = data) do
    # Final response with usage stats
    usage = extract_usage(data)
    
    {:done, %{
      content: "",
      done: true,
      model: data["model"],
      usage: usage
    }}
  end
  
  defp parse_ollama_data(%{"message" => %{"content" => content}} = data) do
    {:continue, %{
      content: content || "",
      role: data["message"]["role"] || "assistant",
      model: data["model"]
    }}
  end
  
  defp parse_ollama_data(%{"response" => content} = data) do
    # Alternative format for some Ollama models
    {:continue, %{
      content: content || "",
      model: data["model"]
    }}
  end
  
  defp parse_ollama_data(_), do: {:continue, nil}
  
  defp extract_usage(%{
    "prompt_eval_count" => prompt_tokens,
    "eval_count" => completion_tokens
  }) do
    %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens
    }
  end
  
  defp extract_usage(_), do: %{}
end