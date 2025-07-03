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
      # Check if ExecuteStreamRequest already set up streaming
      if request.state == :streaming && request.assigns[:response_stream] do
        # Streaming is already set up, just pass through
        request
      else
        # Set up stream parser configuration for real streaming
        parser_config = %{
          parse_chunk: fn data -> parse_ollama_ndjson_chunk(data) end,
          accumulator: %{
            content: "",
            role: nil,
            finish_reason: nil,
            model: nil
          }
        }

        # Store parser config but DON'T set streaming state yet
        # Let ExecuteStreamRequest handle the actual streaming setup
        request
        |> Request.put_private(:stream_parser, parser_config)
        |> Request.assign(:stream_parser_configured, true)
      end
    end
  end

  def call(request, _opts), do: request

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

  defp parse_ollama_ndjson_chunk(data) when is_binary(data) do
    # Ollama sends NDJSON (newline-delimited JSON)
    # Each line is a complete JSON object
    data
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      case Jason.decode(line) do
        {:ok, json_data} ->
          parse_ollama_json_chunk(json_data)

        {:error, _} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      [chunk] -> chunk
      # Multiple chunks in one data packet
      chunks -> chunks
    end
  end

  defp parse_ollama_json_chunk(%{"done" => true} = data) do
    # Final chunk with usage stats
    %ExLLM.Types.StreamChunk{
      content: "",
      finish_reason: data["done_reason"] || "stop",
      model: data["model"],
      metadata: %{
        provider: :ollama,
        raw: data,
        usage: extract_ollama_usage(data)
      }
    }
  end

  defp parse_ollama_json_chunk(%{"message" => %{"content" => content}} = data) do
    %ExLLM.Types.StreamChunk{
      content: content || "",
      finish_reason: nil,
      model: data["model"],
      metadata: %{provider: :ollama, raw: data}
    }
  end

  defp parse_ollama_json_chunk(%{"response" => content} = data) do
    # Alternative format for some Ollama models
    %ExLLM.Types.StreamChunk{
      content: content || "",
      finish_reason: nil,
      model: data["model"],
      metadata: %{provider: :ollama, raw: data}
    }
  end

  defp parse_ollama_json_chunk(_), do: nil

  defp extract_ollama_usage(%{
         "prompt_eval_count" => prompt_tokens,
         "eval_count" => completion_tokens
       }) do
    %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens
    }
  end

  defp extract_ollama_usage(_), do: %{}
end
