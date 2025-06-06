defmodule ExLLM.Adapters.Gemini do
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
      ExLLM.Adapters.Gemini.chat(messages, config_provider: ExLLM.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        gemini: %{
          api_key: "your-api-key",
          model: "gemini-2.5-flash-preview-05-20"
        }
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      ExLLM.Adapters.Gemini.chat(messages, config_provider: provider)

  ## Example Usage

      messages = [
        %{role: "user", content: "Hello, how are you?"}
      ]

      # Simple chat
      {:ok, response} = ExLLM.Adapters.Gemini.chat(messages)
      IO.puts(response.content)

      # Streaming chat
      {:ok, stream} = ExLLM.Adapters.Gemini.stream_chat(messages)
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
      {:ok, response} = ExLLM.Adapters.Gemini.chat(messages, options)
  """

  @behaviour ExLLM.Adapter

  alias ExLLM.{Error, Types, ModelConfig, Logger}
  alias ExLLM.Adapters.Shared.{ModelUtils, ConfigHelper}

  @base_url "https://generativelanguage.googleapis.com"
  @api_version "v1beta"

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
      {:error, "Google API key not configured"}
    else
      model = Keyword.get(options, :model, Map.get(config, :model, ConfigHelper.ensure_default_model(:gemini)))

      with {:ok, request_body} <- build_request_body(messages, options),
           {:ok, response} <- call_gemini_api(model, request_body, api_key) do
        parse_response(response, model)
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
      {:error, "Google API key not configured"}
    else
      model = Keyword.get(options, :model, Map.get(config, :model, ConfigHelper.ensure_default_model(:gemini)))

      with {:ok, request_body} <- build_request_body(messages, options) do
        stream_gemini_api(model, request_body, api_key)
      end
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
    ExLLM.ModelLoader.load_models(:gemini,
      Keyword.merge(options, [
        api_fetcher: fn(_opts) -> fetch_gemini_models(config) end,
        config_transformer: &gemini_model_transformer/2
      ])
    )
  end
  
  defp fetch_gemini_models(config) do
    api_key = get_api_key(config)

    if !api_key || api_key == "" do
      {:error, "Google API key not configured"}
    else
      url = "#{@base_url}/#{@api_version}/models?key=#{api_key}"

      case Req.get(url) do
        {:ok, %{status: 200, body: body}} ->
          models =
            body["models"]
            |> Enum.filter(&is_gemini_chat_model?/1)
            |> Enum.map(&parse_gemini_api_model/1)
            |> Enum.sort_by(& &1.id)

          {:ok, models}

        {:ok, %{status: status, body: body}} ->
          Logger.debug("Gemini API returned status #{status}: #{inspect(body)}")
          {:error, "API returned status #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
  
  defp is_gemini_chat_model?(model) do
    # Filter for Gemini chat models
    String.starts_with?(model["name"], "models/gemini")
  end
  
  defp parse_gemini_api_model(model) do
    model_id = String.replace_prefix(model["name"], "models/", "")
    
    %Types.Model{
      id: model_id,
      name: Map.get(model, "displayName", model_id),
      description: Map.get(model, "description"),
      context_window: get_input_token_limit(model),
      capabilities: parse_gemini_capabilities(model)
    }
  end
  
  defp get_input_token_limit(model) do
    get_in(model, ["inputTokenLimit"]) || 1_048_576
  end
  
  defp parse_gemini_capabilities(model) do
    supported_methods = Map.get(model, "supportedGenerationMethods", [])
    
    features = []
    features = if "generateContent" in supported_methods, do: [:streaming | features], else: features
    features = if model["name"] =~ "vision", do: [:vision | features], else: features
    
    %{
      supports_streaming: "generateContent" in supported_methods,
      supports_functions: false,  # Gemini uses different mechanism
      supports_vision: model["name"] =~ "vision" || String.contains?(model["name"], "gemini-1.5") || String.contains?(model["name"], "gemini-2"),
      features: features
    }
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
        Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
      )

    config = get_config(config_provider)
    api_key = get_api_key(config)
    !is_nil(api_key) && api_key != ""
  end

  @impl true
  def default_model do
    ConfigHelper.ensure_default_model(:gemini)
  end

  # Default model fetching moved to shared ConfigHelper module

  # Private functions

  defp get_config(config_provider) do
    config_provider.get_all(:gemini)
  end

  defp get_api_key(config) do
    Map.get(config, :api_key) || System.get_env("GOOGLE_API_KEY") ||
      System.get_env("GEMINI_API_KEY")
  end

  defp build_request_body(messages, options) do
    contents = format_messages_for_gemini(messages)

    generation_config = %{
      temperature: Keyword.get(options, :temperature, 0.7),
      topP: Keyword.get(options, :top_p, 0.95),
      topK: Keyword.get(options, :top_k, 40),
      maxOutputTokens: Keyword.get(options, :max_tokens, 2_048)
    }

    safety_settings = get_safety_settings(options)

    body = %{
      contents: contents,
      generationConfig: generation_config
    }

    body = if safety_settings, do: Map.put(body, :safetySettings, safety_settings), else: body

    {:ok, body}
  end

  defp format_messages_for_gemini(messages) do
    messages
    |> Enum.map(fn msg ->
      role =
        case to_string(msg.role || msg["role"]) do
          # Gemini doesn't have system role
          "system" -> "user"
          "assistant" -> "model"
          role -> role
        end

      %{
        role: role,
        parts: [%{text: to_string(msg.content || msg["content"])}]
      }
    end)
    |> merge_system_messages()
  end

  defp merge_system_messages(messages) do
    # Merge system messages into the first user message
    case messages do
      [%{role: "user", parts: parts} = first | rest] ->
        system_parts =
          messages
          |> Enum.take_while(&(&1.role == "user"))
          |> Enum.drop(1)
          |> Enum.flat_map(& &1.parts)

        if length(system_parts) > 0 do
          merged_first = %{first | parts: system_parts ++ parts}
          [merged_first | Enum.drop_while(rest, &(&1.role == "user"))]
        else
          messages
        end

      _ ->
        messages
    end
  end

  defp get_safety_settings(options) do
    Keyword.get(options, :safety_settings, [
      %{category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_MEDIUM_AND_ABOVE"},
      %{category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_MEDIUM_AND_ABOVE"},
      %{category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_MEDIUM_AND_ABOVE"},
      %{category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_MEDIUM_AND_ABOVE"}
    ])
  end

  defp call_gemini_api(model, request_body, api_key) do
    url = build_url(model, "generateContent", api_key)
    headers = [{"content-type", "application/json"}]

    case Req.post(url, json: request_body, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Error.api_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stream_gemini_api(model, request_body, api_key) do
    url = build_url(model, "streamGenerateContent", api_key)

    headers = [
      {"content-type", "application/json"},
      {"accept", "text/event-stream"}
    ]

    parent = self()

    # Start async request task
    Task.start(fn ->
      case Req.post(url,
             json: request_body,
             headers: headers,
             receive_timeout: 60_000,
             into: :self
           ) do
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

  defp build_url(model, method, api_key) do
    "#{@base_url}/#{@api_version}/models/#{model}:#{method}?key=#{api_key}"
  end

  defp parse_response(%{"candidates" => [candidate | _]}, model) do
    case candidate do
      %{"content" => %{"parts" => parts}} ->
        content =
          parts
          |> Enum.map_join(fn %{"text" => text} -> text end, "")

        # Gemini doesn't provide token usage, so we estimate
        # Placeholder
        prompt_tokens = 100
        completion_tokens = ExLLM.Cost.estimate_tokens(content)

        %Types.LLMResponse{
          content: content,
          usage: %{
            input_tokens: prompt_tokens,
            output_tokens: completion_tokens,
            total_tokens: prompt_tokens + completion_tokens
          },
          model: model,
          finish_reason: candidate["finishReason"] || "stop",
          cost:
            ExLLM.Cost.calculate("gemini", model, %{
              input_tokens: prompt_tokens,
              output_tokens: completion_tokens
            })
        }

      %{"finishReason" => reason} when reason in ["SAFETY", "RECITATION"] ->
        {:error, "Response blocked: #{reason}"}

      _ ->
        {:error, "Unexpected response format"}
    end
  end

  defp parse_response(%{"error" => error}, _model) do
    Error.api_error(error["code"] || 500, error["message"])
  end

  defp parse_response(_, _model) do
    {:error, "Invalid response format"}
  end

  defp handle_stream_response(response, parent, model, buffer) do
    %Req.Response.Async{ref: ref} = response.body

    receive do
      {^ref, {:data, data}} ->
        {new_buffer, chunks} = parse_sse_data(buffer <> data)
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

  defp parse_sse_data(data) do
    lines = String.split(data, "\n")

    {complete_lines, rest} =
      case List.last(lines) do
        "" -> {lines, ""}
        last_line -> {Enum.drop(lines, -1), last_line}
      end

    chunks =
      complete_lines
      |> Enum.filter(&String.starts_with?(&1, "data: "))
      |> Enum.map(&String.replace_prefix(&1, "data: ", ""))
      |> Enum.reject(&(&1 == "[DONE]"))
      |> Enum.map(&parse_streaming_chunk/1)
      |> Enum.reject(&is_nil/1)

    {rest, chunks}
  end

  defp parse_streaming_chunk(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"candidates" => [%{"content" => %{"parts" => parts}} | _]}} ->
        text =
          parts
          |> Enum.map_join(fn %{"text" => text} -> text end, "")

        %Types.StreamChunk{
          content: text,
          finish_reason: nil
        }

      {:ok, %{"candidates" => [%{"finishReason" => reason} | _]}} ->
        %Types.StreamChunk{
          content: "",
          finish_reason: reason
        }

      _ ->
        nil
    end
  end
end
