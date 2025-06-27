defmodule ExLLM.Providers.Ollama.BuildRequest do
  @moduledoc """
  Pipeline plug for building Ollama API requests.

  Ollama uses its native API format at /api/chat endpoint.
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Shared.{ConfigHelper, MessageFormatter}

  @impl true
  def call(request, _opts) do
    # Extract configuration from request
    config = request.assigns.config
    # Will be "no-api-key-required" for Ollama
    _api_key = request.assigns.api_key
    messages = request.messages
    options = request.options

    # Determine model
    model =
      Map.get(
        options,
        :model,
        Map.get(config, :model) || ConfigHelper.ensure_default_model(:ollama)
      )

    # Build request body and headers
    body = build_request_body(messages, model, config, options)
    headers = build_headers()
    url = "#{get_base_url(config)}/api/chat"

    request
    |> Map.put(:provider_request, body)
    |> Request.assign(:model, model)
    |> Request.assign(:request_body, body)
    |> Request.assign(:request_headers, headers)
    |> Request.assign(:request_url, url)
    |> Request.assign(:http_path, "/api/chat")
    |> Request.assign(:timeout, 60_000)
  end

  defp build_request_body(messages, model, config, options) do
    # Handle system prompts if provided as option
    formatted_messages = 
      case Map.get(options, :system) do
        nil -> messages
        system_content ->
          [%{role: "system", content: system_content} | messages]
      end
    
    # Use Ollama's native format
    %{
      model: model,
      messages: MessageFormatter.stringify_message_keys(formatted_messages),
      temperature:
        Map.get(
          options,
          :temperature,
          Map.get(config, :temperature, 0.7)
        )
    }
    |> maybe_add_max_tokens(options, config)
    |> maybe_add_parameters(options)
    |> maybe_add_streaming_options(options)
  end

  defp build_headers do
    [{"content-type", "application/json"}]
  end

  defp get_base_url(config) do
    Map.get(config, :base_url) ||
      System.get_env("OLLAMA_API_BASE") ||
      "http://localhost:11434"
  end

  defp maybe_add_max_tokens(body, options, config) do
    case Map.get(options, :max_tokens, Map.get(config, :max_tokens)) do
      nil -> body
      max_tokens -> Map.put(body, :options, %{num_predict: max_tokens})
    end
  end

  defp maybe_add_parameters(body, _options) do
    # Add other Ollama-specific parameters if needed
    body
  end

  defp maybe_add_streaming_options(body, options) do
    # Always explicitly set stream option for Ollama
    Map.put(body, :stream, Map.get(options, :stream, false))
  end
end
