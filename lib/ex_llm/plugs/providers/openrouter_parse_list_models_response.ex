defmodule ExLLM.Plugs.Providers.OpenRouterParseListModelsResponse do
  @moduledoc """
  Parses list models response from the OpenRouter API.

  OpenRouter provides models from multiple providers with rich metadata
  including pricing, context windows, and capabilities.
  """

  use ExLLM.Plug

  @impl true
  def call(%ExLLM.Pipeline.Request{response: %Tesla.Env{} = response} = request, _opts) do
    case response.status do
      200 ->
        parse_success_response(request, response)

      status when status in [401, 403] ->
        parse_auth_error_response(request, response, status)

      status when status >= 500 ->
        parse_server_error_response(request, response, status)

      _ ->
        parse_unknown_error_response(request, response)
    end
  end

  defp parse_success_response(request, response) do
    body = response.body

    # Extract and transform model data
    models =
      case body["data"] do
        models when is_list(models) ->
          models
          |> Enum.map(&transform_model/1)
          |> Enum.sort_by(& &1.id)

        _ ->
          []
      end

    request
    |> Map.put(:result, models)
    |> ExLLM.Pipeline.Request.put_state(:completed)
  end

  defp parse_auth_error_response(request, response, status) do
    error_data = %{
      type: :authentication_error,
      status: status,
      message: extract_error_message(response.body),
      provider: :openrouter
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_server_error_response(request, _response, status) do
    error_data = %{
      type: :server_error,
      status: status,
      message: "OpenRouter server error (#{status})",
      provider: :openrouter,
      retryable: true
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_unknown_error_response(request, response) do
    error_data = %{
      type: :unknown_error,
      status: response.status,
      message: "Unexpected response from OpenRouter",
      provider: :openrouter,
      raw_response: response.body
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp transform_model(model) do
    %{
      id: model["id"],
      name: model["name"] || model["id"],
      description: model["description"],
      context_window: model["context_length"] || 4096,
      max_output_tokens: get_max_output_tokens(model),
      capabilities: parse_capabilities(model),
      pricing: parse_pricing(model["pricing"]),
      created: model["created"],
      provider_info: %{
        top_provider: model["top_provider"],
        architecture: model["architecture"]
      }
    }
  end

  defp get_max_output_tokens(model) do
    case model["top_provider"] do
      %{"max_completion_tokens" => max_tokens} when is_integer(max_tokens) -> max_tokens
      _ -> nil
    end
  end

  defp parse_capabilities(model) do
    base_capabilities = ["chat"]

    # Extract supported parameters to determine capabilities
    supported_params = model["supported_parameters"] || []

    capabilities =
      if "tools" in supported_params or "tool_choice" in supported_params do
        ["function_calling" | base_capabilities]
      else
        base_capabilities
      end

    # Check if model supports vision based on architecture or description
    capabilities =
      if supports_vision?(model) do
        ["vision" | capabilities]
      else
        capabilities
      end

    # Check for streaming support (most models support it)
    capabilities = ["streaming" | capabilities]

    capabilities
  end

  defp supports_vision?(model) do
    # Check architecture input modalities
    case get_in(model, ["architecture", "input_modalities"]) do
      modalities when is_list(modalities) ->
        "image" in modalities or "file" in modalities

      _ ->
        # Fallback: check model ID for known vision models
        model_id = model["id"] || ""
        model_id =~ ~r/(vision|gpt-4o|gpt-4-turbo|claude-3|gemini)/i
    end
  end

  defp parse_pricing(nil), do: nil

  defp parse_pricing(pricing) when is_map(pricing) do
    %{
      currency: "USD",
      input_cost_per_token: parse_price_value(pricing["prompt"]) / 1_000_000,
      output_cost_per_token: parse_price_value(pricing["completion"]) / 1_000_000,
      image_cost: parse_price_value(pricing["image"]),
      request_cost: parse_price_value(pricing["request"])
    }
  end

  defp parse_price_value(nil), do: 0
  defp parse_price_value(value) when is_number(value), do: value

  defp parse_price_value(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> parsed
      :error -> 0
    end
  end

  defp extract_error_message(body) when is_map(body) do
    case body do
      %{"error" => %{"message" => message}} -> message
      %{"error" => error} when is_binary(error) -> error
      %{"message" => message} -> message
      _ -> "Unknown error"
    end
  end

  defp extract_error_message(_), do: "Unknown error"
end
