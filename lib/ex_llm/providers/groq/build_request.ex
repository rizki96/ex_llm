defmodule ExLLM.Providers.Groq.BuildRequest do
  @moduledoc """
  Pipeline plug for building Groq API requests.

  Since Groq uses OpenAI-compatible API format, this plug largely delegates
  to the OpenAI BuildRequest plug but handles Groq-specific configuration
  and URL endpoints.
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
        Map.get(config, :model) || ConfigHelper.ensure_default_model(:groq)
      )

    # Build request body using OpenAI format (Groq is compatible)
    body = build_request_body(messages, model, config, options)
    headers = build_headers(api_key)
    url = "#{get_base_url(config)}/chat/completions"

    request
    |> Request.assign(:model, model)
    |> Request.assign(:request_body, body)
    |> Request.assign(:request_headers, headers)
    |> Request.assign(:request_url, url)
    |> Request.assign(:timeout, 60_000)
  end

  defp build_request_body(messages, model, config, options) do
    # Use OpenAI-compatible format
    %{
      model: model,
      messages: MessageFormatter.stringify_message_keys(messages),
      temperature: Keyword.get(options, :temperature, Map.get(config, :temperature, 0.7))
    }
    |> maybe_add_max_tokens(options, config)
    |> maybe_add_parameters(options)
    |> maybe_add_streaming_options(options)
    |> maybe_add_system_prompt(options)
  end

  defp build_headers(api_key) do
    [
      {"authorization", "Bearer #{api_key}"}
    ]
  end

  defp get_base_url(config) do
    Map.get(config, :base_url) ||
      System.get_env("GROQ_API_BASE") ||
      "https://api.groq.com/openai/v1"
  end

  defp maybe_add_system_prompt(body, options) do
    case Keyword.get(options, :system) do
      nil -> body
      system -> Map.update!(body, :messages, &MessageFormatter.add_system_message(&1, system))
    end
  end

  defp maybe_add_max_tokens(body, options, config) do
    case Keyword.get(options, :max_tokens) || Map.get(config, :max_tokens) do
      nil -> body
      max_tokens -> Map.put(body, :max_tokens, max_tokens)
    end
  end

  defp maybe_add_parameters(body, options) do
    body
    |> maybe_add_param(:top_p, options)
    |> maybe_add_param(:frequency_penalty, options)
    |> maybe_add_param(:presence_penalty, options)
    |> maybe_add_param(:stop, options)
    |> maybe_add_param(:user, options)
    |> maybe_add_param(:seed, options)
  end

  defp maybe_add_streaming_options(body, options) do
    case Keyword.get(options, :stream) do
      true -> Map.put(body, :stream, true)
      _ -> body
    end
  end

  defp maybe_add_param(body, key, options) do
    case Keyword.get(options, key) do
      nil -> body
      value -> Map.put(body, key, value)
    end
  end
end
