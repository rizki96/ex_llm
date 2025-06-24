defmodule ExLLM.Providers.Perplexity do
  @moduledoc """
  Perplexity AI API adapter for ExLLM.

  Perplexity AI provides search-augmented language models that combine LLM capabilities
  with real-time web search. Their models include:

  ## Search Models
  - Sonar: Lightweight, cost-effective search model
  - Sonar Pro: Advanced search with grounding for complex queries

  ## Research Models
  - Sonar Deep Research: Expert-level research conducting exhaustive searches

  ## Reasoning Models
  - Sonar Reasoning: Chain of thought reasoning with web search
  - Sonar Reasoning Pro: Premier reasoning powered by DeepSeek R1

  ## Standard Models
  - Various Llama, CodeLlama, and Mistral models without search capabilities

  ## Configuration

  This adapter requires a Perplexity API key and optionally a base URL.

  ### Using Environment Variables

      # Set environment variables
      export PERPLEXITY_API_KEY="pplx-your-api-key"
      export PERPLEXITY_MODEL="perplexity/sonar-pro"  # optional
      export PERPLEXITY_API_BASE="https://api.perplexity.ai"  # optional

      # Use with default environment provider
      ExLLM.Providers.Perplexity.chat(messages, config_provider: ExLLM.Infrastructure.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        perplexity: %{
          api_key: "pplx-your-api-key",
          model: "perplexity/sonar-pro",
          base_url: "https://api.perplexity.ai"  # optional
        }
      }
      {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)
      ExLLM.Providers.Perplexity.chat(messages, config_provider: provider)

  ## Example Usage

      messages = [
        %{role: "user", content: "What's the latest news in AI research?"}
      ]

      # Simple search-augmented chat
      {:ok, response} = ExLLM.Providers.Perplexity.chat(messages, model: "perplexity/sonar-pro")
      IO.puts(response.content)

      # Academic search mode
      {:ok, response} = ExLLM.Providers.Perplexity.chat(messages,
        model: "perplexity/sonar-pro",
        search_mode: "academic",
        web_search_options: %{search_context_size: "medium"}
      )

      # Deep research with high reasoning effort
      {:ok, response} = ExLLM.Providers.Perplexity.chat(messages,
        model: "perplexity/sonar-deep-research",
        reasoning_effort: "high"
      )

      # Streaming search results
      {:ok, stream} = ExLLM.Providers.Perplexity.stream_chat(messages,
        model: "perplexity/sonar",
        search_mode: "news"
      )
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end
  """

  import ExLLM.Providers.Shared.ModelUtils, only: [format_model_name: 1, generate_description: 2]
  import ExLLM.Providers.OpenAICompatible, only: [default_model_transformer: 2]

  use ExLLM.Providers.OpenAICompatible,
    provider: :perplexity,
    base_url: "https://api.perplexity.ai"

  alias ExLLM.Infrastructure.Config.ModelConfig
  alias ExLLM.Types

  @max_filter_items 10
  @valid_search_modes ["news", "academic", "general"]
  @valid_reasoning_efforts ["low", "medium", "high"]

  @impl ExLLM.Provider
  def default_model, do: "perplexity/sonar"

  # Override chat and stream_chat to add Perplexity-specific validation
  @impl ExLLM.Provider
  def chat(messages, options) do
    with :ok <- validate_perplexity_parameters(options) do
      super(messages, options)
    end
  end

  @impl ExLLM.Provider
  def stream_chat(messages, options) do
    with :ok <- validate_perplexity_parameters(options) do
      super(messages, options)
    end
  end

  # Override list_models to provide fallback to config
  @impl ExLLM.Provider
  # NOTE: Defensive error handling - super() currently only returns {:ok, models}
  # but this error clause provides safety if parent implementations change
  def list_models(options \\ []) do
    case super(options) do
      {:ok, models} ->
        {:ok, models}

      {:error, _reason} ->
        # Fallback to configuration-based models if API fails
        load_models_from_config()
    end
  end

  # Override OpenAICompatible behavior to add Perplexity-specific parameters
  @impl ExLLM.Providers.OpenAICompatible
  def transform_request(request, options) do
    request
    |> add_optional_param(options, :search_mode, "search_mode")
    |> add_optional_param(options, :web_search_options, "web_search_options")
    |> add_optional_param(options, :reasoning_effort, "reasoning_effort")
    |> add_optional_param(options, :return_images, "return_images")
    |> add_optional_param(options, :image_domain_filter, "image_domain_filter")
    |> add_optional_param(options, :image_format_filter, "image_format_filter")
    |> add_optional_param(options, :recency_filter, "recency_filter")
    # Perplexity uses a different default temperature
    |> Map.put_new("temperature", 0.2)
  end

  # Override to parse models from Perplexity's API response
  @impl ExLLM.Providers.OpenAICompatible
  def parse_model(model) do
    model_id = model["id"]
    web_search = supports_web_search?(model_id)
    reasoning = supports_reasoning?(model_id)

    features = ["streaming"]
    features = if web_search, do: ["web_search" | features], else: features
    features = if reasoning, do: ["reasoning" | features], else: features

    %Types.Model{
      id: model_id,
      name: format_model_name(model_id),
      description: generate_description(model_id, :perplexity),
      # Default for most Perplexity models
      context_window: 128_000,
      # Default max output
      max_output_tokens: 8000,
      capabilities: %{
        supports_streaming: true,
        supports_functions: false,
        supports_vision: false,
        features: features
      }
    }
  end

  @impl ExLLM.Provider
  def embeddings(_inputs, _options) do
    {:error, {:not_implemented, :perplexity_embeddings}}
  end

  # Public helper functions for model classification

  @doc """
  Checks if a model supports web search capabilities.
  """
  @spec supports_web_search?(String.t()) :: boolean()
  def supports_web_search?(model_id) when is_binary(model_id) do
    String.contains?(model_id, "sonar") and not String.contains?(model_id, "chat")
  end

  @doc """
  Checks if a model supports reasoning capabilities.
  """
  @spec supports_reasoning?(String.t()) :: boolean()
  def supports_reasoning?(model_id) when is_binary(model_id) do
    String.contains?(model_id, "reasoning") or String.contains?(model_id, "deep-research")
  end

  # Parameter validation functions

  @doc """
  Validates search_mode parameter.
  """
  @spec validate_search_mode(String.t()) :: :ok | {:error, String.t()}
  def validate_search_mode(mode) when mode in @valid_search_modes, do: :ok

  def validate_search_mode(mode) when is_binary(mode) do
    {:error,
     "Invalid search_mode '#{mode}'. Valid options: #{Enum.join(@valid_search_modes, ", ")}"}
  end

  def validate_search_mode(_), do: {:error, "search_mode must be a string"}

  @doc """
  Validates reasoning_effort parameter.
  """
  @spec validate_reasoning_effort(String.t()) :: :ok | {:error, String.t()}
  def validate_reasoning_effort(effort) when effort in @valid_reasoning_efforts, do: :ok

  def validate_reasoning_effort(effort) when is_binary(effort) do
    {:error,
     "Invalid reasoning_effort '#{effort}'. Valid options: #{Enum.join(@valid_reasoning_efforts, ", ")}"}
  end

  def validate_reasoning_effort(_), do: {:error, "reasoning_effort must be a string"}

  @doc """
  Validates image filter parameters (domain or format filters).
  """
  @spec validate_image_filters(list(String.t())) :: :ok | {:error, String.t()}
  def validate_image_filters(filters) when is_list(filters) do
    if length(filters) <= @max_filter_items do
      :ok
    else
      {:error, "Image filters can have a maximum of #{@max_filter_items} entries"}
    end
  end

  def validate_image_filters(_), do: {:error, "Image filters must be a list of strings"}

  # Private helper functions

  defp validate_perplexity_parameters(options) do
    with :ok <-
           (case Keyword.get(options, :search_mode) do
              nil -> :ok
              mode -> validate_search_mode(mode)
            end),
         :ok <-
           (case Keyword.get(options, :reasoning_effort) do
              nil -> :ok
              effort -> validate_reasoning_effort(effort)
            end),
         :ok <- validate_image_filter_param(options, :image_domain_filter) do
      validate_image_filter_param(options, :image_format_filter)
    end
  end

  defp validate_image_filter_param(options, param_key) do
    case Keyword.get(options, param_key) do
      nil -> :ok
      filters -> validate_image_filters(filters)
    end
  end

  defp load_models_from_config do
    models_map = ModelConfig.get_all_models(:perplexity)

    if map_size(models_map) > 0 do
      # Convert the map of model configs to Model structs
      models =
        models_map
        |> Enum.map(fn {model_id, config} ->
          model_id_str = to_string(model_id)

          %Types.Model{
            id: model_id_str,
            name: format_model_name(model_id_str),
            description: generate_description(model_id_str, :perplexity),
            context_window: Map.get(config, :context_window) || 128_000,
            max_output_tokens: Map.get(config, :max_output_tokens) || 8000,
            pricing: Map.get(config, :pricing),
            capabilities: %{
              features: Map.get(config, :capabilities) || ["streaming"]
            }
          }
        end)
        |> Enum.sort_by(& &1.id)

      {:ok, models}
    else
      # Return some default models if config loading fails
      {:ok,
       [
         %Types.Model{
           id: "perplexity/sonar",
           name: "Sonar",
           description: "Lightweight search model with grounding",
           context_window: 128_000,
           max_output_tokens: 8000,
           capabilities: %{features: ["streaming", "web_search"]}
         },
         %Types.Model{
           id: "perplexity/sonar-pro",
           name: "Sonar Pro",
           description: "Advanced search with grounding for complex queries",
           context_window: 200_000,
           max_output_tokens: 8000,
           capabilities: %{features: ["streaming", "web_search"]}
         }
       ]}
    end
  end
end
