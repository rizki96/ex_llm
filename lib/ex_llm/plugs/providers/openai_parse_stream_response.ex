defmodule ExLLM.Plugs.Providers.OpenAIParseStreamResponse do
  @moduledoc """
  Parses streaming responses from OpenAI-compatible APIs.

  This plug sets up chunk parsing for Server-Sent Events (SSE) format
  used by OpenAI and compatible APIs.
  """

  use ExLLM.Plug
  alias ExLLM.Infrastructure.Logger

  @impl true
  def call(%Request{} = request, _opts) do
    # Set up stream parser configuration
    parser_config = %{
      parse_chunk: &parse_sse_chunk/1,
      accumulator: %{
        content: "",
        role: nil,
        finish_reason: nil,
        function_call: nil,
        tool_calls: []
      }
    }

    request
    |> Request.put_private(:stream_parser, parser_config)
    |> Request.assign(:stream_parser_configured, true)
  end

  @doc """
  Parses a Server-Sent Events chunk from OpenAI streaming response.
  """
  def parse_sse_chunk(data) when is_binary(data) do
    data
    |> String.split("\n")
    |> Enum.reduce({:continue, []}, fn
      "data: [DONE]", _acc ->
        {:done, %{done: true}}

      "data: " <> json, {:continue, chunks} ->
        case Jason.decode(json) do
          {:ok, parsed} ->
            {:continue, chunks ++ [extract_chunk_data(parsed)]}

          {:error, _} ->
            {:continue, chunks}
        end

      _, acc ->
        acc
    end)
  end

  defp extract_chunk_data(%{"choices" => [%{"delta" => delta} | _]} = chunk) do
    %{
      content: delta["content"] || "",
      role: delta["role"],
      finish_reason: chunk["choices"] |> List.first() |> Map.get("finish_reason"),
      function_call: extract_function_call(delta),
      tool_calls: extract_tool_calls(delta),
      model: chunk["model"],
      provider: :openai
    }
  end

  defp extract_chunk_data(_), do: %{content: ""}

  defp extract_function_call(%{"function_call" => fc}) when is_map(fc) do
    %{
      name: fc["name"],
      arguments: fc["arguments"] || ""
    }
  end

  defp extract_function_call(_), do: nil

  defp extract_tool_calls(%{"tool_calls" => calls}) when is_list(calls) do
    Enum.map(calls, fn call ->
      %{
        index: call["index"],
        id: call["id"],
        type: call["type"],
        function: %{
          name: get_in(call, ["function", "name"]),
          arguments: get_in(call, ["function", "arguments"]) || ""
        }
      }
    end)
  end

  defp extract_tool_calls(_), do: []
end
