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

  ## Streaming Support

  LM Studio supports streaming responses. Due to how LM Studio returns streaming data,
  the high-level `ExLLM.stream/4` API may not work as expected. Instead, use the
  provider's direct streaming method:

      # Recommended approach for streaming with LM Studio
      {:ok, stream} = ExLLM.Providers.LMStudio.stream_chat(messages, model: "gpt-4")
      
      stream
      |> Enum.each(fn chunk ->
        IO.write(chunk.content || "")
      end)

  Regular non-streaming chat works perfectly with both the high-level and low-level APIs.
  """

  alias ExLLM.Providers.Shared.ModelUtils
  import ModelUtils, only: [format_model_name: 1]

  use ExLLM.Providers.OpenAICompatible,
    provider: :lmstudio,
    base_url: "http://localhost:1234"

  alias ExLLM.Providers.Shared.EnhancedStreamingCoordinator
  alias ExLLM.Providers.Shared.HTTP.Core
  alias ExLLM.Providers.Shared.{MessageFormatter, Validation}
  alias ExLLM.Types

  import ExLLM.Providers.OpenAICompatible, only: [default_model_transformer: 2]

  @timeout 30_000

  @default_host "localhost"
  @default_port 1234

  # Override chat to inject dynamic options into config
  @impl ExLLM.Provider
  def chat(messages, options) do
    with :ok <- MessageFormatter.validate_messages(messages) do
      config = prepare_config(options)
      api_key = get_api_key(config)

      with {:ok, _} <- Validation.validate_api_key(api_key) do
        # do_chat is private in the context of this module, so it can be called.
        do_chat(messages, options, config, api_key)
      end
    end
  end

  @impl ExLLM.Provider
  def stream_chat(messages, opts) do
    config = prepare_config(opts)
    api_key = get_api_key(config)
    model = Keyword.get(opts, :model) || get_default_model(config)

    url = "#{get_base_url(config)}/v1/chat/completions"
    headers = get_headers(api_key, opts)
    body = build_chat_request(messages, model, opts) |> Map.put("stream", true)

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

    {:ok, stream_id} =
      EnhancedStreamingCoordinator.start_stream(url, body, headers, callback, stream_options)

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
  end

  @impl ExLLM.Providers.OpenAICompatible
  def get_base_url(config) do
    case Map.get(config, :base_url) do
      nil ->
        host = Map.get(config, :host, @default_host)
        port = Map.get(config, :port, @default_port)
        "http://#{host}:#{port}"

      base_url ->
        base_url
    end
  end

  @impl ExLLM.Providers.OpenAICompatible
  def get_api_key(config) do
    Map.get(config, :api_key, "lm-studio")
  end

  @impl ExLLM.Provider
  def default_model, do: "local-model"

  @impl true
  def configured?(opts) do
    config = prepare_config(opts)
    host = Map.get(config, :host, @default_host)
    port = Map.get(config, :port, @default_port)

    with :ok <- validate_host(host),
         :ok <- validate_port(port),
         :ok <- test_connection(config) do
      true
    else
      {:error, _} -> false
    end
  end

  @impl true
  def list_models(opts) do
    if Keyword.get(opts, :enhanced, false) do
      list_models_enhanced(opts)
    else
      config = prepare_config(opts)

      # Replicates logic from OpenAICompatible.list_models to pass a custom config
      ExLLM.Infrastructure.Config.ModelLoader.load_models(
        provider_atom(),
        Keyword.merge(opts,
          api_fetcher: fn _opts -> fetch_models_from_api(config) end,
          config_transformer: &default_model_transformer/2
        )
      )
    end
  end

  @impl ExLLM.Providers.OpenAICompatible
  def transform_request(request, opts) do
    # Add LMStudio specific parameters
    request
    |> maybe_add_param("ttl", Keyword.get(opts, :ttl))
  end

  defp prepare_config(options) do
    config_provider = get_config_provider(options)
    base_config = get_config(config_provider)

    runtime_config =
      %{
        host: Keyword.get(options, :host),
        port: Keyword.get(options, :port),
        api_key: Keyword.get(options, :api_key)
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    Map.merge(base_config, runtime_config)
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
    if Keyword.get(opts, :validate_local, false) do
      &validate_lmstudio_chunk/1
    end
  end

  defp validate_lmstudio_chunk(chunk) do
    if chunk.content do
      validate_chunk_content(chunk.content)
    else
      :ok
    end
  end

  defp validate_chunk_content(content) do
    if String.length(String.trim(content)) > 0 do
      :ok
    else
      {:error, "Empty content from local model"}
    end
  end

  defp list_models_enhanced(opts) do
    config = prepare_config(opts)
    timeout = Keyword.get(opts, :timeout, @timeout)
    loaded_only = Keyword.get(opts, :loaded_only, false)
    api_key = get_api_key(config)

    client = Core.client(provider: :lmstudio, api_key: api_key, base_url: get_base_url(config))

    case Tesla.get(client, "/api/v0/models", opts: [timeout: timeout]) do
      {:ok, %Tesla.Env{status: 200, body: %{"data" => models}}} when is_list(models) ->
        # Handle newer LM Studio API format with "data" wrapper
        filtered_models =
          if loaded_only do
            Enum.filter(models, fn model -> Map.get(model, "state", "not-loaded") == "loaded" end)
          else
            models
          end

        formatted_models = Enum.map(filtered_models, &format_enhanced_model/1)
        {:ok, formatted_models}

      {:ok, %Tesla.Env{status: 200, body: response}} when is_list(response) ->
        # Handle older LM Studio API format (direct array)
        models = response

        filtered_models =
          if loaded_only do
            Enum.filter(models, fn model -> Map.get(model, "loaded", false) end)
          else
            models
          end

        formatted_models = Enum.map(filtered_models, &format_enhanced_model/1)
        {:ok, formatted_models}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        handle_error_response(status, error_body)

      {:error, reason} ->
        {:error, "LM Studio not accessible: #{inspect(reason)}"}
    end
  end

  defp test_connection(config) do
    api_key = get_api_key(config)
    client = Core.client(provider: :lmstudio, api_key: api_key, base_url: get_base_url(config))

    case Tesla.get(client, "/v1/models", opts: [timeout: 5_000]) do
      {:ok, %Tesla.Env{}} ->
        :ok

      {:error, {:api_error, %{status: 401}}} ->
        # Unauthorized is still a valid connection
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_host(nil), do: :ok
  defp validate_host(host) when is_binary(host) and byte_size(host) > 0, do: :ok
  defp validate_host(_), do: {:error, "Host must be a non-empty string"}

  defp validate_port(nil), do: :ok
  defp validate_port(port) when is_integer(port) and port > 0 and port <= 65_535, do: :ok
  defp validate_port(_), do: {:error, "Port must be an integer between 1 and 65_535"}

  defp maybe_add_param(request, _key, nil), do: request
  defp maybe_add_param(request, key, value), do: Map.put(request, key, value)

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
