defmodule ExLLM.Providers.OpenRouter do
  @moduledoc """
  OpenRouter API adapter for ExLLM.

  OpenRouter provides access to 300+ AI models through a unified API that's compatible
  with the OpenAI format. It offers intelligent routing, automatic fallbacks, and
  normalized responses across different AI providers.

  ## Configuration

  This adapter requires an OpenRouter API key and optionally app identification headers.

  ### Using Environment Variables

      # Set environment variables
      export OPENROUTER_API_KEY="your-api-key"
      export OPENROUTER_MODEL="openai/gpt-4o"  # optional
      export OPENROUTER_APP_NAME="MyApp"       # optional
      export OPENROUTER_APP_URL="https://myapp.com"  # optional

      # Use with default environment provider
      ExLLM.Providers.OpenRouter.chat(messages, config_provider: ExLLM.Infrastructure.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        openrouter: %{
          api_key: "your-api-key",
          model: "openai/gpt-4o",
          app_name: "MyApp",
          app_url: "https://myapp.com",
          base_url: "https://openrouter.ai/api/v1"  # optional
        }
      }
      {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)
      ExLLM.Providers.OpenRouter.chat(messages, config_provider: provider)

  ## Example Usage

      messages = [
        %{role: "user", content: "Hello, how are you?"}
      ]

      # Simple chat
      {:ok, response} = ExLLM.Providers.OpenRouter.chat(messages)
      IO.puts(response.content)

      # With specific model
      {:ok, response} = ExLLM.Providers.OpenRouter.chat(messages, model: "anthropic/claude-3-5-sonnet")

      # Streaming chat
      {:ok, stream} = ExLLM.Providers.OpenRouter.stream_chat(messages)
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end

  ## OpenRouter Features

  - **Model Routing**: Access 300+ models from providers like OpenAI, Anthropic, Google, Meta, etc.
  - **Automatic Fallbacks**: Intelligent routing if primary model is unavailable
  - **Unified API**: OpenAI-compatible format for all models
  - **Streaming**: Real-time responses for all supported models
  - **Function Calling**: Tool/function calling support where available
  - **Multimodal**: Image and PDF input support for compatible models
  """

  @behaviour ExLLM.Provider

  alias ExLLM.Providers.Shared.{
    ConfigHelper,
    EnhancedStreamingCoordinator,
    HTTPClient
  }

  alias ExLLM.{Infrastructure.Logger, Types}

  @default_base_url "https://openrouter.ai/api/v1"

  @impl true
  def chat(messages, options \\ []) do
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(
          :ex_llm,
          :config_provider,
          ExLLM.Infrastructure.ConfigProvider.Default
        )
      )

    config = get_config(config_provider)
    api_key = get_api_key(config)

    if !api_key || api_key == "" do
      {:error, "OpenRouter API key not configured"}
    else
      model = Keyword.get(options, :model, get_model(config))

      request_body = build_request_body(messages, model, options)
      headers = build_headers(api_key, config)

      url = "#{get_base_url(config)}/chat/completions"

      case HTTPClient.post_json(url, request_body, headers, provider: :openrouter) do
        {:ok, %{status: 200, body: body}} ->
          parse_response(body, model)

        {:ok, %{status: status, body: body}} ->
          {:error, ExLLM.Infrastructure.Error.api_error(status, body)}

        {:error, reason} ->
          {:error, ExLLM.Infrastructure.Error.connection_error(reason)}
      end
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(
          :ex_llm,
          :config_provider,
          ExLLM.Infrastructure.ConfigProvider.Default
        )
      )

    config = get_config(config_provider)
    api_key = get_api_key(config)

    if !api_key || api_key == "" do
      {:error, "OpenRouter API key not configured"}
    else
      model = Keyword.get(options, :model, get_model(config))

      request_body =
        messages
        |> build_request_body(model, options)
        |> Map.put("stream", true)

      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/chat/completions"

      # Create stream with enhanced coordinator
      chunks_ref = make_ref()
      parent = self()

      # Setup callback that sends chunks to parent
      callback = fn chunk ->
        send(parent, {chunks_ref, {:chunk, chunk}})
      end

      # Enhanced streaming options with OpenRouter-specific features
      stream_options = [
        parse_chunk_fn: &parse_openrouter_chunk/1,
        provider: :openrouter,
        model: model,
        stream_recovery: Keyword.get(options, :stream_recovery, false),
        track_metrics: Keyword.get(options, :track_metrics, false),
        on_metrics: Keyword.get(options, :on_metrics),
        buffer_chunks: Keyword.get(options, :buffer_chunks, 1),
        timeout: Keyword.get(options, :timeout, 300_000),
        # Enable enhanced features if requested
        enable_flow_control: Keyword.get(options, :enable_flow_control, false),
        enable_batching: Keyword.get(options, :enable_batching, false),
        track_detailed_metrics: Keyword.get(options, :track_detailed_metrics, false)
      ]

      Logger.with_context([provider: :openrouter, model: model], fn ->
        case EnhancedStreamingCoordinator.start_stream(
               url,
               request_body,
               headers,
               callback,
               stream_options
             ) do
          {:ok, stream_id} ->
            # Create Elixir stream that receives chunks
            stream = create_chunk_stream(chunks_ref, stream_id)

            {:ok, stream}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end
  end

  @impl true
  def configured?(options \\ []) do
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(
          :ex_llm,
          :config_provider,
          ExLLM.Infrastructure.ConfigProvider.Default
        )
      )

    config = get_config(config_provider)
    api_key = get_api_key(config)

    !is_nil(api_key) && api_key != ""
  end

  @impl true
  def default_model do
    ConfigHelper.ensure_default_model(:openrouter)
  end

  # Default model fetching moved to shared ConfigHelper module

  @impl true
  def list_models(options \\ []) do
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(
          :ex_llm,
          :config_provider,
          ExLLM.Infrastructure.ConfigProvider.Default
        )
      )

    config = get_config(config_provider)

    # Use ModelLoader with API fetching
    ExLLM.Infrastructure.Config.ModelLoader.load_models(
      :openrouter,
      Keyword.merge(options,
        api_fetcher: fn _opts -> fetch_openrouter_models(config) end,
        config_transformer: &openrouter_model_transformer/2
      )
    )
  end

  defp fetch_openrouter_models(config) do
    api_key = get_api_key(config)

    if !api_key || api_key == "" do
      {:error, "OpenRouter API key not configured"}
    else
      headers = build_headers(api_key, config)
      url = "#{get_base_url(config)}/models"

      case HTTPClient.get_json(url, headers, provider: :openrouter) do
        {:ok, %{status: 200, body: body}} ->
          models =
            body["data"]
            |> Enum.map(&parse_openrouter_api_model/1)
            |> Enum.sort_by(& &1.id)

          {:ok, models}

        {:ok, %{status: status, body: body}} ->
          Logger.debug("OpenRouter API returned status #{status}: #{inspect(body)}")
          {:error, "API returned status #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp parse_openrouter_api_model(model) do
    %Types.Model{
      id: model["id"],
      name: model["name"] || model["id"],
      description: model["description"],
      context_window: model["context_length"] || 4096,
      pricing: parse_pricing(model["pricing"]),
      capabilities: parse_capabilities(model)
    }
  end

  # Transform config data to OpenRouter model format
  defp openrouter_model_transformer(model_id, config) do
    %Types.Model{
      id: to_string(model_id),
      name: Map.get(config, :name, to_string(model_id)),
      description: Map.get(config, :description),
      context_window: Map.get(config, :context_window, 4096),
      capabilities: %{
        supports_streaming: :streaming in Map.get(config, :capabilities, []),
        supports_functions: :function_calling in Map.get(config, :capabilities, []),
        supports_vision: :vision in Map.get(config, :capabilities, []),
        features: Map.get(config, :capabilities, [])
      }
    }
  end

  # Private functions

  defp get_config(config_provider) do
    case config_provider do
      provider when is_pid(provider) ->
        # Static provider - get the full config and extract openrouter section
        full_config = ExLLM.Infrastructure.ConfigProvider.Static.get_all(provider)
        Map.get(full_config, :openrouter, %{})

      provider when is_atom(provider) ->
        # Module-based provider (Env, Default)
        provider.get_all(:openrouter)
    end
  end

  defp get_api_key(config) do
    # First try config, then environment variable
    Map.get(config, :api_key) || System.get_env("OPENROUTER_API_KEY")
  end

  defp get_model(config) do
    Map.get(config, :model) || System.get_env("OPENROUTER_MODEL") ||
      ConfigHelper.ensure_default_model(:openrouter)
  end

  defp get_base_url(config) do
    Map.get(config, :base_url) || System.get_env("OPENROUTER_BASE_URL") || @default_base_url
  end

  defp get_app_name(config) do
    Map.get(config, :app_name) || System.get_env("OPENROUTER_APP_NAME") || "ExLLM"
  end

  defp get_app_url(config) do
    Map.get(config, :app_url) || System.get_env("OPENROUTER_APP_URL") ||
      "https://github.com/3rdparty-integrations/ex_llm"
  end

  defp build_headers(api_key, config) do
    base_headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"},
      {"x-title", get_app_name(config)}
    ]

    app_url = get_app_url(config)

    if app_url do
      [{"http-referer", app_url} | base_headers]
    else
      base_headers
    end
  end

  defp build_request_body(messages, model, options) do
    base_body = %{
      "model" => model,
      "messages" => format_messages(messages)
    }

    # Add optional parameters
    base_body
    |> maybe_add_temperature(options)
    |> maybe_add_max_tokens(options)
    |> maybe_add_functions(options)
    |> maybe_add_tools(options)
    |> maybe_add_stream_options(options)
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      case msg do
        %{role: role, content: content} ->
          %{"role" => to_string(role), "content" => content}

        %{"role" => role, "content" => content} ->
          %{"role" => to_string(role), "content" => content}

        msg when is_map(msg) ->
          # Handle other message formats
          msg
          |> Enum.into(%{})
          |> Map.update("role", "user", &to_string/1)
      end
    end)
  end

  defp maybe_add_temperature(body, options) do
    case Keyword.get(options, :temperature) do
      nil -> body
      temp -> Map.put(body, "temperature", temp)
    end
  end

  defp maybe_add_max_tokens(body, options) do
    case Keyword.get(options, :max_tokens) do
      nil -> body
      tokens -> Map.put(body, "max_tokens", tokens)
    end
  end

  defp maybe_add_functions(body, options) do
    case Keyword.get(options, :functions) do
      nil -> body
      functions -> Map.put(body, "functions", functions)
    end
  end

  defp maybe_add_tools(body, options) do
    case Keyword.get(options, :tools) do
      nil -> body
      tools -> Map.put(body, "tools", tools)
    end
  end

  defp maybe_add_stream_options(body, options) do
    case Keyword.get(options, :stream_options) do
      nil -> body
      stream_opts -> Map.put(body, "stream_options", stream_opts)
    end
  end

  defp parse_response(body, model) do
    choice = List.first(body["choices"])
    message = choice["message"]

    content = message["content"] || ""
    finish_reason = choice["finish_reason"]

    usage = body["usage"] || %{}

    {:ok,
     %Types.LLMResponse{
       content: content,
       model: model,
       usage: %{
         input_tokens: usage["prompt_tokens"] || 0,
         output_tokens: usage["completion_tokens"] || 0,
         total_tokens: usage["total_tokens"] || 0
       },
       finish_reason: finish_reason,
       id: body["id"],
       tool_calls: parse_function_calls(message)
     }}
  end

  defp parse_function_calls(message) do
    cond do
      # OpenAI-style function call
      message["function_call"] ->
        [
          %{
            id: "generated_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
            name: message["function_call"]["name"],
            arguments: message["function_call"]["arguments"] |> Jason.decode!()
          }
        ]

      # OpenAI-style tool calls
      message["tool_calls"] ->
        Enum.map(message["tool_calls"], fn tool_call ->
          %{
            id: tool_call["id"],
            name: tool_call["function"]["name"],
            arguments: tool_call["function"]["arguments"] |> Jason.decode!()
          }
        end)

      true ->
        []
    end
  end

  defp parse_pricing(nil), do: nil

  defp parse_pricing(pricing) do
    %{
      currency: "USD",
      input_cost_per_token: parse_price_value(pricing["prompt"]) / 1_000_000,
      output_cost_per_token: parse_price_value(pricing["completion"]) / 1_000_000
    }
  end

  defp parse_price_value(nil), do: 0
  defp parse_price_value(value) when is_number(value), do: value

  defp parse_price_value(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> parsed
      :error -> 0
    end
  end

  defp parse_capabilities(model) do
    features = []

    features = if model["supports_streaming"], do: [:streaming | features], else: features
    features = if model["supports_functions"], do: [:function_calling | features], else: features
    features = if model["supports_vision"], do: [:vision | features], else: features

    %{
      supports_streaming: model["supports_streaming"] || false,
      supports_functions: model["supports_functions"] || false,
      supports_vision: model["supports_vision"] || false,
      features: features
    }
  end

  defp create_chunk_stream(chunks_ref, stream_id) do
    Stream.resource(
      fn -> {chunks_ref, stream_id} end,
      &process_stream_chunks/1,
      fn _ -> :ok end
    )
  end

  defp process_stream_chunks({ref, _id} = state) do
    receive do
      {^ref, {:chunk, chunk}} -> {[chunk], state}
    after
      100 -> {[], state}
    end
  end

  # Parse streaming chunk from OpenRouter.
  # OpenRouter uses OpenAI-compatible streaming format.
  defp parse_openrouter_chunk(data) do
    case Jason.decode(data) do
      {:ok, %{"choices" => choices} = chunk} ->
        choice = List.first(choices)

        if choice do
          content = get_in(choice, ["delta", "content"])
          finish_reason = choice["finish_reason"]

          %Types.StreamChunk{
            content: content,
            finish_reason: finish_reason,
            model: chunk["model"]
          }
        else
          nil
        end

      {:ok, _other} ->
        # Handle other chunk types like usage information
        nil

      {:error, _} ->
        # Skip invalid JSON chunks
        nil
    end
  end

  @doc """
  Generate embeddings for text through OpenRouter.

  This function is a placeholder. While OpenRouter provides access to
  models with embedding capabilities, embeddings API is not yet implemented.
  """
  @impl ExLLM.Provider
  @spec embeddings(list(String.t()), keyword()) :: {:error, term()}
  def embeddings(_inputs, _options \\ []) do
    {:error, {:not_implemented, :openrouter_embeddings}}
  end
end
