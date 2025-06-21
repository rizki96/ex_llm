defmodule ExLLM.Plugs.Providers.AnthropicParseStreamResponse do
  @moduledoc """
  Parses streaming responses from the Anthropic API.

  Anthropic uses a different streaming format with event types like
  message_start, content_block_start, content_block_delta, etc.
  """

  use ExLLM.Plug

  @impl true
  def call(%Request{} = request, _opts) do
    # Set up stream parser configuration for Anthropic's format
    parser_config = %{
      parse_chunk: &parse_anthropic_chunk/1,
      accumulator: %{
        content: "",
        role: "assistant",
        model: nil,
        stop_reason: nil,
        usage: %{}
      }
    }

    request
    |> Request.put_private(:stream_parser, parser_config)
    |> Request.assign(:stream_parser_configured, true)
  end

  @doc """
  Parses Anthropic's streaming event format.
  """
  def parse_anthropic_chunk(data) when is_binary(data) do
    data
    |> String.split("\n")
    |> Enum.reduce({:continue, []}, fn
      "event: message_stop", _acc ->
        {:done, %{done: true}}

      "event: " <> event_type, acc ->
        # Store event type for next data line
        put_elem(acc, 1, [{:event_type, event_type} | elem(acc, 1)])

      "data: " <> json, {:continue, chunks} ->
        case Jason.decode(json) do
          {:ok, parsed} ->
            # Get the last event type
            {event_type, remaining} = extract_event_type(chunks)
            chunk_data = parse_event_data(event_type, parsed)
            {:continue, remaining ++ [chunk_data]}

          {:error, _} ->
            {:continue, chunks}
        end

      _, acc ->
        acc
    end)
  end

  defp extract_event_type(chunks) do
    case Enum.find_index(chunks, &match?({:event_type, _}, &1)) do
      nil ->
        {nil, chunks}

      idx ->
        {:event_type, type} = Enum.at(chunks, idx)
        {type, List.delete_at(chunks, idx)}
    end
  end

  defp parse_event_data("message_start", %{"message" => message}) do
    %{
      model: message["model"],
      role: message["role"],
      usage: parse_usage(message["usage"])
    }
  end

  defp parse_event_data("content_block_start", %{"content_block" => block}) do
    %{
      content_type: block["type"],
      text: block["text"] || ""
    }
  end

  defp parse_event_data("content_block_delta", %{"delta" => delta}) do
    %{
      content: delta["text"] || "",
      provider: :anthropic
    }
  end

  defp parse_event_data("message_delta", %{"delta" => delta, "usage" => usage}) do
    %{
      stop_reason: delta["stop_reason"],
      usage: parse_usage(usage)
    }
  end

  defp parse_event_data(_, _), do: %{}

  defp parse_usage(nil), do: %{}

  defp parse_usage(usage) do
    %{
      prompt_tokens: usage["input_tokens"] || 0,
      completion_tokens: usage["output_tokens"] || 0,
      total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
    }
  end
end
