defmodule ExLLM.Providers.Mistral do
  @moduledoc """
  Mistral AI API adapter for ExLLM.

  Mistral AI provides state-of-the-art language models including:
  - Mistral Large: Most capable model for complex reasoning
  - Mistral Medium: Balanced model for most use cases  
  - Mistral Small: Fast and cost-effective model
  - Codestral: Specialized model for code generation
  - Pixtral: Multimodal model with vision capabilities

  ## Configuration

  This adapter requires a Mistral AI API key and optionally a base URL.

  ### Using Environment Variables

      # Set environment variables
      export MISTRAL_API_KEY="your-api-key"
      export MISTRAL_MODEL="mistral/mistral-tiny"  # optional
      export MISTRAL_API_BASE="https://api.mistral.ai/v1"  # optional

      # Use with default environment provider
      ExLLM.Providers.Mistral.chat(messages, config_provider: ExLLM.Infrastructure.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        mistral: %{
          api_key: "your-api-key",
          model: "mistral/mistral-small-latest",
          base_url: "https://api.mistral.ai/v1"  # optional
        }
      }
      {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)
      ExLLM.Providers.Mistral.chat(messages, config_provider: provider)

  ## Example Usage

      messages = [
        %{role: "user", content: "Explain quantum computing"}
      ]

      # Simple chat
      {:ok, response} = ExLLM.Providers.Mistral.chat(messages)
      IO.puts(response.content)

      # Streaming chat
      {:ok, stream} = ExLLM.Providers.Mistral.stream_chat(messages)
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end

      # Function calling
      functions = [
        %{
          name: "get_weather",
          description: "Get weather information",
          parameters: %{
            type: "object",
            properties: %{
              location: %{type: "string", description: "City name"}
            }
          }
        }
      ]

      {:ok, response} = ExLLM.Providers.Mistral.chat(messages, tools: functions)
  """

  import ExLLM.Providers.Shared.ModelUtils, only: [format_model_name: 1]

  use ExLLM.Providers.OpenAICompatible,
    provider: :mistral,
    base_url: "https://api.mistral.ai/v1"

  alias ExLLM.Infrastructure.Config.ModelConfig
  alias ExLLM.Types
  alias ExLLM.Providers.Shared.{ConfigHelper, ResponseBuilder, Validation}
  import ExLLM.Providers.Shared.ModelUtils, only: [generate_description: 2]
  alias ExLLM.Infrastructure.Error, as: Error

  # Note: Temperature validation is removed as it's not critical
  # The API will validate and return an error if temperature is out of range

  @impl ExLLM.Provider
  def embeddings(inputs, options \\ []) do
    with config_provider <- ConfigHelper.get_config_provider(options),
         config <- get_config(config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      model = Keyword.get(options, :model, "mistral-embed")

      inputs_list =
        case inputs do
          input when is_binary(input) -> [input]
          inputs when is_list(inputs) -> inputs
        end

      body = %{
        "model" => model,
        "input" => inputs_list,
        "encoding_format" => Keyword.get(options, :encoding_format, "float")
      }

      headers = get_headers(api_key, options)
      url = "#{get_base_url(config)}/embeddings"

      case send_request(url, body, headers) do
        {:ok, response} ->
          {:ok, ResponseBuilder.build_embedding_response(response, model, provider: :mistral)}

        {:error, error} ->
          handle_error(error)
      end
    else
      {:error, _reason} = error -> error
    end
  end

  @impl ExLLM.Provider
  def list_models(options) do
    with config_provider <- ConfigHelper.get_config_provider(options),
         config <- get_config(config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      headers = get_headers(api_key, options)
      url = "#{get_base_url(config)}/models"

      case send_request(url, %{}, headers, :get) do
        {:ok, %{"data" => models}} when is_list(models) ->
          parsed_models =
            models
            |> Enum.map(&parse_model/1)
            |> Enum.sort_by(& &1.id)

          {:ok, parsed_models}

        _ ->
          load_models_from_config()
      end
    else
      _ ->
        load_models_from_config()
    end
  end

  @impl ExLLM.Provider
  def default_model(_options \\ []), do: "mistral-tiny"

  # Override OpenAICompatible behavior to add Mistral-specific parameters
  @impl ExLLM.Providers.OpenAICompatible
  def transform_request(request, options) do
    request
    |> add_optional_param(options, :safe_prompt, "safe_prompt")
    |> add_optional_param(options, :random_seed, "random_seed")
  end

  # Override to handle Mistral-specific error format
  @impl ExLLM.Providers.OpenAICompatible
  def parse_error(%{status: 401, body: body}) do
    message = Map.get(body, "message", "Invalid API key")
    {:error, Error.authentication_error(message)}
  end

  def parse_error(%{status: 429, body: body}) do
    message = Map.get(body, "message", inspect(body))
    {:error, Error.rate_limit_error(message)}
  end

  def parse_error(%{status: status, body: body}) when status >= 500 do
    message = Map.get(body, "message", inspect(body))
    {:error, Error.api_error(status, message)}
  end

  def parse_error(%{status: status, body: body}) do
    message = Map.get(body, "message", inspect(body))
    {:error, Error.api_error(status, message)}
  end

  # Override to parse models from Mistral's API response
  @impl ExLLM.Providers.OpenAICompatible
  def parse_model(model) do
    model_id = model["id"]
    has_vision = String.contains?(model_id, "pixtral")
    features = ["streaming", "function_calling"] ++ if has_vision, do: ["vision"], else: []

    %Types.Model{
      id: model_id,
      name: ExLLM.Providers.Shared.ModelUtils.format_model_name(model_id),
      description: "Mistral model: #{model_id}",
      context_window: 32_000,
      max_output_tokens: nil,
      capabilities: %{
        supports_streaming: true,
        supports_functions: true,
        supports_vision: has_vision,
        features: features
      }
    }
  end

  # Private helpers

  defp load_models_from_config do
    models_map = ModelConfig.get_all_models(:mistral)

    if map_size(models_map) > 0 do
      models =
        models_map
        |> Enum.map(fn {model_id, config} ->
          model_id_str = to_string(model_id)
          features = Map.get(config, :capabilities, ["streaming"])

          %Types.Model{
            id: model_id_str,
            name: ExLLM.Providers.Shared.ModelUtils.format_model_name(model_id_str),
            description:
              Map.get(config, :description) ||
                generate_description(model_id_str, :mistral),
            context_window: Map.get(config, :context_window, 32_000),
            max_output_tokens: Map.get(config, :max_output_tokens),
            pricing: Map.get(config, :pricing),
            capabilities: %{
              supports_streaming: :streaming in features,
              supports_functions: :function_calling in features,
              supports_vision: :vision in features,
              features: features
            }
          }
        end)
        |> Enum.sort_by(& &1.id)

      {:ok, models}
    else
      {:ok, default_config_models()}
    end
  end

  defp default_config_models do
    [
      %Types.Model{
        id: "mistral/mistral-tiny",
        name: "Mistral Tiny",
        description: "Small and fast model for simple tasks",
        context_window: 32_000,
        max_output_tokens: 8191,
        capabilities: %{
          supports_streaming: true,
          supports_functions: false,
          supports_vision: false,
          features: ["streaming"]
        }
      },
      %Types.Model{
        id: "mistral/mistral-small-latest",
        name: "Mistral Small",
        description: "Balanced model for most use cases",
        context_window: 32_000,
        max_output_tokens: 8191,
        capabilities: %{
          supports_streaming: true,
          supports_functions: true,
          supports_vision: false,
          features: ["streaming", "function_calling"]
        }
      }
    ]
  end
end
