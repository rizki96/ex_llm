defmodule ExLLM.Providers.Anthropic.BuildRequest do
  @moduledoc """
  Pipeline plug for building Anthropic API requests.

  This plug transforms a standardized ExLLM request into the format expected
  by the Anthropic API, including proper message formatting, parameter handling,
  and authentication headers.
  """

  use ExLLM.Plug

  alias ExLLM.Providers.Shared.{ConfigHelper, MessageFormatter}

  @impl true
  def call(request, _opts) do
    # Extract configuration and API key from request
    config = request.assigns.config
    api_key = request.assigns.api_key
    messages = request.messages
    options = request.options

    # Determine model
    model =
      Keyword.get(
        options,
        :model,
        Map.get(config, :model) || ConfigHelper.ensure_default_model(:anthropic)
      )

    # Build request body and headers
    body = build_request_body(messages, model, config, options)
    headers = build_headers(api_key)
    url = "#{get_base_url(config)}/v1/messages"

    request
    |> Request.assign(:model, model)
    |> Request.assign(:request_body, body)
    |> Request.assign(:request_headers, headers)
    |> Request.assign(:request_url, url)
    |> Request.assign(:timeout, 60_000)
  end

  defp build_request_body(messages, model, config, options) do
    # Extract system message if present
    {system_content, other_messages} = MessageFormatter.extract_system_message(messages)

    # Format messages for Anthropic
    formatted_messages = format_messages_for_anthropic(other_messages)

    body = %{
      model: model,
      messages: formatted_messages,
      max_tokens: Keyword.get(options, :max_tokens, Map.get(config, :max_tokens, 4096))
    }

    # Add system message if present
    body =
      if system_content do
        Map.put(body, :system, system_content)
      else
        body
      end

    # Add temperature if specified
    case Keyword.get(options, :temperature) do
      nil -> body
      temp -> Map.put(body, :temperature, temp)
    end
  end

  defp build_headers(api_key) do
    [
      {"authorization", "Bearer #{api_key}"},
      {"anthropic-version", "2023-06-01"}
    ]
  end

  defp get_base_url(config) do
    Map.get(config, :base_url) ||
      System.get_env("ANTHROPIC_API_BASE") ||
      "https://api.anthropic.com"
  end

  defp format_messages_for_anthropic(messages) do
    Enum.map(messages, fn
      %{role: "user", content: content} when is_binary(content) ->
        %{
          role: "user",
          content: content
        }

      %{role: "user", content: content} when is_list(content) ->
        formatted_content = format_content_blocks(content)

        %{
          role: "user",
          content: formatted_content
        }

      %{role: "assistant", content: content} ->
        %{
          role: "assistant",
          content: content
        }

      message ->
        # Pass through as-is for other message types
        message
    end)
  end

  defp format_content_blocks(content_blocks) do
    Enum.map(content_blocks, fn
      %{type: "text", text: text} ->
        %{type: "text", text: text}

      %{type: "image_url", image_url: %{url: url}} ->
        %{
          type: "image",
          source: %{
            type: "base64",
            media_type: "image/jpeg",
            data: extract_base64_data(url)
          }
        }

      block ->
        # Pass through other content blocks as-is
        block
    end)
  end

  defp extract_base64_data("data:" <> rest) do
    case String.split(rest, ",", parts: 2) do
      [_media_type, data] -> data
      [data] -> data
    end
  end

  defp extract_base64_data(url), do: url
end
