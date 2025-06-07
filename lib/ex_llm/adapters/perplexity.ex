defmodule ExLLM.Adapters.Perplexity do
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
      ExLLM.Adapters.Perplexity.chat(messages, config_provider: ExLLM.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        perplexity: %{
          api_key: "pplx-your-api-key",
          model: "perplexity/sonar-pro",
          base_url: "https://api.perplexity.ai"  # optional
        }
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      ExLLM.Adapters.Perplexity.chat(messages, config_provider: provider)

  ## Example Usage

      messages = [
        %{role: "user", content: "What's the latest news in AI research?"}
      ]

      # Simple search-augmented chat
      {:ok, response} = ExLLM.Adapters.Perplexity.chat(messages, model: "perplexity/sonar-pro")
      IO.puts(response.content)

      # Academic search mode
      {:ok, response} = ExLLM.Adapters.Perplexity.chat(messages, 
        model: "perplexity/sonar-pro",
        search_mode: "academic",
        web_search_options: %{search_context_size: "medium"}
      )

      # Deep research with high reasoning effort
      {:ok, response} = ExLLM.Adapters.Perplexity.chat(messages,
        model: "perplexity/sonar-deep-research", 
        reasoning_effort: "high"
      )

      # Streaming search results
      {:ok, stream} = ExLLM.Adapters.Perplexity.stream_chat(messages,
        model: "perplexity/sonar",
        search_mode: "news"
      )
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end
  """

  @behaviour ExLLM.Adapter
  @behaviour ExLLM.Adapters.Shared.StreamingBehavior

  alias ExLLM.{Logger, ModelConfig, Types}

  alias ExLLM.Adapters.Shared.{
    ConfigHelper,
    ErrorHandler,
    HTTPClient,
    MessageFormatter,
    ModelUtils,
    ResponseBuilder,
    StreamingCoordinator,
    Validation
  }

  @default_base_url "https://api.perplexity.ai"
  @default_temperature 0.2
  @max_filter_items 10

  # Search modes supported by Perplexity
  @valid_search_modes ["news", "academic", "general"]
  
  # Reasoning effort levels for deep research models
  @valid_reasoning_efforts ["low", "medium", "high"]

  @impl true
  def chat(messages, options \\ []) do
    with :ok <- MessageFormatter.validate_messages(messages),
         :ok <- validate_perplexity_parameters(options),
         config_provider <- ConfigHelper.get_config_provider(options),
         config <- ConfigHelper.get_config(:perplexity, config_provider),
         api_key <- ConfigHelper.get_api_key(config, "PERPLEXITY_API_KEY"),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      model =
        Keyword.get(
          options,
          :model,
          Map.get(config, :model) || ConfigHelper.ensure_default_model(:perplexity)
        )

      body = build_request_body(messages, model, config, options)
      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/chat/completions"

      Logger.with_context([provider: :perplexity, model: model], fn ->
        case HTTPClient.post_json(url, body, headers, timeout: 60_000, provider: :perplexity) do
          {:ok, response} ->
            {:ok, parse_response(response, model)}

          {:error, {:api_error, %{status: status, body: body}}} ->
            ErrorHandler.handle_provider_error(:perplexity, status, body)

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    with :ok <- MessageFormatter.validate_messages(messages),
         :ok <- validate_perplexity_parameters(options),
         config_provider <- ConfigHelper.get_config_provider(options),
         config <- ConfigHelper.get_config(:perplexity, config_provider),
         api_key <- ConfigHelper.get_api_key(config, "PERPLEXITY_API_KEY"),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      model =
        Keyword.get(
          options,
          :model,
          Map.get(config, :model) || ConfigHelper.ensure_default_model(:perplexity)
        )

      body = build_request_body(messages, model, config, options ++ [stream: true])
      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/chat/completions"

      Logger.with_context([provider: :perplexity, model: model], fn ->
        StreamingCoordinator.start_stream(
          url,
          body,
          headers,
          fn chunk -> chunk end,
          parse_chunk_fn: &parse_stream_chunk/1,
          provider: :perplexity,
          model: model
        )
      end)
    end
  end

  @impl true
  def list_models(options \\ []) do
    with config_provider <- ConfigHelper.get_config_provider(options),
         config <- ConfigHelper.get_config(:perplexity, config_provider),
         api_key <- ConfigHelper.get_api_key(config, "PERPLEXITY_API_KEY"),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/models"

      case HTTPClient.post_json(url, %{}, headers,
             method: :get,
             timeout: 30_000,
             provider: :perplexity
           ) do
        {:ok, %{"data" => models}} ->
          parsed_models =
            models
            |> Enum.map(&parse_model_info/1)
            |> Enum.sort_by(& &1.id)

          {:ok, parsed_models}

        {:error, {:api_error, %{status: status, body: body}}} ->
          Logger.debug("Failed to fetch Perplexity models: #{status} - #{inspect(body)}")
          ErrorHandler.handle_provider_error(:perplexity, status, body)

        {:error, reason} ->
          Logger.debug("Failed to fetch Perplexity models: #{inspect(reason)}")
          {:error, reason}
      end
    else
      # Fallback to configuration-based models if API fails
      _ ->
        load_models_from_config()
    end
  end

  @impl true
  def configured?(options \\ []) do
    config_provider = ConfigHelper.get_config_provider(options)
    config = ConfigHelper.get_config(:perplexity, config_provider)
    api_key = ConfigHelper.get_api_key(config, "PERPLEXITY_API_KEY")

    case Validation.validate_api_key(api_key) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def default_model, do: "perplexity/sonar"

  # StreamingBehavior implementation
  @impl ExLLM.Adapters.Shared.StreamingBehavior
  def parse_stream_chunk(chunk) do
    case Jason.decode(chunk) do
      {:ok, %{"choices" => [%{"delta" => delta, "finish_reason" => finish_reason} | _]}} ->
        content = delta["content"]

        if content || finish_reason do
          %Types.StreamChunk{
            content: content,
            finish_reason: finish_reason
          }
        else
          nil
        end

      {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
        content = delta["content"]

        if content do
          %Types.StreamChunk{
            content: content,
            finish_reason: nil
          }
        else
          nil
        end

      _ ->
        nil
    end
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
    {:error, "Invalid search_mode '#{mode}'. Valid options: #{Enum.join(@valid_search_modes, ", ")}"}
  end
  def validate_search_mode(_), do: {:error, "search_mode must be a string"}

  @doc """
  Validates reasoning_effort parameter.
  """
  @spec validate_reasoning_effort(String.t()) :: :ok | {:error, String.t()}
  def validate_reasoning_effort(effort) when effort in @valid_reasoning_efforts, do: :ok
  def validate_reasoning_effort(effort) when is_binary(effort) do
    {:error, "Invalid reasoning_effort '#{effort}'. Valid options: #{Enum.join(@valid_reasoning_efforts, ", ")}"}
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

  defp build_request_body(messages, model, _config, options) do
    body = %{
      model: model,
      messages: messages,
      temperature: Keyword.get(options, :temperature, @default_temperature),
      stream: Keyword.get(options, :stream, false)
    }

    # Add optional parameters
    body
    |> maybe_add_param(:max_tokens, Keyword.get(options, :max_tokens))
    |> maybe_add_param(:top_p, Keyword.get(options, :top_p))
    |> maybe_add_param(:presence_penalty, Keyword.get(options, :presence_penalty))
    |> maybe_add_param(:frequency_penalty, Keyword.get(options, :frequency_penalty))
    # Perplexity-specific parameters
    |> maybe_add_param(:search_mode, Keyword.get(options, :search_mode))
    |> maybe_add_param(:web_search_options, Keyword.get(options, :web_search_options))
    |> maybe_add_param(:reasoning_effort, Keyword.get(options, :reasoning_effort))
    |> maybe_add_param(:return_images, Keyword.get(options, :return_images))
    |> maybe_add_param(:image_domain_filter, Keyword.get(options, :image_domain_filter))
    |> maybe_add_param(:image_format_filter, Keyword.get(options, :image_format_filter))
    |> maybe_add_param(:recency_filter, Keyword.get(options, :recency_filter))
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  defp maybe_add_param(body, _key, nil), do: body
  defp maybe_add_param(body, key, value), do: Map.put(body, key, value)

  defp build_headers(api_key, _config) do
    HTTPClient.build_provider_headers(:perplexity, api_key: api_key)
  end

  defp get_base_url(config) do
    Map.get(config, :base_url) || @default_base_url
  end

  defp parse_response(response, model) do
    ResponseBuilder.build_chat_response(response, model, provider: :perplexity)
  end

  defp parse_model_info(model_data) do
    %Types.Model{
      id: model_data["id"],
      name: ModelUtils.format_model_name(model_data["id"]),
      description: ModelUtils.generate_description(model_data["id"], :perplexity),
      context_window: 128000,  # Default for most Perplexity models
      max_output_tokens: 8000, # Default max output
      capabilities: build_model_capabilities(model_data["id"])
    }
  end

  defp build_model_capabilities(model_id) do
    features = ["streaming"]

    features =
      if supports_web_search?(model_id) do
        ["web_search" | features]
      else
        features
      end

    features =
      if supports_reasoning?(model_id) do
        ["reasoning" | features]
      else
        features
      end

    %{features: features}
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
            name: ModelUtils.format_model_name(model_id_str),
            description: ModelUtils.generate_description(model_id_str, :perplexity),
            context_window: Map.get(config, :context_window) || 128000,
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
      {:ok, [
        %Types.Model{
          id: "perplexity/sonar",
          name: "Sonar",
          description: "Lightweight search model with grounding",
          context_window: 128000,
          max_output_tokens: 8000,
          capabilities: %{features: ["streaming", "web_search"]}
        },
        %Types.Model{
          id: "perplexity/sonar-pro", 
          name: "Sonar Pro",
          description: "Advanced search with grounding for complex queries",
          context_window: 200000,
          max_output_tokens: 8000,
          capabilities: %{features: ["streaming", "web_search"]}
        }
      ]}
    end
  end

  defp validate_perplexity_parameters(options) do
    # Validate search mode if provided
    case Keyword.get(options, :search_mode) do
      nil -> :ok
      mode -> validate_search_mode(mode)
    end
    |> case do
      :ok ->
        # Validate reasoning effort if provided
        case Keyword.get(options, :reasoning_effort) do
          nil -> :ok
          effort -> validate_reasoning_effort(effort)
        end

      error -> error
    end
    |> case do
      :ok ->
        # Validate image filters if provided
        with :ok <- validate_image_filter_param(options, :image_domain_filter),
             :ok <- validate_image_filter_param(options, :image_format_filter) do
          :ok
        end

      error -> error
    end
  end

  defp validate_image_filter_param(options, param_key) do
    case Keyword.get(options, param_key) do
      nil -> :ok
      filters -> validate_image_filters(filters)
    end
  end
end