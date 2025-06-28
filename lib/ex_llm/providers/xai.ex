defmodule ExLLM.Providers.XAI do
  @moduledoc """
  Adapter for X.AI's Grok models using OpenAI-compatible base.

  X.AI provides access to the Grok family of models including Grok-3, Grok-2,
  and their variants with different capabilities (vision, reasoning, etc.).

  ## Configuration

  The adapter requires an API key to be configured:

      config :ex_llm, :xai,
        api_key: System.get_env("XAI_API_KEY")

  Or using environment variables:
  - `XAI_API_KEY` - Your X.AI API key

  ## Supported Models

  - `grok-beta` - Grok Beta with 131K context
  - `grok-2-vision-1212` - Grok 2 with vision support
  - `grok-3-beta` - Grok 3 Beta with reasoning capabilities
  - `grok-3-mini-beta` - Smaller, faster Grok 3 variant

  See `config/models/xai.yml` for the full list of models.

  ## Features

  - ✅ Streaming support
  - ✅ Function calling
  - ✅ Vision support (for vision models)
  - ✅ Web search capabilities
  - ✅ Structured outputs
  - ✅ Tool choice
  - ✅ Reasoning (Grok-3 models)

  ## Example

      # Basic chat
      {:ok, response} = ExLLM.chat(:xai, [
        %{role: "user", content: "What is the meaning of life?"}
      ])

      # With vision
      {:ok, response} = ExLLM.chat(:xai, [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,..."}}
          ]
        }
      ])
  """

  alias ExLLM.Infrastructure.Config.ModelConfig
  alias ExLLM.Types
  import ExLLM.Providers.Shared.ModelUtils, only: [format_model_name: 1]

  use ExLLM.Providers.OpenAICompatible,
    provider: :xai,
    base_url: "https://api.x.ai"

  # Override to use pipeline instead of direct HTTP calls
  @impl ExLLM.Provider
  def chat(messages, options) do
    ExLLM.Core.Chat.chat(:xai, messages, options)
  end

  @impl ExLLM.Provider
  def stream_chat(messages, options) do
    ExLLM.Core.Chat.stream_chat(:xai, messages, options)
  end

  # Allow overriding list_models from the base implementation
  defoverridable list_models: 0

  # Override base implementation for XAI-specific features

  @impl ExLLM.Providers.OpenAICompatible
  def get_base_url(config) do
    Map.get(config, :base_url, "https://api.x.ai")
  end

  @impl ExLLM.Providers.OpenAICompatible
  def get_api_key(config) do
    Map.get(config, :api_key) || System.get_env("XAI_API_KEY")
  end

  @impl ExLLM.Providers.OpenAICompatible
  def transform_request(request, _options) do
    # XAI uses standard OpenAI format, no transformation needed
    request
  end

  @impl ExLLM.Providers.OpenAICompatible
  def transform_response(response, _options) do
    # XAI uses standard OpenAI format, no transformation needed
    response
  end

  @impl ExLLM.Providers.OpenAICompatible
  def get_headers(api_key, _options) do
    [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]
  end

  @impl ExLLM.Providers.OpenAICompatible
  def parse_error(%{"error" => error}) do
    message =
      case error do
        %{"message" => msg} -> msg
        msg when is_binary(msg) -> msg
        _ -> "Unknown XAI API error"
      end

    {:error, message}
  end

  def parse_error(_), do: {:error, "Unknown XAI API error"}

  @impl ExLLM.Providers.OpenAICompatible
  def filter_model(_model) do
    # Accept all models from XAI
    true
  end

  @impl ExLLM.Providers.OpenAICompatible
  def parse_model(model) do
    model_id = model["id"]

    # Load model config from YAML
    case ModelConfig.get_model_config(:xai, model_id) do
      {:ok, config} ->
        %Types.Model{
          id: model_id,
          name: "X.AI " <> format_model_name(model_id),
          description: config.description || "X.AI model: #{model_id}",
          context_window: config.context_window || 131_072,
          max_output_tokens: config.max_output_tokens,
          capabilities: %{
            supports_streaming: :streaming in (config.capabilities || []),
            supports_functions: :function_calling in (config.capabilities || []),
            supports_vision: :vision in (config.capabilities || []),
            features: config.capabilities || []
          }
        }

      {:error, _} ->
        # Fallback for models not in config
        %Types.Model{
          id: model_id,
          name: "X.AI " <> format_model_name(model_id),
          description: "X.AI model: #{model_id}",
          # Default for Grok models
          context_window: 131_072,
          capabilities: %{
            supports_streaming: true,
            supports_functions: true,
            supports_vision: String.contains?(model_id, "vision"),
            features: [:chat, :streaming, :function_calling]
          }
        }
    end
  end

  # Override list_models to use local config since XAI doesn't have a models endpoint
  @impl ExLLM.Provider
  def list_models(_options \\ []) do
    case ModelConfig.get_all_models(:xai) do
      models when is_map(models) ->
        formatted_models =
          Enum.map(models, fn {id, model_data} ->
            # Convert string capabilities to atoms safely
            capabilities_list = convert_capabilities(model_data)

            %Types.Model{
              id: to_string(id),
              name: "X.AI " <> format_model_name(to_string(id)),
              context_window: Map.get(model_data, :context_window, 131_072),
              max_output_tokens: Map.get(model_data, :max_output_tokens),
              # Convert to map format for consistency
              capabilities: %{
                supports_streaming: :streaming in capabilities_list,
                supports_functions: :function_calling in capabilities_list,
                supports_vision: :vision in capabilities_list,
                features: capabilities_list
              }
            }
          end)

        {:ok, formatted_models}

      _ ->
        {:error, "Failed to load XAI models from configuration"}
    end
  end

  # Add default_model/0 for backward compatibility
  @impl ExLLM.Provider
  def default_model(_options \\ []) do
    case ModelConfig.get_default_model(:xai) do
      {:ok, model} -> model
      # Fallback default
      _ -> "grok-beta"
    end
  end

  # XAI doesn't support embeddings
  @impl ExLLM.Provider
  def embeddings(_input, _options \\ []) do
    {:error, {:not_supported, "XAI does not support embeddings API"}}
  end

  defp convert_capabilities(model_data) do
    model_data
    |> Map.get(:capabilities, [])
    |> Enum.map(fn
      cap when is_binary(cap) ->
        # Only convert known capability atoms
        case cap do
          "chat" -> :chat
          "streaming" -> :streaming
          "function_calling" -> :function_calling
          "vision" -> :vision
          "audio" -> :audio
          "embeddings" -> :embeddings
          "reasoning" -> :reasoning
          "web_search" -> :web_search
          "tool_choice" -> :tool_choice
          _ -> nil
        end

      cap when is_atom(cap) ->
        cap
    end)
    |> Enum.filter(&(&1 != nil))
  end
end
