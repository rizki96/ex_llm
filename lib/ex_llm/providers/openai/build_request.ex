defmodule ExLLM.Providers.OpenAI.BuildRequest do
  @moduledoc """
  Pipeline plug for building OpenAI API requests.

  This plug transforms a standardized ExLLM request into the format expected
  by the OpenAI API, including proper message formatting, parameter handling,
  and authentication headers.
  """

  use ExLLM.Plug

  alias ExLLM.Providers.Shared.{ConfigHelper, MessageFormatter}

  @default_temperature 0.7

  @impl true
  def call(request, _opts) do
    # Extract configuration and API key from request
    config = request.assigns.config
    api_key = request.assigns.api_key
    messages = request.messages
    options = request.options

    # Determine model
    model =
      Map.get(
        options,
        :model,
        Map.get(config, :model) || ConfigHelper.ensure_default_model(:openai)
      )

    # Build request body and headers
    body = build_request_body(messages, model, config, options)
    headers = build_headers(api_key, config)
    url = "#{get_base_url(config)}/v1/chat/completions"

    request
    |> Map.put(:provider_request, body)
    |> Request.assign(:model, model)
    |> Request.assign(:request_body, body)
    |> Request.assign(:request_headers, headers)
    |> Request.assign(:request_url, url)
    |> Request.assign(:timeout, 60_000)
  end

  defp build_request_body(messages, model, config, options) do
    %{
      model: model,
      messages: MessageFormatter.stringify_message_keys(messages),
      temperature:
        Map.get(options, :temperature, Map.get(config, :temperature, @default_temperature))
    }
    |> maybe_add_max_tokens(options, config)
    |> maybe_add_modern_parameters(options)
    |> maybe_add_response_format(options)
    |> maybe_add_tools(options)
    |> maybe_add_audio_options(options)
    |> maybe_add_web_search(options)
    |> maybe_add_prediction(options)
    |> maybe_add_streaming_options(options)
    |> maybe_add_o_series_options(options, model)
    |> maybe_add_system_prompt(options)
    # Keep for backward compatibility
    |> maybe_add_functions(options)
  end

  defp build_headers(api_key, config) do
    headers = [
      {"authorization", "Bearer #{api_key}"}
    ]

    if org = Map.get(config, :organization) do
      [{"openai-organization", org} | headers]
    else
      headers
    end
  end

  defp get_base_url(config) do
    Map.get(config, :base_url) ||
      System.get_env("OPENAI_API_BASE") ||
      "https://api.openai.com"
  end

  defp maybe_add_system_prompt(body, options) do
    case Map.get(options, :system) do
      nil -> body
      system -> Map.update!(body, :messages, &MessageFormatter.add_system_message(&1, system))
    end
  end

  defp maybe_add_functions(body, options) do
    case Map.get(options, :functions) do
      nil -> body
      functions -> Map.put(body, :functions, functions)
    end
  end

  defp maybe_add_max_tokens(body, options, config) do
    case Map.get(options, :max_tokens) || Map.get(config, :max_tokens) do
      nil -> body
      max_tokens -> Map.put(body, :max_tokens, max_tokens)
    end
  end

  defp maybe_add_modern_parameters(body, options) do
    body
    |> maybe_add_param(:top_p, options)
    |> maybe_add_param(:frequency_penalty, options)
    |> maybe_add_param(:presence_penalty, options)
    |> maybe_add_param(:stop, options)
    |> maybe_add_param(:user, options)
    |> maybe_add_param(:seed, options)
    |> maybe_add_param(:top_logprobs, options)
    |> maybe_add_param(:logprobs, options)
  end

  defp maybe_add_response_format(body, options) do
    case Map.get(options, :response_format) do
      nil -> body
      format -> Map.put(body, :response_format, format)
    end
  end

  defp maybe_add_tools(body, options) do
    case Map.get(options, :tools) do
      nil -> body
      tools -> Map.put(body, :tools, tools)
    end
  end

  defp maybe_add_audio_options(body, options) do
    body
    |> maybe_add_param(:audio, options)
  end

  defp maybe_add_web_search(body, options) do
    case Map.get(options, :web_search) do
      nil -> body
      true -> Map.put(body, :web_search, true)
      false -> body
    end
  end

  defp maybe_add_o_series_options(body, options, model) do
    if String.starts_with?(model, "o1") do
      body
      |> maybe_add_param(:reasoning_effort, options)
      |> Map.delete(:temperature)
      # o1 doesn't support streaming
      |> Map.delete(:stream)
      |> transform_max_tokens_for_o1()
    else
      body
    end
  end

  defp transform_max_tokens_for_o1(body) do
    case Map.pop(body, :max_tokens) do
      {nil, body} ->
        body

      {max_tokens, body} ->
        Map.put(body, :max_completion_tokens, max_tokens)
    end
  end

  defp maybe_add_prediction(body, options) do
    case Map.get(options, :prediction) do
      nil -> body
      prediction -> Map.put(body, :prediction, prediction)
    end
  end

  defp maybe_add_streaming_options(body, options) do
    case Map.get(options, :stream) do
      true -> Map.put(body, :stream, true)
      _ -> body
    end
  end

  defp maybe_add_param(body, key, options) do
    case Map.get(options, key) do
      nil -> body
      value -> Map.put(body, key, value)
    end
  end
end
