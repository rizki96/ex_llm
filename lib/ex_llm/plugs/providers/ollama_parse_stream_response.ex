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
  def call(%Request{options: %{stream: true}} = request, _opts) do
    # For cases where we already have the full NDJSON response (e.g., testing)
    if request.response && is_binary(request.response.body) &&
         String.contains?(request.response.body, "\n{") do
      create_stream_from_ndjson_body(request)
    else
      # Set up stream parser configuration for real streaming
      parser_config = %{
        parse_chunk: &parse_ollama_chunk/1,
        accumulator: %{
          content: "",
          role: "assistant",
          model: nil,
          done: false
        }
      }

      # CRITICAL FIX: Set streaming state to halt pipeline for ALL streaming requests
      request
      |> Request.put_private(:stream_parser, parser_config)
      |> Request.assign(:stream_parser_configured, true)
      |> Request.put_state(:streaming)
    end
  end

  def call(request, _opts), do: request

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

    {:done,
     %{
       content: "",
       done: true,
       model: data["model"],
       usage: usage
     }}
  end

  defp parse_ollama_data(%{"message" => %{"content" => content}} = data) do
    {:continue,
     %{
       content: content || "",
       role: data["message"]["role"] || "assistant",
       model: data["model"]
     }}
  end

  defp parse_ollama_data(%{"response" => content} = data) do
    # Alternative format for some Ollama models
    {:continue,
     %{
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

  defp create_stream_from_ndjson_body(request) do
    # Parse NDJSON lines from the response body
    chunks = parse_ndjson_body_to_chunks(request.response.body)

    # Create a stream from the chunks
    stream =
      Stream.map(chunks, fn chunk ->
        %ExLLM.Types.StreamChunk{
          content: chunk[:content] || "",
          finish_reason: chunk[:finish_reason],
          model: chunk[:model]
        }
      end)

    # Assign the stream and set streaming state
    request
    |> Request.assign(:response_stream, stream)
    |> Request.put_state(:streaming)
  end

  defp parse_ndjson_body_to_chunks(body) do
    body
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      case Jason.decode(line) do
        {:ok, data} ->
          parse_chunk_data(data)

        {:error, _} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_chunk_data(%{"done" => true} = data) do
    %{
      content: "",
      finish_reason: data["done_reason"] || "stop",
      model: data["model"]
    }
  end

  defp parse_chunk_data(%{"message" => %{"content" => content}} = data) do
    %{
      content: content || "",
      role: data["message"]["role"] || "assistant",
      model: data["model"]
    }
  end

  defp parse_chunk_data(_), do: nil
end
