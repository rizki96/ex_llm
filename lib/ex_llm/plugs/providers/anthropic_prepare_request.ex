defmodule ExLLM.Plugs.Providers.AnthropicPrepareRequest do
  @moduledoc """
  Prepares a request for the Anthropic API.

  Transforms the generic ExLLM message format into Anthropic's expected
  format. This includes:
  - Converting message structure
  - Handling system messages (Anthropic uses a separate system field)
  - Formatting multimodal content
  - Setting appropriate headers
  """

  use ExLLM.Plug
  require Logger

  @impl true
  def call(%Request{} = request, _opts) do
    body = build_request_body(request)

    request
    |> Request.put_private(:provider_request_body, body)
    |> Request.assign(:request_prepared, true)
  end

  defp build_request_body(%Request{messages: messages, config: config}) do
    # Separate system messages from other messages
    {system_messages, other_messages} = Enum.split_with(messages, &(&1[:role] == "system"))

    # Build base request
    body = %{
      messages: Enum.map(other_messages, &format_message/1),
      model: config[:model] || "claude-3-opus-20240229",
      max_tokens: config[:max_tokens] || 4096
    }

    # Add system prompt if present
    body =
      case system_messages do
        [] ->
          body

        [%{content: content} | _rest] ->
          # Anthropic only supports one system message
          Map.put(body, :system, content)
      end

    # Add optional parameters
    body
    |> maybe_add_temperature(config)
    |> maybe_add_top_p(config)
    |> maybe_add_top_k(config)
    |> maybe_add_stop_sequences(config)
    |> maybe_add_stream(config)
    |> maybe_add_metadata(config)
    |> compact()
  end

  defp format_message(%{role: role, content: content}) do
    %{
      "role" => normalize_role(role),
      "content" => format_content(content)
    }
  end

  defp normalize_role("user"), do: "user"
  defp normalize_role("assistant"), do: "assistant"
  # System messages handled separately
  defp normalize_role("system"), do: "user"
  defp normalize_role(_), do: "user"

  defp format_content(content) when is_binary(content), do: content

  defp format_content(content) when is_list(content) do
    Enum.map(content, fn
      %{type: "text", text: text} ->
        %{"type" => "text", "text" => text}

      %{type: "image", source: %{type: "base64", media_type: media_type, data: data}} ->
        %{
          "type" => "image",
          "source" => %{
            "type" => "base64",
            "media_type" => media_type,
            "data" => data
          }
        }

      %{type: "image_url", image_url: %{url: url}} when is_binary(url) ->
        # Convert data URLs to Anthropic format
        case parse_data_url(url) do
          {:ok, media_type, data} ->
            %{
              "type" => "image",
              "source" => %{
                "type" => "base64",
                "media_type" => media_type,
                "data" => data
              }
            }

          :error ->
            # Skip non-data URLs as Anthropic doesn't support external URLs
            nil
        end

      # Handle string keys
      %{"type" => _} = item ->
        item

      other ->
        Logger.warning("Unknown content type in Anthropic message: #{inspect(other)}")
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp format_content(content), do: to_string(content)

  defp parse_data_url("data:" <> rest) do
    case String.split(rest, ";base64,", parts: 2) do
      [media_type, data] -> {:ok, media_type, data}
      _ -> :error
    end
  end

  defp parse_data_url(_), do: :error

  defp maybe_add_temperature(body, %{temperature: temp}) when is_number(temp) do
    Map.put(body, :temperature, temp)
  end

  defp maybe_add_temperature(body, _), do: body

  defp maybe_add_top_p(body, %{top_p: top_p}) when is_number(top_p) do
    Map.put(body, :top_p, top_p)
  end

  defp maybe_add_top_p(body, _), do: body

  defp maybe_add_top_k(body, %{top_k: top_k}) when is_integer(top_k) do
    Map.put(body, :top_k, top_k)
  end

  defp maybe_add_top_k(body, _), do: body

  defp maybe_add_stop_sequences(body, %{stop_sequences: sequences}) when is_list(sequences) do
    Map.put(body, :stop_sequences, sequences)
  end

  defp maybe_add_stop_sequences(body, _), do: body

  defp maybe_add_stream(body, %{stream: true}) do
    Map.put(body, :stream, true)
  end

  defp maybe_add_stream(body, _), do: body

  defp maybe_add_metadata(body, %{metadata: metadata}) when is_map(metadata) do
    Map.put(body, :metadata, metadata)
  end

  defp maybe_add_metadata(body, _), do: body

  defp compact(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
