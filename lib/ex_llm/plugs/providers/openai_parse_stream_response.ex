defmodule ExLLM.Plugs.Providers.OpenAIParseStreamResponse do
  @moduledoc """
  Parses streaming responses from OpenAI-compatible APIs.

  This plug sets up chunk parsing for Server-Sent Events (SSE) format
  used by OpenAI and compatible APIs.
  """

  use ExLLM.Plug

  @impl true
  def call(%Request{provider: provider, options: %{stream: true}} = request, _opts) do
    # For test environments with mocked SSE responses
    if request.response && is_binary(request.response.body) &&
         String.contains?(request.response.body, "data:") do
      create_stream_from_sse_body(request, provider)
    else
      # Set up stream parser configuration for real streaming
      parser_config = %{
        parse_chunk: fn data -> parse_sse_chunk(data, provider) end,
        accumulator: %{
          content: "",
          role: nil,
          finish_reason: nil,
          function_call: nil,
          tool_calls: []
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

  defp create_stream_from_sse_body(request, provider) do
    # Parse SSE events from the response body
    chunks = parse_sse_body_to_chunks(request.response.body, provider)

    # Create a stream from the chunks
    stream =
      Stream.map(chunks, fn chunk ->
        %ExLLM.Types.StreamChunk{
          content: chunk[:content],
          finish_reason: chunk[:finish_reason]
        }
      end)
      |> Stream.reject(fn chunk -> is_nil(chunk.content) && is_nil(chunk.finish_reason) end)

    request
    |> Request.assign(:response_stream, stream)
    |> Request.put_state(:streaming)
  end

  defp parse_sse_body_to_chunks(body, provider) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.map(fn line ->
      data = String.trim_leading(line, "data: ")

      cond do
        data == "[DONE]" ->
          %{finish_reason: "stop"}

        true ->
          case Jason.decode(data) do
            {:ok, parsed} ->
              extract_chunk_data(parsed, provider)

            {:error, _} ->
              nil
          end
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_chunk_data(%{"choices" => [%{"delta" => delta} | _]} = chunk, _provider) do
    %{
      content: delta["content"],
      finish_reason: chunk["choices"] |> List.first() |> Map.get("finish_reason")
    }
  end

  defp extract_chunk_data(_, _), do: nil

  @doc """
  Parses a Server-Sent Events chunk from OpenAI streaming response.
  """
  def parse_sse_chunk(data, provider) when is_binary(data) do
    data
    |> String.split("\n")
    |> Enum.reduce({:continue, []}, fn
      "data: [DONE]", _acc ->
        {:done, %{done: true}}

      "data: " <> json, {:continue, chunks} ->
        case Jason.decode(json) do
          {:ok, parsed} ->
            {:continue, chunks ++ [extract_chunk_data(parsed, provider)]}

          {:error, _} ->
            {:continue, chunks}
        end

      _, acc ->
        acc
    end)
  end
end
