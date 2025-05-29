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

  alias ExLLM.{Error, Types, ModelConfig}
  require Logger

  @base_url "https://generativelanguage.googleapis.com"
  @api_version "v1beta"

  # Available models
  @models %{
    "gemini-2.5-flash-preview-05-20" => %{
      name: "Gemini 2.5 Flash Preview",
      supports_vision: true,
      context_window: 1_048_576,
      max_output_tokens: 8_192
    },
    "gemini-2.5-pro-preview-05-06" => %{
      name: "Gemini 2.5 Pro Preview",
      supports_vision: true,
      context_window: 1_048_576,
      max_output_tokens: 8_192
    },
    "gemini-2.0-flash" => %{
      name: "Gemini 2.0 Flash",
      supports_vision: true,
      context_window: 1_048_576,
      max_output_tokens: 8_192
    },
    "gemini-2.0-flash-lite" => %{
      name: "Gemini 2.0 Flash Lite",
      supports_vision: true,
      context_window: 1_048_576,
      max_output_tokens: 8_192
    },
    "gemini-1.5-flash" => %{
      name: "Gemini 1.5 Flash",
      supports_vision: true,
      context_window: 1_048_576,
      max_output_tokens: 8_192
    },
    "gemini-1.5-pro" => %{
      name: "Gemini 1.5 Pro",
      supports_vision: true,
      context_window: 2_097_152,
      max_output_tokens: 8_192
    }
  }

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
      model = Keyword.get(options, :model, Map.get(config, :model, get_default_model()))

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
      model = Keyword.get(options, :model, Map.get(config, :model, get_default_model()))

      with {:ok, request_body} <- build_request_body(messages, options) do
        stream_gemini_api(model, request_body, api_key)
      end
    end
  end

  @impl true
  def list_models(_options \\ []) do
    models =
      @models
      |> Enum.map(fn {id, info} ->
        %Types.Model{
          id: id,
          name: info.name,
          context_window: info.context_window
        }
      end)
      |> Enum.sort_by(& &1.id)

    {:ok, models}
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
    case ModelConfig.get_default_model(:gemini) do
      nil ->
        raise "Missing configuration: No default model found for Gemini. " <>
              "Please ensure config/models/gemini.yml exists and contains a 'default_model' field."
      model ->
        model
    end
  end

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
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
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
