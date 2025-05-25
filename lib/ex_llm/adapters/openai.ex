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

  alias ExLLM.{ConfigProvider, Error, Types}

  @default_base_url "https://api.openai.com/v1"
  @default_model "gpt-4-turbo"
  @default_max_tokens 4_096
  @default_temperature 0.7

  @impl true
  def chat(messages, options \\ []) do
    config_provider = Keyword.get(options, :config_provider, Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default))
    config = get_config(config_provider)
    
    api_key = get_api_key(config)
    if !api_key || api_key == "", do: return {:error, "OpenAI API key not configured"}
    
    model = Keyword.get(options, :model, Map.get(config, :model, @default_model))
    max_tokens = Keyword.get(options, :max_tokens, Map.get(config, :max_tokens, @default_max_tokens))
    temperature = Keyword.get(options, :temperature, Map.get(config, :temperature, @default_temperature))

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
        Error.api_error("OpenAI", status, body)

      {:error, reason} ->
        Error.request_error("OpenAI", reason)
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    config_provider = Keyword.get(options, :config_provider, Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default))
    config = get_config(config_provider)
    
    api_key = get_api_key(config)
    if !api_key || api_key == "", do: return {:error, "OpenAI API key not configured"}
    
    model = Keyword.get(options, :model, Map.get(config, :model, @default_model))
    max_tokens = Keyword.get(options, :max_tokens, Map.get(config, :max_tokens, @default_max_tokens))
    temperature = Keyword.get(options, :temperature, Map.get(config, :temperature, @default_temperature))

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
            send(parent, {:stream_error, Error.api_error("OpenAI", response.status, response.body)})
          end

        {:error, reason} ->
          send(parent, {:stream_error, Error.request_error("OpenAI", reason)})
      end
    end)

    # Create stream that receives messages
    stream = Stream.resource(
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

  @impl true
  def list_models(options \\ []) do
    config_provider = Keyword.get(options, :config_provider, Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default))
    config = get_config(config_provider)
    
    api_key = get_api_key(config)
    if !api_key || api_key == "", do: return {:error, "OpenAI API key not configured"}

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    url = "#{get_base_url(config)}/models"
    
    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        models = body["data"]
        |> Enum.filter(fn model ->
          # Filter for chat models
          String.contains?(model["id"], "gpt") and
            not String.contains?(model["id"], "instruct")
        end)
        |> Enum.map(fn model ->
          %Types.Model{
            id: model["id"],
            name: model["id"],
            context_window: get_context_window(model["id"]),
            max_output_tokens: get_max_output_tokens(model["id"])
          }
        end)
        |> Enum.sort_by(& &1.id, :desc)

        {:ok, models}

      {:ok, %{status: status, body: body}} ->
        # Fallback to static list
        {:ok, fallback_models()}

      {:error, _reason} ->
        # Fallback to static list
        {:ok, fallback_models()}
    end
  end

  # Private functions

  defp get_config(config_provider) do
    ConfigProvider.get(config_provider, :openai)
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
      %{
        "role" => to_string(msg.role || msg["role"]),
        "content" => to_string(msg.content || msg["content"])
      }
    end)
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
      cost: ExLLM.Cost.calculate("openai", model, usage["prompt_tokens"] || 0, usage["completion_tokens"] || 0)
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
        send(parent, {:stream_error, Error.request_error("OpenAI", reason)})
    after
      30_000 ->
        send(parent, {:stream_error, Error.timeout_error("OpenAI")})
    end
  end

  defp get_context_window(model_id) do
    case model_id do
      "gpt-4-turbo" <> _ -> 128_000
      "gpt-4-1106" <> _ -> 128_000
      "gpt-4-32k" <> _ -> 32_768
      "gpt-4" <> _ -> 8_192
      "gpt-3.5-turbo-1106" -> 16_385
      "gpt-3.5-turbo-16k" <> _ -> 16_385
      "gpt-3.5-turbo" <> _ -> 4_096
      _ -> 4_096
    end
  end

  defp get_max_output_tokens(model_id) do
    case model_id do
      "gpt-4-turbo" <> _ -> 4_096
      "gpt-4" <> _ -> 4_096
      "gpt-3.5-turbo" <> _ -> 4_096
      _ -> 4_096
    end
  end

  defp fallback_models() do
    [
      %Types.Model{
        id: "gpt-4-turbo",
        name: "GPT-4 Turbo",
        context_window: 128_000,
        max_output_tokens: 4_096
      },
      %Types.Model{
        id: "gpt-4",
        name: "GPT-4",
        context_window: 8_192,
        max_output_tokens: 4_096
      },
      %Types.Model{
        id: "gpt-4-32k",
        name: "GPT-4 32K",
        context_window: 32_768,
        max_output_tokens: 4_096
      },
      %Types.Model{
        id: "gpt-3.5-turbo",
        name: "GPT-3.5 Turbo",
        context_window: 4_096,
        max_output_tokens: 4_096
      },
      %Types.Model{
        id: "gpt-3.5-turbo-16k",
        name: "GPT-3.5 Turbo 16K",
        context_window: 16_385,
        max_output_tokens: 4_096
      }
    ]
  end
end