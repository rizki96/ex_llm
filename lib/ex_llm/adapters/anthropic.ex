defmodule ExLLM.Adapters.Anthropic do
  @moduledoc """
  Anthropic Claude API adapter for ExLLM.

  ## Configuration

  This adapter requires an Anthropic API key and optionally a base URL.

  ### Using Environment Variables

      # Set environment variables
      export ANTHROPIC_API_KEY="your-api-key"
      export ANTHROPIC_MODEL="claude-3-5-sonnet-20241022"  # optional

      # Use with default environment provider
      ExLLM.Adapters.Anthropic.chat(messages, config_provider: ExLLM.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        anthropic: %{
          api_key: "your-api-key",
          model: "claude-3-5-sonnet-20241022",
          base_url: "https://api.anthropic.com/v1"  # optional
        }
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      ExLLM.Adapters.Anthropic.chat(messages, config_provider: provider)

  ## Example Usage

      messages = [
        %{role: "user", content: "Hello, how are you?"}
      ]

      # Simple chat
      {:ok, response} = ExLLM.Adapters.Anthropic.chat(messages)
      IO.puts(response.content)

      # Streaming chat
      {:ok, stream} = ExLLM.Adapters.Anthropic.stream_chat(messages)
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end
  """

  @behaviour ExLLM.Adapter

  alias ExLLM.{ConfigProvider, Error, Types, ModelConfig}
  import ExLLM.Adapters.OpenAICompatible, only: [format_model_name: 1, default_model_transformer: 2]

  @default_base_url "https://api.anthropic.com/v1"

  @impl true
  def chat(messages, options \\ []) do
    config_provider = Keyword.get(options, :config_provider, ConfigProvider.Env)
    config = get_config(config_provider)
    model = Keyword.get(options, :model, config.model || get_default_model())
    max_tokens = Keyword.get(options, :max_tokens, config.max_tokens || 4_096)

    # Convert messages to Anthropic format
    formatted_messages = format_messages_for_anthropic(messages)

    body =
      %{
        model: model,
        messages: formatted_messages,
        max_tokens: max_tokens
      }
      |> maybe_add_system(options)
      |> maybe_add_temperature(options)

    headers = [
      {"x-api-key", get_api_key(config_provider)},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    case Req.post("#{get_base_url(config_provider)}/messages", json: body, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, parse_response(response)}

      {:ok, %{status: status, body: body}} ->
        Error.api_error(status, body)

      {:error, reason} ->
        Error.connection_error(reason)
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    config_provider = Keyword.get(options, :config_provider, ConfigProvider.Env)
    config = get_config(config_provider)
    model = Keyword.get(options, :model, config.model || get_default_model())
    max_tokens = Keyword.get(options, :max_tokens, config.max_tokens || 4_096)

    # Convert messages to Anthropic format
    formatted_messages = format_messages_for_anthropic(messages)

    body =
      %{
        model: model,
        messages: formatted_messages,
        max_tokens: max_tokens,
        stream: true
      }
      |> maybe_add_system(options)
      |> maybe_add_temperature(options)

    headers = [
      {"x-api-key", get_api_key(config_provider)},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    # Create a simple streaming implementation
    parent = self()
    base_url = get_base_url(config_provider)

    Task.start(fn ->
      case Req.post("#{base_url}/messages",
             json: body,
             headers: headers,
             receive_timeout: 60_000,
             into: :self
           ) do
        {:ok, response} ->
          handle_response_status(response, parent)

        {:error, reason} ->
          send(parent, {:stream_error, inspect(reason)})
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
            {:stream_error, error} -> throw({:error, error})
          after
            30_000 -> {[], state}
          end
        end,
        fn _ -> :ok end
      )

    {:ok, stream}
  catch
    {:error, error} -> {:error, error}
  end

  @impl true
  def configured?(options \\ []) do
    config_provider = Keyword.get(options, :config_provider, ConfigProvider.Env)
    api_key = get_api_key(config_provider)
    api_key != nil and String.length(api_key) > 0
  end

  @impl true
  def default_model, do: get_default_model()

  # Private helper to get default model from config
  defp get_default_model do
    case ModelConfig.get_default_model(:anthropic) do
      nil ->
        raise "Missing configuration: No default model found for Anthropic. " <>
              "Please ensure config/models/anthropic.yml exists and contains a 'default_model' field."
      model ->
        model
    end
  end

  @impl true
  def list_models(options \\ []) do
    config_provider = Keyword.get(
      options,
      :config_provider,
      Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
    )
    
    config = get_config(config_provider)
    
    # Use ModelLoader with API fetching
    ExLLM.ModelLoader.load_models(:anthropic,
      Keyword.merge(options, [
        api_fetcher: fn(_opts) -> fetch_anthropic_models(config) end,
        config_transformer: &anthropic_model_transformer/2
      ])
    )
  end
  
  defp fetch_anthropic_models(config) do
    api_key = config.api_key
    
    if !api_key || api_key == "" do
      {:error, "No API key available"}
    else
      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ]
      
      case Req.get("https://api.anthropic.com/v1/models", headers: headers) do
        {:ok, %{status: 200, body: %{"data" => models}}} ->
          # Transform models using the shared parse_api_model function
          parsed_models = models
          |> Enum.map(&parse_anthropic_model/1)
          |> Enum.sort_by(& &1.id)
          
          {:ok, parsed_models}
          
        {:ok, %{status: status}} ->
          {:error, "API returned status #{status}"}
          
        {:error, reason} ->
          {:error, "Network error: #{inspect(reason)}"}
      end
    end
  end
  
  defp parse_anthropic_model(model) do
    %Types.Model{
      id: model["id"],
      name: format_model_name(model["id"]),
      description: generate_anthropic_description(model["id"]),
      context_window: model["context_length"] || 200_000,
      capabilities: %{
        supports_streaming: true,
        supports_functions: model["supports_tools"] || false,
        supports_vision: model["supports_vision"] || false,
        features: build_anthropic_capabilities(model)
      }
    }
  end
  
  defp build_anthropic_capabilities(model) do
    capabilities = ["streaming"]
    
    capabilities = if model["supports_tools"], do: ["function_calling" | capabilities], else: capabilities
    capabilities = if model["supports_vision"], do: ["vision" | capabilities], else: capabilities
    capabilities = if Map.get(model, "supports_system_messages", true), do: ["system_messages" | capabilities], else: capabilities
    
    capabilities
  end
  
  # Transform config data to Anthropic model format
  defp anthropic_model_transformer(model_id, config) do
    # Use base transformer but override description
    base_model = default_model_transformer(model_id, config)
    %{base_model |
      description: Map.get(config, :description, generate_anthropic_description(to_string(model_id))),
      context_window: Map.get(config, :context_window, 200_000)
    }
  end
  
  defp generate_anthropic_description(model_id) do
    cond do
      String.contains?(model_id, "opus-4") -> "Claude Opus 4: Most intelligent model"
      String.contains?(model_id, "sonnet-4") -> "Claude Sonnet 4: Best value model"
      String.contains?(model_id, "opus") -> "Most capable model with advanced reasoning"
      String.contains?(model_id, "sonnet") -> "Balanced model for general tasks"
      String.contains?(model_id, "haiku") -> "Fast and efficient model for simple tasks"
      true -> "Claude model"
    end
  end

  # Private functions

  defp get_config(config_provider) do
    case config_provider do
      ConfigProvider.Env ->
        %{
          api_key: config_provider.get(:anthropic, :api_key),
          base_url: config_provider.get(:anthropic, :base_url),
          model: config_provider.get(:anthropic, :model),
          max_tokens: nil
        }

      provider when is_pid(provider) ->
        # Static provider
        anthropic_config = ConfigProvider.Static.get(provider, :anthropic) || %{}

        %{
          api_key: Map.get(anthropic_config, :api_key),
          base_url: Map.get(anthropic_config, :base_url),
          model: Map.get(anthropic_config, :model),
          max_tokens: Map.get(anthropic_config, :max_tokens)
        }

      provider ->
        # Custom provider
        anthropic_config = provider.get_all(:anthropic) || %{}

        %{
          api_key: Map.get(anthropic_config, :api_key),
          base_url: Map.get(anthropic_config, :base_url),
          model: Map.get(anthropic_config, :model),
          max_tokens: Map.get(anthropic_config, :max_tokens)
        }
    end
  end

  defp get_api_key(config_provider) do
    get_config(config_provider).api_key
  end

  defp get_base_url(config_provider) do
    get_config(config_provider).base_url || @default_base_url
  end

  defp format_messages_for_anthropic(messages) do
    # Anthropic expects alternating user/assistant messages
    # System messages should be extracted and sent separately
    messages
    |> Enum.reject(fn msg -> msg.role == "system" end)
    |> Enum.map(fn msg ->
      formatted_content = format_content_for_anthropic(msg.content)

      %{
        role: msg.role,
        content: formatted_content
      }
    end)
  end

  defp format_content_for_anthropic(content) when is_binary(content) do
    # Simple text content
    content
  end

  defp format_content_for_anthropic(content) when is_list(content) do
    # Multimodal content with text and images
    Enum.map(content, fn part ->
      case part do
        %{"type" => "text", "text" => text} ->
          %{type: "text", text: text}

        %{type: "text", text: text} ->
          %{type: "text", text: text}

        %{"type" => "image", "image" => image_data} ->
          format_image_for_anthropic(image_data)

        %{type: "image", image: image_data} ->
          format_image_for_anthropic(image_data)

        %{"type" => "image_url", "image_url" => %{"url" => _url}} ->
          # For URLs, we might need to download and convert to base64
          # For now, return an error as Anthropic prefers base64
          %{
            type: "image",
            source: %{
              type: "base64",
              media_type: "image/jpeg",
              data: "placeholder_for_url_download"
            }
          }

        _ ->
          part
      end
    end)
  end

  defp format_image_for_anthropic(%{"data" => data, "media_type" => media_type}) do
    %{
      type: "image",
      source: %{
        type: "base64",
        media_type: media_type,
        data: data
      }
    }
  end

  defp format_image_for_anthropic(%{data: data, media_type: media_type}) do
    %{
      type: "image",
      source: %{
        type: "base64",
        media_type: media_type,
        data: data
      }
    }
  end

  defp maybe_add_system(body, options) do
    case Keyword.get(options, :system) do
      nil -> body
      system -> Map.put(body, :system, system)
    end
  end

  defp maybe_add_temperature(body, options) do
    case Keyword.get(options, :temperature) do
      nil -> body
      temp when is_number(temp) -> Map.put(body, :temperature, temp)
      _ -> body
    end
  end

  defp parse_response(response) do
    content =
      response["content"]
      |> List.first()
      |> Map.get("text", "")

    usage =
      case response["usage"] do
        nil ->
          nil

        usage_map ->
          %{
            input_tokens: Map.get(usage_map, "input_tokens", 0),
            output_tokens: Map.get(usage_map, "output_tokens", 0)
          }
      end

    # Calculate cost if we have usage data
    cost =
      if usage && response["model"] do
        ExLLM.Cost.calculate("anthropic", response["model"], usage)
      else
        nil
      end

    %Types.LLMResponse{
      content: content,
      model: response["model"],
      usage: usage,
      finish_reason: response["stop_reason"],
      id: response["id"],
      cost: cost
    }
  end

  defp handle_response_status(response, parent) do
    if response.status == 200 do
      handle_stream_response(response, parent, "")
    else
      send(parent, {:stream_error, "HTTP #{response.status}"})
    end
  end

  defp handle_stream_response(response, parent, buffer) do
    receive do
      {:finch, _ref, {:status, _status}} ->
        handle_stream_response(response, parent, buffer)

      {:finch, _ref, {:headers, _headers}} ->
        handle_stream_response(response, parent, buffer)

      {:finch, _ref, {:data, data}} ->
        new_buffer = buffer <> data
        {chunks, remaining_buffer} = parse_sse_chunks(new_buffer)

        Enum.each(chunks, fn chunk ->
          case parse_anthropic_chunk(chunk) do
            {:ok, parsed_chunk} -> send(parent, {:chunk, parsed_chunk})
            {:error, _} -> :ignore
          end
        end)

        handle_stream_response(response, parent, remaining_buffer)

      {:finch, _ref, :done} ->
        send(parent, :stream_done)

      {:finch, _ref, {:error, error}} ->
        send(parent, {:stream_error, inspect(error)})
    after
      30_000 ->
        send(parent, {:stream_error, "Stream timeout"})
    end
  end

  defp parse_sse_chunks(data) do
    # Parse Server-Sent Events format
    lines = String.split(data, "\n")
    {chunks, buffer} = extract_complete_chunks(lines, [])
    {chunks, buffer}
  end

  defp extract_complete_chunks([], acc), do: {Enum.reverse(acc), ""}
  defp extract_complete_chunks([line], _acc), do: {[], line}

  defp extract_complete_chunks([line | rest], acc) do
    if String.starts_with?(line, "data: ") do
      data = String.slice(line, 6..-1//1)

      if data == "[DONE]" do
        {Enum.reverse(acc), ""}
      else
        extract_complete_chunks(rest, [data | acc])
      end
    else
      extract_complete_chunks(rest, acc)
    end
  end

  defp parse_anthropic_chunk(chunk_data) do
    case Jason.decode(chunk_data) do
      {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
        {:ok, %Types.StreamChunk{content: text}}

      {:ok, %{"type" => "message_stop"}} ->
        {:ok, %Types.StreamChunk{finish_reason: "stop"}}

      {:ok, _} ->
        {:ok, %Types.StreamChunk{}}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end
end
