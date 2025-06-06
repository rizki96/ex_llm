defmodule ExLLM.Adapters.OpenAI do
  @moduledoc """
  OpenAI GPT API adapter for ExLLM.

  ## Configuration

  This adapter requires an OpenAI API key and optionally a base URL.

  ### Using Environment Variables

      # Set environment variables
      export OPENAI_API_KEY="your-api-key"
      export OPENAI_MODEL="gpt-4-turbo"  # optional
      export OPENAI_API_BASE="https://api.openai.com/v1"  # optional

      # Use with default environment provider
      ExLLM.Adapters.OpenAI.chat(messages, config_provider: ExLLM.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        openai: %{
          api_key: "your-api-key",
          model: "gpt-4-turbo",
          base_url: "https://api.openai.com/v1"  # optional
        }
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      ExLLM.Adapters.OpenAI.chat(messages, config_provider: provider)

  ## Example Usage

      messages = [
        %{role: "user", content: "Hello, how are you?"}
      ]

      # Simple chat
      {:ok, response} = ExLLM.Adapters.OpenAI.chat(messages)
      IO.puts(response.content)

      # Streaming chat
      {:ok, stream} = ExLLM.Adapters.OpenAI.stream_chat(messages)
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end
  """

  @behaviour ExLLM.Adapter
  @behaviour ExLLM.Adapters.Shared.StreamingBehavior

  alias ExLLM.{Error, Types, ModelConfig}
  alias ExLLM.Adapters.Shared.{ConfigHelper, HTTPClient, ErrorHandler, MessageFormatter, StreamingBehavior, Validation, ModelUtils}
  require Logger

  @default_base_url "https://api.openai.com/v1"
  @default_temperature 0.7

  @impl true
  def chat(messages, options \\ []) do
    with :ok <- MessageFormatter.validate_messages(messages),
         config_provider <- ConfigHelper.get_config_provider(options),
         config <- ConfigHelper.get_config(:openai, config_provider),
         api_key <- ConfigHelper.get_api_key(config, "OPENAI_API_KEY"),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      
      model = Keyword.get(options, :model, Map.get(config, :model) || ConfigHelper.ensure_default_model(:openai))
      
      body = build_request_body(messages, model, config, options)
      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/chat/completions"
      
      case HTTPClient.post_json(url, body, headers, timeout: 60_000) do
        {:ok, response} ->
          {:ok, parse_response(response, model)}
          
        {:error, {:api_error, %{status: status, body: body}}} ->
          ErrorHandler.handle_provider_error(:openai, status, body)
          
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    with :ok <- MessageFormatter.validate_messages(messages),
         config_provider <- ConfigHelper.get_config_provider(options),
         config <- ConfigHelper.get_config(:openai, config_provider),
         api_key <- ConfigHelper.get_api_key(config, "OPENAI_API_KEY"),
         {:ok, _} <- Validation.validate_api_key(api_key) do
      
      model = Keyword.get(options, :model, Map.get(config, :model) || ConfigHelper.ensure_default_model(:openai))
      
      body = 
        messages
        |> build_request_body(model, config, options)
        |> Map.put(:stream, true)
        
      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/chat/completions"
      parent = self()
      ref = make_ref()
      
      # Start streaming task
      Task.start(fn ->
        HTTPClient.stream_request(url, body, headers, 
          fn chunk -> send(parent, {ref, {:chunk, chunk}}) end,
          on_error: fn status, body -> 
            send(parent, {ref, {:error, ErrorHandler.handle_provider_error(:openai, status, body)}})
          end
        )
        
        # Wait for stream completion and forward the done signal
        receive do
          :stream_done -> send(parent, {ref, :done})
          {:stream_error, error} -> send(parent, {ref, {:error, error}})
        after
          60_000 -> send(parent, {ref, {:error, :timeout}})
        end
      end)
      
      # Create stream that processes chunks
      stream = Stream.resource(
        fn -> {ref, model} end,
        fn {ref, _model} = state ->
          receive do
            {^ref, {:chunk, data}} ->
              case parse_stream_chunk(data) do
                {:ok, :done} -> {:halt, state}
                {:ok, chunk} -> {[chunk], state}
                {:error, _} -> {[], state}  # Skip bad chunks
              end
              
            {^ref, :done} -> {:halt, state}
            {^ref, {:error, error}} -> throw(error)
          after
            100 -> {[], state}
          end
        end,
        fn _ -> :ok end
      )
      
      {:ok, stream}
    end
  end

  @impl true
  def list_models(options \\ []) do
    config_provider = ConfigHelper.get_config_provider(options)
    config = ConfigHelper.get_config(:openai, config_provider)
    
    # Use ModelLoader with API fetching
    ExLLM.ModelLoader.load_models(:openai,
      Keyword.merge(options, [
        api_fetcher: fn(_opts) -> fetch_openai_models(config) end,
        config_transformer: &openai_model_transformer/2
      ])
    )
  end
  
  defp fetch_openai_models(config) do
    api_key = ConfigHelper.get_api_key(config, "OPENAI_API_KEY")

    case Validation.validate_api_key(api_key) do
      {:error, _} = error -> error
      {:ok, _} ->
        headers = build_headers(api_key, config)
        url = "#{get_base_url(config)}/models"

        case Req.get(url, headers: headers) do
          {:ok, %{status: 200, body: %{"data" => data}}} ->
            models =
              data
              |> Enum.filter(&is_chat_model?/1)
              |> Enum.map(&parse_api_model/1)
              |> Enum.sort_by(& &1.id, :desc)

            {:ok, models}

          {:ok, %{status: status, body: body}} ->
            Logger.debug("Failed to fetch OpenAI models: #{status} - #{inspect(body)}")
            ErrorHandler.handle_provider_error(:openai, status, body)

          {:error, reason} ->
            Logger.debug("Failed to fetch OpenAI models: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end
  
  defp is_chat_model?(model) do
    id = model["id"]
    # Include GPT models, O models, and exclude instruction-tuned variants
    (String.contains?(id, "gpt") || String.starts_with?(id, "o")) &&
      not String.contains?(id, "instruct") &&
      not String.contains?(id, "0301") &&  # Exclude old snapshots
      not String.contains?(id, "0314") &&
      not String.contains?(id, "0613")
  end
  
  defp parse_api_model(model) do
    model_id = model["id"]
    
    %Types.Model{
      id: model_id,
      name: format_openai_model_name(model_id),
      description: model["description"],
      context_window: get_context_window(model_id),
      capabilities: infer_model_capabilities(model_id)
    }
  end
  
  defp format_openai_model_name(model_id) do
    # Special cases for OpenAI-specific naming
    case model_id do
      "gpt-4.1" -> "GPT-4.1"
      "gpt-4.1-mini" -> "GPT-4.1 Mini"
      "gpt-4.1-nano" -> "GPT-4.1 Nano"
      "gpt-4o" -> "GPT-4o"
      "gpt-4o-mini" -> "GPT-4o Mini"
      "o3" -> "O3"
      "o3-mini" -> "O3 Mini"
      "o1" -> "O1"
      "o1-mini" -> "O1 Mini"
      _ -> ModelUtils.format_model_name(model_id)
    end
  end
  
  defp infer_model_capabilities(model_id) do
    # Base capabilities for all OpenAI models
    base_features = [:streaming, :function_calling]
    
    # Add vision for multimodal models
    features = 
      if String.contains?(model_id, "4o") || String.contains?(model_id, "4.1") do
        [:vision | base_features]
      else
        base_features
      end
    
    %{
      supports_streaming: true,
      supports_functions: true,
      supports_vision: :vision in features,
      features: features
    }
  end
  
  # Transform config data to OpenAI model format
  defp openai_model_transformer(model_id, config) do
    %Types.Model{
      id: to_string(model_id),
      name: Map.get(config, :name, format_openai_model_name(to_string(model_id))),
      description: Map.get(config, :description),
      context_window: Map.get(config, :context_window, 128_000),
      capabilities: %{
        supports_streaming: :streaming in Map.get(config, :capabilities, []),
        supports_functions: :function_calling in Map.get(config, :capabilities, []),
        supports_vision: :vision in Map.get(config, :capabilities, []),
        features: Map.get(config, :capabilities, [])
      }
    }
  end

  @impl true
  def configured?(options \\ []) do
    config_provider = ConfigHelper.get_config_provider(options)
    config = ConfigHelper.get_config(:openai, config_provider)
    api_key = ConfigHelper.get_api_key(config, "OPENAI_API_KEY")
    !is_nil(api_key) && api_key != ""
  end

  @impl true
  def default_model do
    ConfigHelper.ensure_default_model(:openai)
  end

  # Default model fetching moved to shared ConfigHelper module

  # Streaming behavior callback
  @impl ExLLM.Adapters.Shared.StreamingBehavior
  def parse_stream_chunk(data) do
    case data do
      "[DONE]" -> 
        {:ok, :done}
        
      _ ->
        case Jason.decode(data) do
          {:ok, parsed} ->
            choice = get_in(parsed, ["choices", Access.at(0)]) || %{}
            delta = choice["delta"] || %{}
            
            chunk = StreamingBehavior.create_text_chunk(
              delta["content"] || "",
              finish_reason: choice["finish_reason"]
            )
            
            {:ok, chunk}
            
          {:error, _} ->
            {:error, :invalid_json}
        end
    end
  end

  # Private functions
  
  # API key validation moved to shared Validation module
  
  defp build_request_body(messages, model, config, options) do
    %{
      model: model,
      messages: MessageFormatter.stringify_message_keys(messages),
      max_tokens: Keyword.get(options, :max_tokens, Map.get(config, :max_tokens)),
      temperature: Keyword.get(options, :temperature, Map.get(config, :temperature, @default_temperature))
    }
    |> maybe_add_system_prompt(options)
    |> maybe_add_functions(options)
  end
  
  defp build_headers(api_key, config) do
    headers = [
      {"authorization", "Bearer #{api_key}"}
    ]
    
    if org = Map.get(config, :organization) do
      [{"openai-organization", org} | headers]
    else
      headers
    end
  end
  
  defp maybe_add_system_prompt(body, options) do
    case Keyword.get(options, :system) do
      nil -> body
      system -> Map.update!(body, :messages, &MessageFormatter.add_system_message(&1, system))
    end
  end
  
  defp maybe_add_functions(body, options) do
    case Keyword.get(options, :functions) do
      nil -> body
      functions -> Map.put(body, :functions, functions)
    end
  end

  defp get_base_url(config) do
    # Check config first, then environment variable, then default
    Map.get(config, :base_url) ||
      System.get_env("OPENAI_API_BASE") ||
      @default_base_url
  end




  defp parse_response(response, model) do
    choice = get_in(response, ["choices", Access.at(0)]) || %{}
    message = choice["message"] || %{}
    usage = response["usage"] || %{}

    %Types.LLMResponse{
      content: message["content"] || "",
      function_call: message["function_call"],
      tool_calls: message["tool_calls"],
      usage: %{
        input_tokens: usage["prompt_tokens"] || 0,
        output_tokens: usage["completion_tokens"] || 0,
        total_tokens: usage["total_tokens"] || 0
      },
      model: model,
      finish_reason: choice["finish_reason"],
      cost:
        ExLLM.Cost.calculate("openai", model, %{
          input_tokens: usage["prompt_tokens"] || 0,
          output_tokens: usage["completion_tokens"] || 0
        })
    }
  end




  defp get_context_window(model_id) do
    # Use ModelConfig for context window lookup
    # This will return nil if model not found, which we handle in the caller
    ModelConfig.get_context_window(:openai, model_id)
  end

  @impl true
  def embeddings(inputs, options \\ []) do
    config_provider = ConfigHelper.get_config_provider(options)
    config = ConfigHelper.get_config(:openai, config_provider)
    api_key = ConfigHelper.get_api_key(config, "OPENAI_API_KEY")
    
    with {:ok, _} <- Validation.validate_api_key(api_key),
         {:ok, url} <- build_embeddings_url(config),
         {:ok, req_body} <- build_embeddings_request(inputs, config, options),
         {:ok, response} <- send_embeddings_request(url, req_body, config, api_key) do
      parse_embeddings_response(response, inputs, config, options)
    end
  end

  @impl true
  def list_embedding_models(_options \\ []) do
    models = [
      %Types.EmbeddingModel{
        name: "text-embedding-3-small",
        dimensions: 1536,
        max_inputs: 1,
        provider: :openai,
        description: "Small, efficient embedding model",
        pricing: %{
          # $0.02 per million
          input_cost_per_token: 0.00002 / 1000,
          output_cost_per_token: 0.0,
          currency: "USD"
        }
      },
      %Types.EmbeddingModel{
        name: "text-embedding-3-large",
        dimensions: 3072,
        max_inputs: 1,
        provider: :openai,
        description: "Large, high-quality embedding model",
        pricing: %{
          # $0.13 per million
          input_cost_per_token: 0.00013 / 1000,
          output_cost_per_token: 0.0,
          currency: "USD"
        }
      },
      %Types.EmbeddingModel{
        name: "text-embedding-ada-002",
        dimensions: 1536,
        max_inputs: 1,
        provider: :openai,
        description: "Legacy embedding model",
        pricing: %{
          # $0.10 per million
          input_cost_per_token: 0.0001 / 1000,
          output_cost_per_token: 0.0,
          currency: "USD"
        }
      }
    ]

    {:ok, models}
  end

  # Private embedding functions

  defp build_embeddings_url(config) do
    {:ok, "#{get_base_url(config)}/embeddings"}
  end

  defp build_embeddings_request(inputs, _config, options) do
    model = Keyword.get(options, :model, "text-embedding-3-small")

    # OpenAI supports multiple inputs but we'll send one at a time for consistency
    body = %{
      model: model,
      input: inputs,
      encoding_format: "float"
    }

    # Add optional parameters
    body =
      if dimensions = Keyword.get(options, :dimensions) do
        Map.put(body, :dimensions, dimensions)
      else
        body
      end

    {:ok, body}
  end

  defp send_embeddings_request(url, body, config, api_key) do
    headers = build_headers(api_key, config)

    case HTTPClient.post_json(url, body, headers, timeout: 30_000) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_embeddings_response(response, _inputs, _config, options) do
    case response do
      %{"data" => data, "usage" => usage, "model" => model} ->
        # Extract embeddings
        embeddings =
          Enum.map(data, fn item ->
            item["embedding"]
          end)

        # Build response
        embedding_response = %Types.EmbeddingResponse{
          embeddings: embeddings,
          model: model,
          usage: %{
            input_tokens: usage["prompt_tokens"],
            # Embeddings don't have output tokens
            output_tokens: 0
          }
        }

        # Add cost tracking if enabled
        embedding_response =
          if Keyword.get(options, :track_cost, true) do
            cost = ExLLM.Cost.calculate(:openai, model, embedding_response.usage)
            %{embedding_response | cost: cost}
          else
            embedding_response
          end

        {:ok, embedding_response}

      _ ->
        {:error, Error.json_parse_error("Invalid embeddings response")}
    end
  end
end
