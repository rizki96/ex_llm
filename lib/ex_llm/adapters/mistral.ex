defmodule ExLLM.Adapters.Mistral do
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
      ExLLM.Adapters.Mistral.chat(messages, config_provider: ExLLM.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        mistral: %{
          api_key: "your-api-key",
          model: "mistral/mistral-small-latest",
          base_url: "https://api.mistral.ai/v1"  # optional
        }
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      ExLLM.Adapters.Mistral.chat(messages, config_provider: provider)

  ## Example Usage

      messages = [
        %{role: "user", content: "Explain quantum computing"}
      ]

      # Simple chat
      {:ok, response} = ExLLM.Adapters.Mistral.chat(messages)
      IO.puts(response.content)

      # Streaming chat
      {:ok, stream} = ExLLM.Adapters.Mistral.stream_chat(messages)
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

      {:ok, response} = ExLLM.Adapters.Mistral.chat(messages, tools: functions)
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

  @default_base_url "https://api.mistral.ai/v1"
  @default_temperature 0.7

  @impl true
  def chat(messages, options \\ []) do
    with :ok <- MessageFormatter.validate_messages(messages),
         :ok <- validate_unsupported_parameters(options),
         config_provider <- ConfigHelper.get_config_provider(options),
         config <- ConfigHelper.get_config(:mistral, config_provider),
         api_key <- ConfigHelper.get_api_key(config, "MISTRAL_API_KEY"),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      model =
        Keyword.get(
          options,
          :model,
          Map.get(config, :model) || ConfigHelper.ensure_default_model(:mistral)
        )

      body = build_request_body(messages, model, config, options)
      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/chat/completions"

      Logger.with_context([provider: :mistral, model: model], fn ->
        case HTTPClient.post_json(url, body, headers, timeout: 60_000, provider: :mistral) do
          {:ok, response} ->
            {:ok, parse_response(response, model)}

          {:error, {:api_error, %{status: status, body: body}}} ->
            ErrorHandler.handle_provider_error(:mistral, status, body)

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    with :ok <- MessageFormatter.validate_messages(messages),
         config_provider <- ConfigHelper.get_config_provider(options),
         config <- ConfigHelper.get_config(:mistral, config_provider),
         api_key <- ConfigHelper.get_api_key(config, "MISTRAL_API_KEY"),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      model =
        Keyword.get(
          options,
          :model,
          Map.get(config, :model) || ConfigHelper.ensure_default_model(:mistral)
        )

      body = build_request_body(messages, model, config, options ++ [stream: true])
      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/chat/completions"

      Logger.with_context([provider: :mistral, model: model], fn ->
        StreamingCoordinator.start_stream(
          url,
          body,
          headers,
          fn chunk -> chunk end,
          parse_chunk_fn: &parse_stream_chunk/1,
          provider: :mistral,
          model: model
        )
      end)
    end
  end

  @impl true
  def embeddings(inputs, options \\ []) do
    with config_provider <- ConfigHelper.get_config_provider(options),
         config <- ConfigHelper.get_config(:mistral, config_provider),
         api_key <- ConfigHelper.get_api_key(config, "MISTRAL_API_KEY"),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      model = Keyword.get(options, :model, "mistral/mistral-embed")

      inputs_list =
        case inputs do
          input when is_binary(input) -> [input]
          inputs when is_list(inputs) -> inputs
        end

      body = %{
        model: model,
        input: inputs_list,
        encoding_format: Keyword.get(options, :encoding_format, "float")
      }

      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/embeddings"

      Logger.with_context([provider: :mistral, model: model], fn ->
        case HTTPClient.post_json(url, body, headers, timeout: 60_000, provider: :mistral) do
          {:ok, response} ->
            {:ok, parse_embeddings_response(response, model)}

          {:error, {:api_error, %{status: status, body: body}}} ->
            ErrorHandler.handle_provider_error(:mistral, status, body)

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end
  end

  @impl true
  def list_models(options \\ []) do
    with config_provider <- ConfigHelper.get_config_provider(options),
         config <- ConfigHelper.get_config(:mistral, config_provider),
         api_key <- ConfigHelper.get_api_key(config, "MISTRAL_API_KEY"),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/models"

      case HTTPClient.post_json(url, %{}, headers,
             method: :get,
             timeout: 30_000,
             provider: :mistral
           ) do
        {:ok, %{"data" => models}} ->
          parsed_models =
            models
            |> Enum.map(&parse_model_info/1)
            |> Enum.sort_by(& &1.id)

          {:ok, parsed_models}

        {:error, {:api_error, %{status: status, body: body}}} ->
          Logger.debug("Failed to fetch Mistral models: #{status} - #{inspect(body)}")
          ErrorHandler.handle_provider_error(:mistral, status, body)

        {:error, reason} ->
          Logger.debug("Failed to fetch Mistral models: #{inspect(reason)}")
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
    config = ConfigHelper.get_config(:mistral, config_provider)
    api_key = ConfigHelper.get_api_key(config, "MISTRAL_API_KEY")

    case Validation.validate_api_key(api_key) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def default_model, do: "mistral/mistral-tiny"

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

  # Private helper functions

  defp build_request_body(messages, model, _config, options) do
    # Handle function calling via tools parameter
    tools = build_tools_from_functions(Keyword.get(options, :functions, []))
    tools = tools ++ Keyword.get(options, :tools, [])

    body = %{
      model: model,
      messages: messages,
      temperature: Keyword.get(options, :temperature, @default_temperature),
      max_tokens: Keyword.get(options, :max_tokens),
      stream: Keyword.get(options, :stream, false)
    }

    # Add tools if present
    body =
      if tools != [] do
        Map.put(body, :tools, tools)
      else
        body
      end

    # Add tool_choice if specified
    body =
      case Keyword.get(options, :tool_choice) do
        nil -> body
        choice -> Map.put(body, :tool_choice, choice)
      end

    # Add other optional parameters
    body
    |> maybe_add_param(:top_p, Keyword.get(options, :top_p))
    |> maybe_add_param(:random_seed, Keyword.get(options, :seed))
    |> maybe_add_param(:safe_prompt, Keyword.get(options, :safe_prompt, false))
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  defp build_tools_from_functions(functions) when is_list(functions) do
    Enum.map(functions, fn function ->
      %{
        type: "function",
        function: function
      }
    end)
  end

  defp build_tools_from_functions(_), do: []

  defp maybe_add_param(body, _key, nil), do: body
  defp maybe_add_param(body, key, value), do: Map.put(body, key, value)

  defp build_headers(api_key, _config) do
    HTTPClient.build_provider_headers(:mistral, api_key: api_key)
  end

  defp get_base_url(config) do
    Map.get(config, :base_url) || @default_base_url
  end

  defp parse_response(response, model) do
    ResponseBuilder.build_chat_response(response, model, provider: :mistral)
  end

  defp parse_embeddings_response(response, model) do
    ResponseBuilder.build_embedding_response(response, model, provider: :mistral)
  end

  defp parse_model_info(model_data) do
    %Types.Model{
      id: model_data["id"],
      name: ModelUtils.format_model_name(model_data["id"]),
      description: ModelUtils.generate_description(model_data["id"], :mistral),
      context_window: 32000,
      max_output_tokens: 8191,
      capabilities: %{
        features: ["streaming", "function_calling"]
      }
    }
  end

  defp load_models_from_config do
    models_map = ModelConfig.get_all_models(:mistral)
    
    if map_size(models_map) > 0 do
      # Convert the map of model configs to Model structs
      models = 
        models_map
        |> Enum.map(fn {model_id, config} ->
          model_id_str = to_string(model_id)
          %Types.Model{
            id: model_id_str,
            name: ModelUtils.format_model_name(model_id_str),
            description: ModelUtils.generate_description(model_id_str, :mistral),
            context_window: Map.get(config, :context_window) || 32000,
            max_output_tokens: Map.get(config, :max_output_tokens) || 8191,
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
          id: "mistral/mistral-tiny",
          name: "Mistral Tiny",
          description: "Small and fast model for simple tasks",
          context_window: 32000,
          max_output_tokens: 8191,
          capabilities: %{features: ["streaming"]}
        },
        %Types.Model{
          id: "mistral/mistral-small-latest",
          name: "Mistral Small",
          description: "Balanced model for most use cases",
          context_window: 32000,
          max_output_tokens: 8191,
          capabilities: %{features: ["streaming", "function_calling"]}
        }
      ]}
    end
  end

  defp validate_unsupported_parameters(options) do
    # Mistral doesn't support some OpenAI parameters
    unsupported = [:frequency_penalty, :presence_penalty, :logprobs, :n]

    case Enum.find(unsupported, &Keyword.has_key?(options, &1)) do
      nil -> :ok
      param -> {:error, "Parameter #{param} is not supported by Mistral API"}
    end
  end
end