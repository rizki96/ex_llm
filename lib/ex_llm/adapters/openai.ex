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

  alias ExLLM.{Error, Types, ModelConfig}
  require Logger

  @default_base_url "https://api.openai.com/v1"
  @default_temperature 0.7

  @impl true
  def chat(messages, options \\ []) do
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
      )

    config = get_config(config_provider)

    api_key = get_api_key(config)

    if !api_key || api_key == "" do
      {:error, "OpenAI API key not configured"}
    else
      model = Keyword.get(options, :model, Map.get(config, :model, get_default_model()))

      max_tokens = Keyword.get(options, :max_tokens, Map.get(config, :max_tokens))

      temperature =
        Keyword.get(options, :temperature, Map.get(config, :temperature, @default_temperature))

      body = %{
        model: model,
        messages: format_messages(messages),
        max_tokens: max_tokens,
        temperature: temperature
      }

      headers = [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]

      url = "#{get_base_url(config)}/chat/completions"

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, parse_response(response, model)}

        {:ok, %{status: status, body: body}} ->
          Error.api_error(status, body)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
      )

    config = get_config(config_provider)

    api_key = get_api_key(config)

    if !api_key || api_key == "" do
      {:error, "OpenAI API key not configured"}
    else
      model = Keyword.get(options, :model, Map.get(config, :model, get_default_model()))

      max_tokens = Keyword.get(options, :max_tokens, Map.get(config, :max_tokens))

      temperature =
        Keyword.get(options, :temperature, Map.get(config, :temperature, @default_temperature))

      body = %{
        model: model,
        messages: format_messages(messages),
        max_tokens: max_tokens,
        temperature: temperature,
        stream: true
      }

      headers = [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]

      url = "#{get_base_url(config)}/chat/completions"
      parent = self()

      # Start async request task
      Task.start(fn ->
        case Req.post(url, json: body, headers: headers, receive_timeout: 60_000, into: :self) do
          {:ok, response} ->
            if response.status == 200 do
              handle_stream_response(response, parent, model, "")
            else
              send(parent, {:stream_error, Error.api_error(response.status, response.body)})
            end

          {:error, reason} ->
            send(parent, {:stream_error, {:error, reason}})
        end
      end)

      # Create stream that receives messages
      stream =
        Stream.resource(
          fn -> :ok end,
          fn state ->
            receive do
              {:chunk, chunk} -> {[chunk], state}
              :stream_done -> {:halt, state}
              {:stream_error, error} -> throw(error)
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
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
      )

    config = get_config(config_provider)
    
    # Use ModelLoader with API fetching
    ExLLM.ModelLoader.load_models(:openai,
      Keyword.merge(options, [
        api_fetcher: fn(_opts) -> fetch_openai_models(config) end,
        config_transformer: &openai_model_transformer/2
      ])
    )
  end
  
  defp fetch_openai_models(config) do
    api_key = get_api_key(config)

    if !api_key || api_key == "" do
      {:error, "OpenAI API key not configured"}
    else
      headers = [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]

      url = "#{get_base_url(config)}/models"

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          models =
            body["data"]
            |> Enum.filter(&is_chat_model?/1)
            |> Enum.map(&parse_api_model/1)
            |> Enum.sort_by(& &1.id, :desc)

          {:ok, models}

        {:ok, %{status: status, body: body}} ->
          Logger.debug("OpenAI API returned status #{status}: #{inspect(body)}")
          {:error, "API returned status #{status}"}

        {:error, reason} ->
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
      _ -> model_id
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
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
      )

    config = get_config(config_provider)
    api_key = get_api_key(config)
    !is_nil(api_key) && api_key != ""
  end

  @impl true
  def default_model do
    get_default_model()
  end

  # Private helper to get default model from config
  defp get_default_model do
    case ModelConfig.get_default_model(:openai) do
      nil ->
        raise "Missing configuration: No default model found for OpenAI. " <>
              "Please ensure config/models/openai.yml exists and contains a 'default_model' field."
      model ->
        model
    end
  end

  # Private functions

  defp get_config(config_provider) do
    config_provider.get_all(:openai)
  end

  defp get_api_key(config) do
    # First try config, then environment variable
    Map.get(config, :api_key) || System.get_env("OPENAI_API_KEY")
  end

  defp get_base_url(config) do
    # Check config first, then environment variable, then default
    Map.get(config, :base_url) ||
      System.get_env("OPENAI_API_BASE") ||
      @default_base_url
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      role = to_string(msg.role || msg["role"])
      content = format_content_for_openai(msg.content || msg["content"])

      %{
        "role" => role,
        "content" => content
      }
    end)
  end

  defp format_content_for_openai(content) when is_binary(content) do
    # Simple text content
    content
  end

  defp format_content_for_openai(content) when is_list(content) do
    # Multimodal content - OpenAI expects array format
    Enum.map(content, fn part ->
      case part do
        %{"type" => "text", "text" => text} ->
          %{"type" => "text", "text" => text}

        %{type: "text", text: text} ->
          %{"type" => "text", "text" => text}

        %{"type" => "image_url", "image_url" => image_url} ->
          %{"type" => "image_url", "image_url" => image_url}

        %{type: "image_url", image_url: image_url} ->
          %{"type" => "image_url", "image_url" => format_image_url(image_url)}

        %{"type" => "image", "image" => %{"data" => data, "media_type" => media_type}} ->
          # Convert base64 to data URL for OpenAI
          %{
            "type" => "image_url",
            "image_url" => %{
              "url" => "data:#{media_type};base64,#{data}"
            }
          }

        %{type: "image", image: %{data: data, media_type: media_type}} ->
          # Convert base64 to data URL for OpenAI
          %{
            "type" => "image_url",
            "image_url" => %{
              "url" => "data:#{media_type};base64,#{data}"
            }
          }

        _ ->
          part
      end
    end)
  end

  defp format_content_for_openai(content) do
    # Fallback - convert to string
    to_string(content)
  end

  defp format_image_url(%{url: url} = image_url) do
    detail = Map.get(image_url, :detail, "auto")
    %{"url" => url, "detail" => to_string(detail)}
  end

  defp format_image_url(%{"url" => _} = image_url) do
    # Already in correct format
    image_url
  end

  defp parse_response(response, model) do
    choice = get_in(response, ["choices", Access.at(0)]) || %{}
    usage = response["usage"] || %{}

    %Types.LLMResponse{
      content: get_in(choice, ["message", "content"]) || "",
      usage: %{
        prompt_tokens: usage["prompt_tokens"] || 0,
        completion_tokens: usage["completion_tokens"] || 0,
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

  defp parse_sse_event("data: [DONE]"), do: %Types.StreamChunk{content: "", finish_reason: "stop"}

  defp parse_sse_event("data: " <> json) do
    case Jason.decode(json) do
      {:ok, data} ->
        choice = get_in(data, ["choices", Access.at(0)]) || %{}
        delta = choice["delta"] || %{}

        %Types.StreamChunk{
          content: delta["content"] || "",
          finish_reason: choice["finish_reason"]
        }

      _ ->
        nil
    end
  end

  defp parse_sse_event(_), do: nil

  defp process_sse_chunks(data) do
    lines = String.split(data, "\n")

    {complete_lines, rest} =
      case List.last(lines) do
        "" -> {lines, ""}
        last_line -> {Enum.drop(lines, -1), last_line}
      end

    chunks =
      complete_lines
      |> Enum.map(&parse_sse_event/1)
      |> Enum.reject(&is_nil/1)

    {rest, chunks}
  end

  defp handle_stream_response(response, parent, model, buffer) do
    %Req.Response.Async{ref: ref} = response.body

    receive do
      {^ref, {:data, data}} ->
        {new_buffer, chunks} = process_sse_chunks(buffer <> data)
        Enum.each(chunks, &send(parent, {:chunk, &1}))
        handle_stream_response(response, parent, model, new_buffer)

      {^ref, :done} ->
        send(parent, :stream_done)

      {^ref, {:error, reason}} ->
        send(parent, {:stream_error, {:error, reason}})
    after
      30_000 ->
        send(parent, {:stream_error, {:error, :timeout}})
    end
  end

  defp get_context_window(model_id) do
    # Use ModelConfig for context window lookup
    # This will return nil if model not found, which we handle in the caller
    ModelConfig.get_context_window(:openai, model_id)
  end

  @impl true
  def embeddings(inputs, options \\ []) do
    with {:ok, config} <- get_config(options),
         {:ok, url} <- build_embeddings_url(config),
         {:ok, req_body} <- build_embeddings_request(inputs, config, options),
         {:ok, response} <- send_embeddings_request(url, req_body, config) do
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
    base_url = Map.get(config, "base_url", "https://api.openai.com/v1")
    {:ok, "#{base_url}/embeddings"}
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

  defp send_embeddings_request(url, body, config) do
    headers = [
      {"authorization", "Bearer #{config["api_key"]}"},
      {"content-type", "application/json"}
    ]

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.api_error(status, body)}

      {:error, reason} ->
        {:error, Error.connection_error(reason)}
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
