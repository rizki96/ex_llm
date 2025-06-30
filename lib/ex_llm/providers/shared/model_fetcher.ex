defmodule ExLLM.Providers.Shared.ModelFetcher do
  @moduledoc """
  Unified behavior and utilities for fetching models from LLM provider APIs.

  This module standardizes the pattern of:
  1. Fetching models from provider APIs
  2. Filtering out non-LLM models
  3. Parsing model metadata
  4. Transforming to common format
  5. Integrating with ModelLoader for caching

  ## Usage

  Adapters can implement the behavior callbacks or use the helper functions
  to reduce code duplication.
  """

  alias ExLLM.{Infrastructure.Logger, Types}
  alias ExLLM.Providers.Shared.{ConfigHelper, HTTP.Core, ModelUtils}

  @doc """
  Callback to fetch models from the provider's API.

  Should return {:ok, raw_models} or {:error, reason}.
  """
  @callback fetch_models(config :: map()) :: {:ok, list(map())} | {:error, term()}

  @doc """
  Callback to filter out non-LLM models.

  Some providers return embeddings, whisper, etc. that we want to exclude.
  """
  @callback filter_model(model :: map()) :: boolean()

  @doc """
  Callback to parse a raw API model into Types.Model struct.
  """
  @callback parse_api_model(model :: map()) :: Types.Model.t()

  @doc """
  Callback to transform config-based model data.

  Used when loading from YAML configuration.
  """
  @callback transform_model_config(model_id :: atom() | String.t(), config :: map()) ::
              Types.Model.t()

  # Optional callbacks with defaults
  @optional_callbacks [filter_model: 1, transform_model_config: 2]

  @doc """
  Standard implementation for list_models that integrates with ModelLoader.

  This is the main entry point that adapters should use.

  ## Example

      def list_models(options \\ []) do
        ModelFetcher.list_models_with_loader(__MODULE__, :myprovider, options)
      end
  """
  @spec list_models_with_loader(module(), atom(), keyword()) ::
          {:ok, list(Types.Model.t())} | {:error, term()}
  def list_models_with_loader(adapter_module, provider, options \\ []) do
    config_provider = ConfigHelper.get_config_provider(options)
    config = ConfigHelper.get_config(provider, config_provider)

    ExLLM.Infrastructure.Config.ModelLoader.load_models(
      provider,
      Keyword.merge(options,
        api_fetcher: fn _opts -> adapter_module.fetch_models(config) end,
        config_transformer: &get_transformer(adapter_module, &1, &2)
      )
    )
  end

  @doc """
  Fetch models from a standard OpenAI-compatible endpoint.

  Many providers use the same /v1/models endpoint format.
  """
  @spec fetch_openai_compatible_models(String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def fetch_openai_compatible_models(base_url, api_key, options \\ []) do
    # Extract provider from options, default to :openai for OpenAI-compatible endpoints
    provider = Keyword.get(options, :provider, :openai)

    # Build client with provider-specific configuration
    client =
      Core.client(
        provider: provider,
        api_key: api_key,
        base_url: base_url,
        timeout: Keyword.get(options, :timeout, 30_000)
      )

    # Additional headers if needed
    extra_headers = Keyword.get(options, :extra_headers, [])

    case Tesla.get(client, "/v1/models", headers: extra_headers) do
      {:ok, %Tesla.Env{status: 200, body: %{"data" => models}}} when is_list(models) ->
        {:ok, models}

      {:ok, %Tesla.Env{status: 200, body: %{"models" => models}}} when is_list(models) ->
        # Some providers use "models" instead of "data"
        {:ok, models}

      {:ok, %Tesla.Env{status: 200, body: response}} ->
        Logger.warning("Unexpected models API response format: #{inspect(response)}")
        {:error, "Unexpected response format"}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, %{status_code: status, response: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Standard model filtering for common patterns.

  Filters out:
  - Embedding models
  - Whisper/audio models
  - Image generation models
  - Old deprecated models
  """
  @spec standard_model_filter(map(), keyword()) :: boolean()
  def standard_model_filter(model, options \\ []) do
    model_id = model["id"] || ""

    # Allow overriding with includes/excludes
    includes = Keyword.get(options, :include_patterns, [])
    excludes = Keyword.get(options, :exclude_patterns, default_exclude_patterns())

    # Check includes first (if specified)
    passes_include =
      if Enum.empty?(includes) do
        true
      else
        Enum.any?(includes, &String.contains?(model_id, &1))
      end

    # Then check excludes
    passes_exclude = not Enum.any?(excludes, &String.contains?(model_id, &1))

    passes_include && passes_exclude
  end

  @doc """
  Parse a model from API response to Types.Model struct.

  Provides sensible defaults and uses ModelUtils for formatting.
  """
  @spec parse_standard_model(map(), atom(), keyword()) :: Types.Model.t()
  def parse_standard_model(model, provider, options \\ []) do
    model_id = model["id"] || ""

    %ExLLM.Types.Model{
      id: model_id,
      name: ModelUtils.format_model_name(model_id),
      description: model["description"] || ModelUtils.generate_description(model_id, provider),
      context_window: model["context_window"] || get_default_context_window(model_id),
      capabilities: parse_model_capabilities(model, provider, options)
    }
  end

  @doc """
  Transform a model from YAML config to Types.Model struct.

  Standard implementation that most adapters can use.
  """
  @spec transform_standard_config(atom() | String.t(), map(), atom()) :: Types.Model.t()
  def transform_standard_config(model_id, config, provider) do
    %ExLLM.Types.Model{
      id: to_string(model_id),
      name: Map.get(config, :name, ModelUtils.format_model_name(to_string(model_id))),
      description:
        Map.get(
          config,
          :description,
          ModelUtils.generate_description(to_string(model_id), provider)
        ),
      context_window: Map.get(config, :context_window, 4096),
      capabilities: %{
        supports_streaming: :streaming in Map.get(config, :capabilities, []),
        supports_functions: :function_calling in Map.get(config, :capabilities, []),
        supports_vision: :vision in Map.get(config, :capabilities, []),
        features: Map.get(config, :capabilities, [])
      }
    }
  end

  @doc """
  Helper to process raw models through filter and parse pipeline.
  """
  @spec process_models(list(map()), module(), atom(), keyword()) :: list(Types.Model.t())
  def process_models(raw_models, adapter_module, provider, options \\ []) do
    filter_fn =
      if function_exported?(adapter_module, :filter_model, 1) do
        &adapter_module.filter_model/1
      else
        &standard_model_filter(&1, options)
      end

    parse_fn =
      if function_exported?(adapter_module, :parse_api_model, 1) do
        &adapter_module.parse_api_model/1
      else
        &parse_standard_model(&1, provider, options)
      end

    raw_models
    |> Enum.filter(filter_fn)
    |> Enum.map(parse_fn)
    |> Enum.sort_by(& &1.id)
  end

  # Private helpers

  defp get_transformer(adapter_module, model_id, config) do
    if function_exported?(adapter_module, :transform_model_config, 2) do
      adapter_module.transform_model_config(model_id, config)
    else
      # Assumes adapter stores this
      provider = adapter_module.__provider__()
      transform_standard_config(model_id, config, provider)
    end
  end

  defp default_exclude_patterns do
    [
      "embedding",
      "whisper",
      "moderation",
      "instruct",
      # Old OpenAI snapshots
      "0301",
      "0314",
      "0613",
      "dall-e",
      "tts",
      "similarity",
      "search"
    ]
  end

  defp get_default_context_window(model_id) do
    cond do
      String.contains?(model_id, "gpt-4") -> 128_000
      String.contains?(model_id, "gpt-3.5-turbo-16k") -> 16_384
      String.contains?(model_id, "gpt-3.5") -> 4_096
      String.contains?(model_id, "claude") -> 200_000
      String.contains?(model_id, "gemini") -> 32_768
      true -> 4_096
    end
  end

  defp parse_model_capabilities(model, provider, _options) do
    # Extract capabilities from model data
    base_capabilities = %{
      supports_streaming: model["supports_streaming"] != false,
      supports_functions: model["supports_tools"] || model["supports_functions"] || false,
      supports_vision: model["supports_vision"] || model["supports_images"] || false
    }

    # Build features list
    features = []

    features =
      if base_capabilities.supports_streaming, do: ["streaming" | features], else: features

    features =
      if base_capabilities.supports_functions, do: ["function_calling" | features], else: features

    features = if base_capabilities.supports_vision, do: ["vision" | features], else: features

    # Add provider-specific features
    features = features ++ get_provider_features(model, provider)

    Map.put(base_capabilities, :features, features)
  end

  defp get_provider_features(_model, :anthropic) do
    ["system_messages", "xml_mode"]
  end

  defp get_provider_features(_model, :openai) do
    ["logprobs", "response_format"]
  end

  defp get_provider_features(model, :groq) do
    if model["supports_structured_output"], do: ["structured_output"], else: []
  end

  defp get_provider_features(_model, _provider) do
    []
  end
end
