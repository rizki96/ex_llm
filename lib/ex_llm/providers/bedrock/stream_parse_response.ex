defmodule ExLLM.Providers.Bedrock.StreamParseResponse do
  @moduledoc """
  Handles streaming responses from AWS Bedrock with multi-provider support.

  This plug handles the complexity of parsing streaming responses from different
  model providers through the Bedrock API. Each sub-provider may have different
  streaming formats and event structures.
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Shared.HTTPClient
  alias ExLLM.Types

  @impl true
  def call(%Request{state: :executing} = request, opts) do
    stream =
      Keyword.get(opts, :stream, false) ||
        Keyword.get(request.options, :stream, false)

    if stream do
      initiate_streaming(request)
    else
      # Not a streaming request, pass through to next plug
      request
    end
  end

  def call(request, _opts), do: request

  defp initiate_streaming(request) do
    url = request.assigns[:url]
    body = request.assigns[:body]
    headers = request.assigns[:signed_headers] || request.assigns[:headers]
    provider_type = request.assigns[:provider_type]
    model = request.assigns[:model]
    timeout = Keyword.get(request.options, :timeout, 60_000)

    if url && body && headers do
      # Update URL for streaming endpoint
      streaming_url = String.replace(url, "/invoke", "/invoke-with-response-stream")

      callback = fn chunk ->
        parse_bedrock_chunk(chunk, provider_type, model)
      end

      case HTTPClient.stream_request(streaming_url, body, headers, callback,
             timeout: timeout,
             provider: request.provider
           ) do
        {:ok, _stream_result} ->
          request
          |> Request.put_state(:streaming)

        {:error, error} ->
          request
          |> Request.add_error(%{
            plug: __MODULE__,
            reason: error,
            message: "Failed to initiate Bedrock streaming: #{inspect(error)}"
          })
          |> Request.put_state(:error)
          |> Request.halt()
      end
    else
      request
      |> Request.add_error(%{
        plug: __MODULE__,
        reason: :missing_request_data,
        message: "Missing URL, body, or headers for Bedrock streaming request"
      })
      |> Request.put_state(:error)
      |> Request.halt()
    end
  end

  defp parse_bedrock_chunk(chunk, provider_type, model) do
    case parse_event_stream_chunk(chunk) do
      {:ok, :heartbeat} ->
        # AWS sends periodic heartbeat events, ignore them
        :continue

      {:ok, event_data} ->
        case extract_content_from_event(event_data, provider_type) do
          {:ok, content, finish_reason} ->
            %Types.StreamChunk{
              content: content,
              finish_reason: finish_reason,
              model: model,
              metadata: %{
                provider: provider_type,
                bedrock: true
              }
            }

          {:error, _reason} ->
            # Skip malformed chunks but continue streaming
            :continue
        end

      {:error, _reason} ->
        # Skip malformed chunks but continue streaming
        :continue
    end
  end

  defp parse_event_stream_chunk(chunk) do
    # AWS event stream format parsing
    # Event streams use a binary format with headers and payload
    case parse_aws_event_stream(chunk) do
      {:ok, %{event_type: ":event-type", value: "chunk"}, payload} ->
        case Jason.decode(payload) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %{event_type: ":event-type", value: "ping"}, _payload} ->
        {:ok, :heartbeat}

      {:ok, %{event_type: ":event-type", value: event_type}, payload} ->
        # Other event types (like errors)
        case Jason.decode(payload) do
          {:ok, data} -> {:ok, %{event_type: event_type, data: data}}
          {:error, _} -> {:error, :invalid_json}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_aws_event_stream(chunk) when is_binary(chunk) do
    # Simplified AWS event stream parser
    # In a full implementation, this would handle the binary format properly
    # For now, we'll assume SSE-like format for compatibility
    case String.split(chunk, "\n") do
      lines when length(lines) >= 2 ->
        # Look for event and data lines
        event_type = extract_sse_field(lines, "event")
        data = extract_sse_field(lines, "data")

        if data do
          {:ok, %{event_type: ":event-type", value: event_type || "chunk"}, data}
        else
          {:error, :no_data}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  defp extract_sse_field(lines, field_name) do
    prefix = "#{field_name}: "

    lines
    |> Enum.find_value(fn line ->
      if String.starts_with?(line, prefix) do
        String.slice(line, String.length(prefix)..-1)
      else
        nil
      end
    end)
  end

  defp extract_content_from_event(event_data, provider_type) do
    case provider_type do
      "anthropic" ->
        extract_anthropic_streaming_content(event_data)

      "amazon" ->
        extract_amazon_streaming_content(event_data)

      "meta" ->
        extract_meta_streaming_content(event_data)

      "cohere" ->
        extract_cohere_streaming_content(event_data)

      "ai21" ->
        extract_ai21_streaming_content(event_data)

      "mistral" ->
        extract_mistral_streaming_content(event_data)

      "writer" ->
        extract_writer_streaming_content(event_data)

      "deepseek" ->
        extract_deepseek_streaming_content(event_data)

      _ ->
        {:error, "Unsupported streaming provider: #{provider_type}"}
    end
  end

  # Anthropic streaming content extraction
  defp extract_anthropic_streaming_content(%{"delta" => %{"text" => text}}) do
    {:ok, text, nil}
  end

  defp extract_anthropic_streaming_content(%{"delta" => %{"stop_reason" => reason}}) do
    {:ok, "", reason}
  end

  defp extract_anthropic_streaming_content(_), do: {:error, :no_content}

  # Amazon streaming content extraction
  defp extract_amazon_streaming_content(%{"outputText" => text}) do
    {:ok, text, nil}
  end

  defp extract_amazon_streaming_content(%{"completionReason" => reason}) do
    {:ok, "", reason}
  end

  defp extract_amazon_streaming_content(_), do: {:error, :no_content}

  # Meta streaming content extraction
  defp extract_meta_streaming_content(%{"generation" => text}) do
    {:ok, text, nil}
  end

  defp extract_meta_streaming_content(%{"stop_reason" => reason}) do
    {:ok, "", reason}
  end

  defp extract_meta_streaming_content(_), do: {:error, :no_content}

  # Cohere streaming content extraction
  defp extract_cohere_streaming_content(%{"text" => text}) do
    {:ok, text, nil}
  end

  defp extract_cohere_streaming_content(%{"finish_reason" => reason}) do
    {:ok, "", reason}
  end

  defp extract_cohere_streaming_content(_), do: {:error, :no_content}

  # AI21 streaming content extraction
  defp extract_ai21_streaming_content(%{"data" => %{"text" => text}}) do
    {:ok, text, nil}
  end

  defp extract_ai21_streaming_content(%{"finishReason" => %{"reason" => reason}}) do
    {:ok, "", reason}
  end

  defp extract_ai21_streaming_content(_), do: {:error, :no_content}

  # Mistral streaming content extraction
  defp extract_mistral_streaming_content(%{"text" => text}) do
    {:ok, text, nil}
  end

  defp extract_mistral_streaming_content(%{"stop_reason" => reason}) do
    {:ok, "", reason}
  end

  defp extract_mistral_streaming_content(_), do: {:error, :no_content}

  # Writer streaming content extraction (similar to Anthropic)
  defp extract_writer_streaming_content(%{"delta" => %{"text" => text}}) do
    {:ok, text, nil}
  end

  defp extract_writer_streaming_content(%{"delta" => %{"stop_reason" => reason}}) do
    {:ok, "", reason}
  end

  defp extract_writer_streaming_content(_), do: {:error, :no_content}

  # DeepSeek streaming content extraction (similar to Anthropic)
  defp extract_deepseek_streaming_content(%{"delta" => %{"text" => text}}) do
    {:ok, text, nil}
  end

  defp extract_deepseek_streaming_content(%{"delta" => %{"stop_reason" => reason}}) do
    {:ok, "", reason}
  end

  defp extract_deepseek_streaming_content(_), do: {:error, :no_content}
end
