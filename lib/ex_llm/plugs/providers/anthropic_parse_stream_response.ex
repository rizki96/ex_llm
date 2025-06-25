defmodule ExLLM.Plugs.Providers.AnthropicParseStreamResponse do
  @moduledoc """
  Parses streaming responses from the Anthropic API.

  Anthropic uses a different streaming format with event types like
  message_start, content_block_start, content_block_delta, etc.
  """

  use ExLLM.Plug

  @impl true
  def call(%Request{options: %{stream: true}} = request, _opts) do
    # For test environments with mocked SSE responses
    if request.response && is_binary(request.response.body) &&
         String.contains?(request.response.body, "data:") do
      create_stream_from_sse_body(request)
    else
      # Set up stream parser configuration for real streaming
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
  end

  def call(request, _opts), do: request

  defp create_stream_from_sse_body(request) do
    # Parse SSE events from the response body
    events = parse_sse_events(request.response.body)

    # Create a stream from the events
    stream =
      Stream.map(events, fn event ->
        case parse_event_to_chunk(event) do
          nil ->
            nil

          chunk ->
            %ExLLM.Types.StreamChunk{
              content: chunk[:content],
              finish_reason: chunk[:stop_reason] || chunk[:finish_reason]
            }
        end
      end)
      |> Stream.reject(&is_nil/1)

    request
    |> Request.assign(:response_stream, stream)
    |> Request.put_state(:streaming)
  end

  defp parse_sse_events(body) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.map(fn line ->
      data = String.trim_leading(line, "data: ")

      case Jason.decode(data) do
        {:ok, parsed} -> parse_anthropic_event(parsed)
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_anthropic_event(%{"type" => "content_block_delta", "delta" => %{"text" => text}}) do
    %{content: text}
  end

  defp parse_anthropic_event(%{"type" => "message_delta", "delta" => %{"stop_reason" => reason}}) do
    %{stop_reason: reason}
  end

  defp parse_anthropic_event(%{"type" => "message_stop"}) do
    %{done: true}
  end

  defp parse_anthropic_event(_), do: nil

  defp parse_event_to_chunk(%{content: content}) when is_binary(content) do
    %{content: content}
  end

  defp parse_event_to_chunk(%{stop_reason: reason}) when not is_nil(reason) do
    %{finish_reason: reason}
  end

  defp parse_event_to_chunk(%{done: true}) do
    %{finish_reason: "stop"}
  end

  defp parse_event_to_chunk(_), do: nil

  @doc """
  Parses Anthropic's streaming event format.
  """
  def parse_anthropic_chunk(data) when is_binary(data) do
    # Parse all SSE events from the data
    events =
      data
      |> String.split("\n\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.flat_map(&parse_single_sse_event/1)
      |> Enum.reject(&is_nil/1)

    # Check if we're done
    if Enum.any?(events, &match?(%{done: true}, &1)) do
      # Find the final chunk with stop_reason
      final = Enum.find(events, &Map.has_key?(&1, :stop_reason)) || %{done: true}
      {:done, final}
    else
      {:continue, events}
    end
  end

  defp parse_single_sse_event(event) do
    lines = String.split(event, "\n")

    # Extract event type and data
    event_type =
      Enum.find_value(lines, fn
        "event: " <> type -> type
        _ -> nil
      end)

    data_json =
      Enum.find_value(lines, fn
        "data: " <> json -> json
        _ -> nil
      end)

    # Handle special events
    case event_type do
      "message_stop" ->
        [%{done: true}]

      _ when data_json != nil ->
        case Jason.decode(data_json) do
          {:ok, parsed} ->
            [parse_event_data(event_type, parsed)]

          {:error, _} ->
            []
        end

      _ ->
        []
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
