defmodule ExLLM.Plugs.Providers.PerplexityPrepareRequest do
  @moduledoc """
  Prepares chat completion requests for the Perplexity API.

  Perplexity uses a similar format to OpenAI but without the /v1 prefix
  and with additional parameters for web search functionality.
  """

  use ExLLM.Plug

  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, _opts) do
    messages = request.messages
    config = request.assigns[:config] || %{}
    options = request.options

    # Build request body similar to OpenAI format
    body = build_request_body(messages, config, options)

    # Transform the request for Perplexity-specific features
    transformed_body =
      body
      |> add_optional_param(options, :search_mode, "search_mode")
      |> add_optional_param(options, :web_search_options, "web_search_options")
      |> add_optional_param(options, :reasoning_effort, "reasoning_effort")
      |> add_optional_param(options, :return_images, "return_images")
      |> add_optional_param(options, :image_domain_filter, "image_domain_filter")
      |> add_optional_param(options, :image_format_filter, "image_format_filter")
      |> add_optional_param(options, :recency_filter, "recency_filter")
      # Perplexity uses a different default temperature
      |> Map.put_new("temperature", 0.2)

    request
    |> Map.put(:provider_request, transformed_body)
    |> ExLLM.Pipeline.Request.assign(:http_method, :post)
    # No /v1 prefix
    |> ExLLM.Pipeline.Request.assign(:http_path, "/chat/completions")
  end

  defp add_optional_param(request, options, option_key, param_name) do
    value = get_option(options, option_key)

    if value do
      Map.put(request, param_name, value)
    else
      request
    end
  end

  defp get_option(options, key) when is_map(options), do: Map.get(options, key)
  defp get_option(options, key) when is_list(options), do: Keyword.get(options, key)
  defp get_option(_, _), do: nil

  defp build_request_body(messages, config, options) do
    # Build base request body
    model = get_option(options, :model) || config[:model] || "sonar"

    body = %{
      "messages" => messages,
      "model" => model
    }

    # Add optional parameters
    body
    |> add_optional_param(options, :temperature, "temperature")
    |> add_optional_param(options, :top_p, "top_p")
    |> add_optional_param(options, :max_tokens, "max_tokens")
    |> add_optional_param(options, :frequency_penalty, "frequency_penalty")
    |> add_optional_param(options, :presence_penalty, "presence_penalty")
    |> add_optional_param(options, :n, "n")
    |> add_optional_param(options, :stop, "stop")
    |> add_optional_param(options, :stream, "stream")
  end
end
