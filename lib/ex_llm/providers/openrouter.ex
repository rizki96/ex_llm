defmodule ExLLM.Providers.OpenRouter do
  @moduledoc """
  OpenRouter API adapter for ExLLM.

  OpenRouter provides access to 300+ AI models through a unified API that's compatible
  with the OpenAI format. It offers intelligent routing, automatic fallbacks, and
  normalized responses across different AI providers.

  ## Configuration

  This adapter requires an OpenRouter API key and optionally app identification headers.

  ### Using Environment Variables

      # Set environment variables
      export OPENROUTER_API_KEY="your-api-key"
      export OPENROUTER_MODEL="openai/gpt-4o"  # optional
      export OPENROUTER_APP_NAME="MyApp"       # optional
      export OPENROUTER_APP_URL="https://myapp.com"  # optional

      # Use with default environment provider
      ExLLM.Providers.OpenRouter.chat(messages, config_provider: ExLLM.Infrastructure.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        openrouter: %{
          api_key: "your-api-key",
          model: "openai/gpt-4o",
          app_name: "MyApp",
          app_url: "https://myapp.com",
          base_url: "https://openrouter.ai/api"  # optional
        }
      }
      {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)
      ExLLM.Providers.OpenRouter.chat(messages, config_provider: provider)
  """

  import ExLLM.Providers.Shared.ModelUtils, only: [format_model_name: 1]
  import ExLLM.Providers.OpenAICompatible, only: [default_model_transformer: 2]

  use ExLLM.Providers.OpenAICompatible,
    provider: :openrouter,
    base_url: "https://openrouter.ai/api"

  # Override to use pipeline instead of direct HTTP calls
  @impl ExLLM.Provider
  def chat(messages, options) do
    ExLLM.Core.Chat.chat(:openrouter, messages, options)
  end

  @impl ExLLM.Provider
  def stream_chat(messages, options) do
    ExLLM.Core.Chat.stream_chat(:openrouter, messages, options)
  end

  alias ExLLM.Types

  # Add default_model to satisfy Provider behaviour
  @impl ExLLM.Provider
  def default_model, do: "openai/gpt-4o"

  # Override get_headers to add custom OpenRouter headers without modifying base module.
  @impl ExLLM.Providers.OpenAICompatible
  def get_headers(api_key, options) do
    base_headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    config_provider = get_config_provider(options)
    config = get_config(config_provider)

    openrouter_headers = [
      {"x-title", get_app_name(config)},
      {"http-referer", get_app_url(config)}
    ]

    openrouter_headers ++ base_headers
  end

  # Override transform_request to add OpenRouter-specific body parameters.
  @impl ExLLM.Providers.OpenAICompatible
  def transform_request(request, options) do
    request
    |> add_optional_param(options, :transforms, "transforms")
    |> add_optional_param(options, :route, "route")
    |> add_optional_param(options, :models, "models")
    |> add_optional_param(options, :stream_options, "stream_options")
    |> add_optional_param(options, :provider, "provider")
  end

  # Override transform_response to normalize legacy function_call into tool_calls.
  @impl ExLLM.Providers.OpenAICompatible
  def transform_response(response, _options) do
    # Handle cases where choices might not be a list
    choices = response["choices"] || []

    if is_list(choices) and length(choices) > 0 do
      first_choice = Enum.at(choices, 0)
      message = first_choice["message"] || %{}

      if message && (message["function_call"] || message["tool_calls"]) do
        tool_calls = parse_function_calls(message)

        updated_message =
          message
          |> Map.put("tool_calls", tool_calls)
          |> Map.delete("function_call")

        updated_choice = Map.put(first_choice, "message", updated_message)
        updated_choices = List.replace_at(choices, 0, updated_choice)
        Map.put(response, "choices", updated_choices)
      else
        response
      end
    else
      response
    end
  end

  # Override parse_model for OpenRouter's detailed model list.
  @impl ExLLM.Providers.OpenAICompatible
  def parse_model(model) do
    %Types.Model{
      id: model["id"],
      name: model["name"] || model["id"],
      description: model["description"],
      context_window: model["context_length"] || 4096,
      pricing: parse_pricing(model["pricing"]),
      capabilities: parse_capabilities(model)
    }
  end

  # Keep the unimplemented embeddings function as a placeholder.
  @impl ExLLM.Provider
  def embeddings(_inputs, _options) do
    {:error, {:not_implemented, :openrouter_embeddings}}
  end

  # Private helpers

  defp get_app_name(config) do
    Map.get(config, :app_name) || System.get_env("OPENROUTER_APP_NAME") || "ExLLM"
  end

  defp get_app_url(config) do
    Map.get(config, :app_url) || System.get_env("OPENROUTER_APP_URL") ||
      "https://github.com/3rdparty-integrations/ex_llm"
  end

  defp parse_function_calls(message) do
    cond do
      # OpenAI-style legacy function call
      message["function_call"] ->
        [
          %{
            "id" => "generated_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
            "type" => "function",
            "function" => %{
              "name" => message["function_call"]["name"],
              "arguments" => message["function_call"]["arguments"]
            }
          }
        ]

      # OpenAI-style tool calls
      message["tool_calls"] ->
        message["tool_calls"]

      true ->
        nil
    end
  end

  defp parse_pricing(nil), do: nil

  defp parse_pricing(pricing) do
    %{
      currency: "USD",
      input_cost_per_token: parse_price_value(pricing["prompt"]) / 1_000_000,
      output_cost_per_token: parse_price_value(pricing["completion"]) / 1_000_000
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

  defp parse_capabilities(model) do
    features = []
    features = if model["supports_streaming"], do: [:streaming | features], else: features
    features = if model["supports_functions"], do: [:function_calling | features], else: features
    features = if model["supports_vision"], do: [:vision | features], else: features

    %{
      supports_streaming: model["supports_streaming"] || false,
      supports_functions: model["supports_functions"] || false,
      supports_vision: model["supports_vision"] || false,
      features: features
    }
  end
end
