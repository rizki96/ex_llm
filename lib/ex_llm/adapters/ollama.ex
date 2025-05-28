defmodule ExLLM.Adapters.Ollama do
  @moduledoc """
  Ollama API adapter for ExLLM - provides local model inference via Ollama server.

  ## Configuration

  This adapter requires a running Ollama server. By default, it connects to localhost:11434.

  ### Using Environment Variables

      # Set environment variables
      export OLLAMA_API_BASE="http://localhost:11434"  # optional
      export OLLAMA_MODEL="llama2"  # optional

      # Use with default environment provider
      ExLLM.Adapters.Ollama.chat(messages, config_provider: ExLLM.ConfigProvider.Env)

  ### Using Static Configuration

      config = %{
        ollama: %{
          base_url: "http://localhost:11434",
          model: "llama2"
        }
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      ExLLM.Adapters.Ollama.chat(messages, config_provider: provider)

  ## Example Usage

      messages = [
        %{role: "user", content: "Hello, how are you?"}
      ]

      # Simple chat
      {:ok, response} = ExLLM.Adapters.Ollama.chat(messages)
      IO.puts(response.content)

      # Streaming chat
      {:ok, stream} = ExLLM.Adapters.Ollama.stream_chat(messages)
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end

  ## Available Models

  To see available models, ensure Ollama is running and use:

      {:ok, models} = ExLLM.Adapters.Ollama.list_models()
  """

  @behaviour ExLLM.Adapter

  alias ExLLM.{Error, Types, ModelConfig}
  require Logger

  @default_base_url "http://localhost:11434"

  @impl true
  def chat(messages, options \\ []) do
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
      )

    config = get_config(config_provider)

    model = Keyword.get(options, :model, Map.get(config, :model, get_default_model()))

    body = %{
      model: model,
      messages: format_messages(messages),
      stream: false
    }

    headers = [{"content-type", "application/json"}]
    url = "#{get_base_url(config)}/api/chat"

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, parse_response(response, model)}

      {:ok, %{status: status, body: body}} ->
        Error.api_error(status, body)

      {:error, reason} ->
        Error.connection_error(reason)
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

    model = Keyword.get(options, :model, Map.get(config, :model, get_default_model()))

    body = %{
      model: model,
      messages: format_messages(messages),
      stream: true
    }

    headers = [{"content-type", "application/json"}]
    url = "#{get_base_url(config)}/api/chat"
    parent = self()

    # Start async request task
    Task.start(fn ->
      case Req.post(url, json: body, headers: headers, receive_timeout: 60_000, into: :self) do
        {:ok, response} ->
          if response.status == 200 do
            handle_stream_response(response, parent, model)
          else
            send(parent, {:stream_error, Error.api_error(response.status, response.body)})
          end

        {:error, reason} ->
          send(parent, {:stream_error, Error.connection_error(reason)})
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

  @impl true
  def list_models(options \\ []) do
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
      )

    config = get_config(config_provider)

    url = "#{get_base_url(config)}/api/tags"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        models =
          body["models"]
          |> Enum.map(fn model ->
            %Types.Model{
              id: model["name"],
              name: model["name"],
              context_window: model["details"]["parameter_size"] || 4_096
            }
          end)

        {:ok, models}

      {:ok, %{status: status, body: body}} ->
        Error.api_error(status, body)

      {:error, reason} ->
        Error.connection_error(reason)
    end
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
    base_url = get_base_url(config)
    # Ollama only needs a base URL to be configured
    !is_nil(base_url) && base_url != ""
  end

  @impl true
  def default_model do
    get_default_model()
  end

  # Private helper to get default model from config
  defp get_default_model do
    ModelConfig.get_default_model(:ollama) || "llama2"
  end

  # Private functions

  defp get_config(config_provider) do
    config_provider.get_all(:ollama)
  end

  defp get_base_url(config) do
    # Check environment variable first, then config, then default
    System.get_env("OLLAMA_API_BASE") ||
      Map.get(config, :base_url) ||
      @default_base_url
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        role: to_string(msg.role || msg["role"]),
        content: to_string(msg.content || msg["content"])
      }
    end)
  end

  defp parse_response(response, model) do
    usage = %{
      prompt_tokens: response["prompt_eval_count"] || 0,
      completion_tokens: response["eval_count"] || 0,
      total_tokens: (response["prompt_eval_count"] || 0) + (response["eval_count"] || 0)
    }

    %Types.LLMResponse{
      content: get_in(response, ["message", "content"]) || "",
      usage: usage,
      model: model,
      finish_reason: if(response["done"], do: "stop", else: nil),
      cost:
        ExLLM.Cost.calculate("ollama", model, %{
          input_tokens: usage.prompt_tokens,
          output_tokens: usage.completion_tokens
        })
    }
  end

  defp handle_stream_response(response, parent, model) do
    %Req.Response.Async{ref: ref} = response.body

    receive do
      {^ref, {:data, data}} ->
        # Parse each line of the NDJSON response
        data
        |> String.split("\n", trim: true)
        |> Enum.each(fn line ->
          case Jason.decode(line) do
            {:ok, chunk} ->
              if chunk["done"] do
                send(parent, :stream_done)
              else
                content = get_in(chunk, ["message", "content"]) || ""

                stream_chunk = %Types.StreamChunk{
                  content: content,
                  finish_reason: nil
                }

                send(parent, {:chunk, stream_chunk})
              end

            {:error, _} ->
              # Skip invalid JSON lines
              :ok
          end
        end)

        handle_stream_response(response, parent, model)

      {^ref, :done} ->
        send(parent, :stream_done)

      {^ref, {:error, reason}} ->
        send(parent, {:stream_error, {:error, reason}})
    after
      30_000 ->
        send(parent, {:stream_error, {:error, :timeout}})
    end
  end
end
