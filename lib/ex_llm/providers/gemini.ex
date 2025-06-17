defmodule ExLLM.Providers.Gemini do
  @moduledoc """
  Google Gemini API adapter for ExLLM.

  Supports Gemini 2.5, 2.0, and 1.5 models including Flash and Pro variants.

  ## Configuration

  This adapter requires a Google API key.

  ### Using Environment Variables

      # Set environment variables
      export GOOGLE_API_KEY="your-api-key"
      export GEMINI_MODEL="gemini-2.0-flash"  # optional

      # Use with default environment provider
      ExLLM.Providers.Gemini.chat(messages, config_provider: ExLLM.Infrastructure.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        gemini: %{
          api_key: "your-api-key",
          model: "gemini-2.5-flash-preview-05-20"
        }
      }
      {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)
      ExLLM.Providers.Gemini.chat(messages, config_provider: provider)

  ## Example Usage

      messages = [
        %{role: "user", content: "Hello, how are you?"}
      ]

      # Simple chat
      {:ok, response} = ExLLM.Providers.Gemini.chat(messages)
      IO.puts(response.content)

      # Streaming chat
      {:ok, stream} = ExLLM.Providers.Gemini.stream_chat(messages)
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end

  ## Safety Settings

  You can customize safety settings:

      options = [
        safety_settings: [
          %{category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_ONLY_HIGH"},
          %{category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_ONLY_HIGH"}
        ]
      ]
      {:ok, response} = ExLLM.Providers.Gemini.chat(messages, options)
  """

  @behaviour ExLLM.Provider

  alias ExLLM.Types
  alias ExLLM.Providers.Shared.{ConfigHelper, ModelUtils}

  alias ExLLM.Providers.Gemini.Content.{
    GenerateContentRequest,
    GenerateContentResponse,
    Content,
    Part,
    GenerationConfig,
    SafetySetting,
    Tool
  }

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
      {:error, "Google API key not configured"}
    else
      model =
        Keyword.get(
          options,
          :model,
          Map.get(config, :model, ConfigHelper.ensure_default_model(:gemini))
        )

      # Convert messages to Gemini Content format
      request = build_content_request(messages, options)

      case ExLLM.Providers.Gemini.Content.generate_content(model, request,
             config_provider: config_provider
           ) do
        {:ok, response} ->
          convert_content_response_to_llm_response(response, model)

        {:error, error} ->
          {:error, error}
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
      {:error, "Google API key not configured"}
    else
      model =
        Keyword.get(
          options,
          :model,
          Map.get(config, :model, ConfigHelper.ensure_default_model(:gemini))
        )

      # Convert messages to Gemini Content format
      request = build_content_request(messages, options)

      case ExLLM.Providers.Gemini.Content.stream_generate_content(model, request,
             config_provider: config_provider
           ) do
        {:ok, stream} ->
          # Convert the Content stream to ExLLM stream format
          converted_stream =
            Stream.map(stream, fn response ->
              convert_content_response_to_stream_chunk(response)
            end)

          {:ok, converted_stream}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @impl true
  def list_models(options \\ []) do
    # Use the new Models API module
    case ExLLM.Providers.Gemini.Models.list_models(options) do
      {:ok, response} ->
        # Convert from Models API format to ExLLM Types.Model format
        models =
          response.models
          |> Enum.filter(&is_gemini_chat_model_struct?/1)
          |> Enum.map(&convert_api_model_to_types/1)
          |> Enum.sort_by(& &1.id)

        {:ok, models}

      {:error, _reason} ->
        # Fallback to config-based models if API fails
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

        _config = get_config(config_provider)

        # Use ModelLoader with config only
        ExLLM.Infrastructure.Config.ModelLoader.load_models(
          :gemini,
          Keyword.merge(options,
            api_fetcher: fn _opts -> {:ok, []} end,
            config_transformer: &gemini_model_transformer/2
          )
        )
    end
  end

  defp is_gemini_chat_model_struct?(%ExLLM.Providers.Gemini.Models.Model{} = model) do
    # Filter for Gemini chat models from API struct
    String.starts_with?(model.name, "models/gemini")
  end

  defp convert_api_model_to_types(%ExLLM.Providers.Gemini.Models.Model{} = api_model) do
    # Convert from Gemini Models API format to ExLLM Types.Model format
    model_id = String.replace_prefix(api_model.name, "models/", "")

    %Types.Model{
      id: model_id,
      name: api_model.display_name,
      description: api_model.description,
      context_window: api_model.input_token_limit,
      max_output_tokens: api_model.output_token_limit,
      capabilities: %{
        supports_streaming: "streamGenerateContent" in api_model.supported_generation_methods,
        supports_functions: "generateContent" in api_model.supported_generation_methods,
        supports_vision:
          String.contains?(model_id, "vision") ||
            String.contains?(model_id, "gemini-1.5") ||
            String.contains?(model_id, "gemini-2"),
        features: parse_features_from_methods(api_model.supported_generation_methods)
      }
    }
  end

  defp parse_features_from_methods(methods) do
    features = []
    features = if "streamGenerateContent" in methods, do: [:streaming | features], else: features
    features = if "generateContent" in methods, do: [:chat | features], else: features
    features
  end

  # Transform config data to Gemini model format
  defp gemini_model_transformer(model_id, config) do
    %Types.Model{
      id: to_string(model_id),
      name: Map.get(config, :name, ModelUtils.format_model_name(to_string(model_id))),
      description: Map.get(config, :description),
      context_window: Map.get(config, :context_window, 1_048_576),
      capabilities: %{
        supports_streaming: :streaming in Map.get(config, :capabilities, []),
        supports_functions: :function_calling in Map.get(config, :capabilities, []),
        supports_vision: :vision in Map.get(config, :capabilities, []),
        features: Map.get(config, :capabilities, [])
      }
    }
  end

  # Model name formatting moved to shared ModelUtils module

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
    ConfigHelper.ensure_default_model(:gemini)
  end

  @impl true
  def embeddings(inputs, options \\ []) do
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
      {:error, "Google API key not configured"}
    else
      model =
        Keyword.get(
          options,
          :model,
          Map.get(config, :embedding_model, "text-embedding-004")
        )

      # Use Gemini Embeddings API
      case ExLLM.Providers.Gemini.Embeddings.embed_content(model, inputs, api_key: api_key) do
        {:ok, response} ->
          # Convert from Gemini format to ExLLM format
          embeddings = Enum.map(response.embeddings, & &1.values)

          {:ok,
           %Types.EmbeddingResponse{
             embeddings: embeddings,
             model: model,
             usage: %{
               # Estimate, Gemini doesn't provide token counts
               total_tokens: length(inputs) * 100
             }
           }}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  # Default model fetching moved to shared ConfigHelper module

  # Private functions

  defp get_config(config_provider) do
    case config_provider do
      provider when is_atom(provider) ->
        provider.get_all(:gemini)

      provider when is_pid(provider) ->
        ExLLM.Infrastructure.ConfigProvider.Static.get_all(provider)
        |> Map.get(:gemini, %{})
    end
  end

  defp get_api_key(config) do
    Map.get(config, :api_key) || System.get_env("GOOGLE_API_KEY") ||
      System.get_env("GEMINI_API_KEY")
  end

  # New helper functions for Content API integration
  defp build_content_request(messages, options) do
    contents = Enum.map(messages, &convert_message_to_content/1)

    # Extract system instruction if present
    {system_instruction, contents} = extract_system_instruction(contents)

    %GenerateContentRequest{
      contents: contents,
      system_instruction: system_instruction,
      generation_config: build_generation_config(options),
      safety_settings: build_safety_settings(options),
      tools: build_tools(options)
    }
  end

  defp convert_message_to_content(%{role: role, content: content}) do
    %Content{
      role: convert_role(role),
      parts: [%Part{text: content}]
    }
  end

  defp convert_message_to_content(message) when is_map(message) do
    role = Map.get(message, "role", "user")
    content = Map.get(message, "content", "")

    %Content{
      role: convert_role(role),
      parts: [%Part{text: content}]
    }
  end

  # Gemini doesn't have system role
  defp convert_role("system"), do: "user"
  defp convert_role("assistant"), do: "model"
  defp convert_role(role), do: to_string(role)

  defp extract_system_instruction([%Content{role: "user", parts: parts} = first | rest]) do
    # Check if this was originally a system message
    case parts do
      [%Part{text: text}] when is_binary(text) ->
        if String.starts_with?(text, "System: ") or String.starts_with?(text, "[System]") do
          system_content = %Content{role: "system", parts: parts}
          {system_content, rest}
        else
          {nil, [first | rest]}
        end

      _ ->
        {nil, [first | rest]}
    end
  end

  defp extract_system_instruction(contents), do: {nil, contents}

  defp build_generation_config(options) do
    config = %GenerationConfig{
      temperature: Keyword.get(options, :temperature),
      top_p: Keyword.get(options, :top_p),
      top_k: Keyword.get(options, :top_k),
      max_output_tokens: Keyword.get(options, :max_tokens),
      stop_sequences: Keyword.get(options, :stop_sequences),
      response_mime_type: Keyword.get(options, :response_mime_type)
    }

    # Only return if any field is set
    if Enum.any?(Map.from_struct(config), fn {_k, v} -> v != nil end) do
      config
    else
      nil
    end
  end

  defp build_safety_settings(options) do
    case Keyword.get(options, :safety_settings) do
      nil ->
        nil

      settings ->
        Enum.map(settings, fn setting ->
          %SafetySetting{
            category: setting[:category] || setting["category"],
            threshold: setting[:threshold] || setting["threshold"]
          }
        end)
    end
  end

  defp build_tools(options) do
    case Keyword.get(options, :tools) do
      nil -> nil
      tools -> Enum.map(tools, &convert_tool/1)
    end
  end

  defp convert_tool(tool) do
    %Tool{
      function_declarations: tool[:function_declarations] || tool["function_declarations"]
    }
  end

  defp convert_content_response_to_llm_response(%GenerateContentResponse{} = response, model) do
    case response.candidates do
      [candidate | _] ->
        content = extract_text_from_candidate(candidate)

        # Get usage data
        usage =
          if response.usage_metadata do
            %{
              input_tokens: response.usage_metadata.prompt_token_count,
              output_tokens: response.usage_metadata.candidates_token_count,
              total_tokens: response.usage_metadata.total_token_count
            }
          else
            # Estimate if not provided
            %{
              input_tokens: 100,
              output_tokens: ExLLM.Core.Cost.estimate_tokens(content),
              total_tokens: 100 + ExLLM.Core.Cost.estimate_tokens(content)
            }
          end

        {:ok,
         %Types.LLMResponse{
           content: content,
           usage: usage,
           model: model,
           finish_reason: candidate.finish_reason || "stop",
           cost: ExLLM.Core.Cost.calculate("gemini", model, usage)
         }}

      [] ->
        # Check if blocked
        if response.prompt_feedback && response.prompt_feedback["blockReason"] do
          {:error, "Response blocked: #{response.prompt_feedback["blockReason"]}"}
        else
          {:error, "No candidates returned"}
        end
    end
  end

  defp extract_text_from_candidate(candidate) do
    candidate.content.parts
    |> Enum.map(fn part -> part.text || "" end)
    |> Enum.join("")
  end

  defp convert_content_response_to_stream_chunk(%GenerateContentResponse{} = response) do
    case response.candidates do
      [candidate | _] ->
        text = extract_text_from_candidate(candidate)

        %Types.StreamChunk{
          content: text,
          finish_reason: candidate.finish_reason
        }

      [] ->
        %Types.StreamChunk{
          content: "",
          finish_reason: "stop"
        }
    end
  end
end
