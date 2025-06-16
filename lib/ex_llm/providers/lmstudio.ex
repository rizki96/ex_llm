defmodule ExLLM.Providers.LMStudio do
  @moduledoc """
  LM Studio adapter for local LLM inference.

  This adapter provides integration with LM Studio, a desktop application for running
  local LLMs with an OpenAI-compatible API. LM Studio supports models from Hugging Face
  and provides both GUI and server modes for local inference.

  ## Configuration

  LM Studio runs a local server with OpenAI-compatible endpoints. By default, it listens
  on `http://localhost:1234` with API key `"lm-studio"`.

      # Basic usage
      {:ok, response} = ExLLM.chat(:lmstudio, messages)
      
      # With custom endpoint
      {:ok, response} = ExLLM.chat(:lmstudio, messages, 
        host: "192.168.1.100", 
        port: 8080
      )

  ## Features

  - OpenAI-compatible API (`/v1/chat/completions`, `/v1/models`, `/v1/embeddings`)
  - Native LM Studio REST API (`/api/v0/*`) with enhanced model information
  - Model loading status and quantization details
  - TTL (Time-To-Live) parameter for automatic model unloading
  - Support for both llama.cpp and MLX engines on Apple Silicon
  - Streaming chat completions

  ## Requirements

  1. Install LM Studio from https://lmstudio.ai
  2. Download and load at least one model in LM Studio
  3. Start the local server (usually localhost:1234)
  4. Ensure the server is running when using this adapter

  ## API Endpoints

  This adapter uses both OpenAI-compatible and native LM Studio endpoints:

  - **OpenAI Compatible**: `/v1/chat/completions`, `/v1/models`, `/v1/embeddings`
  - **Native API**: `/api/v0/models`, `/api/v0/chat/completions` (enhanced features)

  The native API provides additional information like model loading status,
  quantization details, architecture information, and performance metrics.
  """

  @behaviour ExLLM.Adapter

  alias ExLLM.Providers.Shared.{MessageFormatter, ResponseBuilder, EnhancedStreamingCoordinator}
  alias ExLLM.Types

  @default_host "localhost"
  @default_port 1234
  @default_api_key "lm-studio"
  @default_model "llama-3.2-3b-instruct"
  @timeout 30_000

  @impl true
  def chat(messages, opts \\ []) do
    with :ok <- validate_messages(messages),
         {:ok, validated_opts} <- validate_options(opts) do
      do_chat(messages, validated_opts)
    end
  end

  @impl true
  def stream_chat(messages, opts \\ []) do
    with :ok <- validate_messages(messages),
         {:ok, validated_opts} <- validate_options(opts) do
      do_stream_chat(messages, validated_opts)
    end
  end

  @impl true
  def configured?(opts \\ []) do
    host = Keyword.get(opts, :host, @default_host)
    port = Keyword.get(opts, :port, @default_port)

    case test_connection(host, port) do
      :ok -> true
      {:error, _} -> false
    end
  end

  @impl true
  def default_model do
    @default_model
  end

  @impl true
  def list_models(opts \\ []) do
    if Keyword.get(opts, :enhanced, false) do
      list_models_enhanced(opts)
    else
      list_models_openai(opts)
    end
  end

  # Private functions

  defp http_client do
    Application.get_env(:ex_llm, :http_client, ExLLM.Providers.Shared.HTTPClient)
  end

  defp do_chat(messages, opts) do
    do_sync_chat(messages, opts)
  end

  defp do_sync_chat(messages, opts) do
    host = Keyword.get(opts, :host, @default_host)
    port = Keyword.get(opts, :port, @default_port)
    api_key = Keyword.get(opts, :api_key, @default_api_key)
    model = Keyword.get(opts, :model, @default_model)
    timeout = Keyword.get(opts, :timeout, @timeout)

    url = build_url(host, port, "/v1/chat/completions")
    headers = build_headers(api_key)
    body = build_chat_request(messages, opts, model)

    case http_client().post_json(url, body, headers, timeout: timeout, provider: :lmstudio) do
      {:ok, response_data} ->
        response = ResponseBuilder.build_chat_response(response_data, model, provider: :lmstudio)
        {:ok, response}

      {:error, {:api_error, %{status: status, body: error_body}}} ->
        handle_error_response(status, error_body)

      {:error, reason} ->
        {:error, "LM Studio not accessible: #{inspect(reason)}"}
    end
  end

  defp do_stream_chat(messages, opts) do
    host = Keyword.get(opts, :host, @default_host)
    port = Keyword.get(opts, :port, @default_port)
    api_key = Keyword.get(opts, :api_key, @default_api_key)
    model = Keyword.get(opts, :model, @default_model)
    _timeout = Keyword.get(opts, :timeout, @timeout)

    url = build_url(host, port, "/v1/chat/completions")
    headers = build_headers(api_key)
    body = build_chat_request(messages, opts, model, stream: true)

    # Create stream with enhanced features
    chunks_ref = make_ref()
    parent = self()

    # Setup callback that sends chunks to parent
    callback = fn chunk ->
      send(parent, {chunks_ref, {:chunk, chunk}})
    end

    # Enhanced streaming options with LMStudio-specific features
    stream_options = [
      parse_chunk_fn: &parse_lmstudio_chunk/1,
      provider: :lmstudio,
      model: model,
      stream_recovery: Keyword.get(opts, :stream_recovery, false),
      track_metrics: Keyword.get(opts, :track_metrics, false),
      on_metrics: Keyword.get(opts, :on_metrics),
      transform_chunk: create_lmstudio_transformer(opts),
      validate_chunk: create_lmstudio_validator(opts),
      buffer_chunks: Keyword.get(opts, :buffer_chunks, 1),
      timeout: Keyword.get(opts, :timeout, 300_000),
      # Enable enhanced features if requested
      enable_flow_control: Keyword.get(opts, :enable_flow_control, false),
      enable_batching: Keyword.get(opts, :enable_batching, false),
      track_detailed_metrics: Keyword.get(opts, :track_detailed_metrics, false)
    ]

    case EnhancedStreamingCoordinator.start_stream(url, body, headers, callback, stream_options) do
      {:ok, stream_id} ->
        # Create Elixir stream that receives chunks
        stream =
          Stream.resource(
            fn -> {chunks_ref, stream_id} end,
            fn {ref, _id} = state ->
              receive do
                {^ref, {:chunk, chunk}} -> {[chunk], state}
              after
                100 -> {[], state}
              end
            end,
            fn _ -> :ok end
          )

        {:ok, stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Parse streaming chunk - LM Studio uses OpenAI-compatible format
  defp parse_stream_chunk(data) do
    case data do
      "[DONE]" ->
        {:ok, :done}

      _ ->
        case Jason.decode(data) do
          {:ok, parsed} ->
            choice = get_in(parsed, ["choices", Access.at(0)]) || %{}
            delta = choice["delta"] || %{}

            # Handle both regular content and reasoning_content
            content = delta["content"] || delta["reasoning_content"] || ""

            chunk = %Types.StreamChunk{
              content: content,
              finish_reason: choice["finish_reason"]
            }

            {:ok, chunk}

          {:error, _} ->
            {:error, :invalid_json}
        end
    end
  end

  # Parse function for StreamingCoordinator (returns Types.StreamChunk directly)
  defp parse_lmstudio_chunk(data) do
    case Jason.decode(data) do
      {:ok, parsed} ->
        choice = get_in(parsed, ["choices", Access.at(0)]) || %{}
        delta = choice["delta"] || %{}

        # Handle both regular content and reasoning_content
        content = delta["content"] || delta["reasoning_content"]
        finish_reason = choice["finish_reason"]

        if content || finish_reason do
          %Types.StreamChunk{
            content: content,
            finish_reason: finish_reason
          }
        else
          nil
        end

      {:error, _} ->
        nil
    end
  end

  # StreamingCoordinator enhancement functions

  defp create_lmstudio_transformer(opts) do
    # Example: Add model performance annotations
    if Keyword.get(opts, :show_performance, false) do
      fn chunk ->
        if chunk.content && String.length(chunk.content) > 50 do
          # Annotate longer responses
          annotated_content = "[LM Studio] #{chunk.content}"
          {:ok, %{chunk | content: annotated_content}}
        else
          {:ok, chunk}
        end
      end
    end
  end

  defp create_lmstudio_validator(opts) do
    # Validate local model responses
    if Keyword.get(opts, :validate_local, false) do
      fn chunk ->
        if chunk.content do
          # Simple validation for local model quality
          if String.length(String.trim(chunk.content)) > 0 do
            :ok
          else
            {:error, "Empty content from local model"}
          end
        else
          :ok
        end
      end
    end
  end

  defp list_models_openai(opts) do
    host = Keyword.get(opts, :host, @default_host)
    port = Keyword.get(opts, :port, @default_port)
    api_key = Keyword.get(opts, :api_key, @default_api_key)
    timeout = Keyword.get(opts, :timeout, @timeout)

    url = build_url(host, port, "/v1/models")
    headers = build_headers(api_key)

    case http_client().post_json(url, %{}, headers,
           method: :get,
           timeout: timeout,
           provider: :lmstudio
         ) do
      {:ok, %{"data" => models}} ->
        formatted_models = Enum.map(models, &format_openai_model/1)
        {:ok, formatted_models}

      {:error, {:api_error, %{status: status, body: error_body}}} ->
        handle_error_response(status, error_body)

      {:error, reason} ->
        {:error, "LM Studio not accessible: #{inspect(reason)}"}
    end
  end

  defp list_models_enhanced(opts) do
    host = Keyword.get(opts, :host, @default_host)
    port = Keyword.get(opts, :port, @default_port)
    timeout = Keyword.get(opts, :timeout, @timeout)
    loaded_only = Keyword.get(opts, :loaded_only, false)

    url = build_url(host, port, "/api/v0/models")
    headers = [{"Content-Type", "application/json"}]

    case http_client().post_json(url, %{}, headers,
           method: :get,
           timeout: timeout,
           provider: :lmstudio
         ) do
      {:ok, %{"data" => models}} when is_list(models) ->
        # Handle newer LM Studio API format with "data" wrapper
        filtered_models =
          if loaded_only do
            Enum.filter(models, fn model -> Map.get(model, "state", "not-loaded") == "loaded" end)
          else
            models
          end

        formatted_models = Enum.map(filtered_models, &format_enhanced_model/1)
        {:ok, formatted_models}

      {:ok, models} when is_list(models) ->
        # Handle older LM Studio API format (direct array)
        filtered_models =
          if loaded_only do
            Enum.filter(models, fn model -> Map.get(model, "loaded", false) end)
          else
            models
          end

        formatted_models = Enum.map(filtered_models, &format_enhanced_model/1)
        {:ok, formatted_models}

      {:error, {:api_error, %{status: status, body: error_body}}} ->
        handle_error_response(status, error_body)

      {:error, reason} ->
        {:error, "LM Studio not accessible: #{inspect(reason)}"}
    end
  end

  defp test_connection(host, port) do
    url = build_url(host, port, "/v1/models")
    headers = build_headers(@default_api_key)

    case http_client().post_json(url, %{}, headers,
           method: :get,
           timeout: 5_000,
           provider: :lmstudio
         ) do
      {:ok, _} ->
        :ok

      {:error, {:api_error, %{status: 401}}} ->
        # Unauthorized is still a valid connection
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_messages(messages) do
    case MessageFormatter.validate_messages(messages) do
      :ok -> :ok
      {:error, {:validation, :messages, reason}} -> {:error, "Messages #{reason}"}
      {:error, {:validation, :message, reason}} -> {:error, "Invalid message format: #{reason}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_options(opts) do
    with :ok <- validate_temperature(Keyword.get(opts, :temperature)),
         :ok <- validate_max_tokens(Keyword.get(opts, :max_tokens)),
         :ok <- validate_host(Keyword.get(opts, :host)),
         :ok <- validate_port(Keyword.get(opts, :port)) do
      {:ok, opts}
    end
  end

  defp validate_temperature(nil), do: :ok
  defp validate_temperature(temp) when is_number(temp) and temp >= 0 and temp <= 2, do: :ok
  defp validate_temperature(_), do: {:error, "Temperature must be between 0 and 2"}

  defp validate_max_tokens(nil), do: :ok
  # LM Studio uses -1 for unlimited tokens
  defp validate_max_tokens(-1), do: :ok
  defp validate_max_tokens(tokens) when is_integer(tokens) and tokens > 0, do: :ok

  defp validate_max_tokens(_),
    do: {:error, "Max tokens must be a positive integer or -1 for unlimited"}

  defp validate_host(nil), do: :ok
  defp validate_host(host) when is_binary(host) and byte_size(host) > 0, do: :ok
  defp validate_host(_), do: {:error, "Host must be a non-empty string"}

  defp validate_port(nil), do: :ok
  defp validate_port(port) when is_integer(port) and port > 0 and port <= 65_535, do: :ok
  defp validate_port(_), do: {:error, "Port must be an integer between 1 and 65_535"}

  defp build_url(host, port, path) do
    "http://#{host}:#{port}#{path}"
  end

  defp build_headers(api_key) do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_key}"}
    ]
  end

  defp build_chat_request(messages, opts, model, extra_opts \\ []) do
    base_request = %{
      "model" => model,
      "messages" => MessageFormatter.stringify_message_keys(messages),
      "stream" => Keyword.get(extra_opts, :stream, false)
    }

    # Add optional parameters
    request =
      base_request
      |> maybe_add_param("temperature", Keyword.get(opts, :temperature))
      # LM Studio default
      |> maybe_add_param("max_tokens", Keyword.get(opts, :max_tokens, -1))
      |> maybe_add_param("top_p", Keyword.get(opts, :top_p))
      |> maybe_add_param("frequency_penalty", Keyword.get(opts, :frequency_penalty))
      |> maybe_add_param("presence_penalty", Keyword.get(opts, :presence_penalty))
      |> maybe_add_param("stop", Keyword.get(opts, :stop))
      |> maybe_add_param("seed", Keyword.get(opts, :seed))
      |> maybe_add_param("ttl", Keyword.get(opts, :ttl))

    request
  end

  defp maybe_add_param(request, _key, nil), do: request
  defp maybe_add_param(request, key, value), do: Map.put(request, key, value)

  defp format_openai_model(model_data) do
    %Types.Model{
      id: model_data["id"],
      name: format_model_name(model_data["id"]),
      description: "LM Studio model - OpenAI compatible endpoint",
      # Default, actual value may vary
      context_window: 4_096,
      max_output_tokens: 4_096,
      # Local models are free
      pricing: %{input: 0.0, output: 0.0},
      capabilities: %{
        features: ["chat", "completions"],
        supports_streaming: true,
        supports_tools: false
      }
    }
  end

  defp format_enhanced_model(model_data) do
    # Handle both old and new LM Studio API formats
    loaded =
      Map.get(model_data, "loaded", false) or
        Map.get(model_data, "state", "not-loaded") == "loaded"

    architecture = Map.get(model_data, "architecture") || Map.get(model_data, "arch", "Unknown")
    quantization = Map.get(model_data, "quantization", "Unknown")

    engine =
      Map.get(model_data, "engine") || Map.get(model_data, "compatibility_type", "llama.cpp")

    context_window =
      Map.get(model_data, "max_context_length") ||
        Map.get(model_data, "loaded_context_length", 4_096)

    status = if loaded, do: "Loaded", else: "Available"

    description = "#{architecture} model - #{quantization} quantization via #{engine} - #{status}"

    %Types.Model{
      id: model_data["id"],
      name: format_model_name(model_data["id"]),
      description: description,
      context_window: context_window,
      max_output_tokens: context_window,
      pricing: %{input: 0.0, output: 0.0},
      capabilities: %{
        features: determine_model_features(model_data),
        architecture: architecture,
        quantization: quantization,
        engine: engine,
        loaded: loaded,
        supports_streaming: true,
        supports_tools: engine in ["llama.cpp", "gguf"]
      }
    }
  end

  defp format_model_name(model_id) do
    model_id
    |> String.split(["/", "-", "_"])
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp determine_model_features(model_data) do
    base_features = ["chat", "completions"]
    architecture = Map.get(model_data, "architecture", "")

    features = base_features

    # Add embedding support for certain architectures
    features =
      if String.contains?(String.downcase(architecture), "bert") do
        ["embeddings" | features]
      else
        features
      end

    # Add vision support for multimodal models
    features =
      if String.contains?(String.downcase(architecture), "vision") or
           String.contains?(String.downcase(architecture), "llava") do
        ["vision" | features]
      else
        features
      end

    features
  end

  defp handle_error_response(status, error_body) do
    case error_body do
      %{"error" => %{"message" => message}} ->
        {:error, message}

      %{"error" => error} when is_binary(error) ->
        {:error, error}

      _ ->
        {:error, "LM Studio request failed with status #{status}"}
    end
  end
end
