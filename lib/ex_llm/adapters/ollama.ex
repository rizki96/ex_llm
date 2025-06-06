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

  alias ExLLM.{Error, Types, Logger}
  alias ExLLM.Adapters.Shared.ConfigHelper

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

    raw_model = Keyword.get(options, :model, Map.get(config, :model, get_default_model()))
    # Strip provider prefix if present
    model = strip_provider_prefix(raw_model)
    
    # Ensure we have a model
    model = model || get_default_model()

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

    raw_model = Keyword.get(options, :model, Map.get(config, :model, get_default_model()))
    # Strip provider prefix if present
    model = strip_provider_prefix(raw_model)
    
    # Ensure we have a model
    model = model || get_default_model()

    formatted_messages = format_messages(messages)
    
    body = %{
      model: model,
      messages: formatted_messages,
      stream: true
    }
    
    # Debug log the request
    Logger.debug("Ollama request - Model: #{model}, Messages: #{inspect(formatted_messages, limit: :infinity)}")

    headers = [{"content-type", "application/json"}]
    url = "#{get_base_url(config)}/api/chat"
    parent = self()

    # Clear any stale messages from mailbox
    flush_mailbox()
    
    # Start async request task
    Task.start(fn ->
      case Req.post(url, json: body, headers: headers, receive_timeout: 300_000, into: :self) do
        {:ok, response} ->
          if response.status == 200 do
            handle_stream_response(response, parent, model)
          else
            Logger.error("Ollama API error - Status: #{response.status}, Body: #{inspect(response.body)}")
            send(parent, {:stream_error, Error.api_error(response.status, response.body)})
          end

        {:error, reason} ->
          Logger.error("Ollama connection error: #{inspect(reason)}")
          send(parent, {:stream_error, Error.connection_error(reason)})
      end
    end)

    # Create stream that receives messages
    stream =
      Stream.resource(
        fn -> :ok end,
        fn state ->
          receive do
            {:chunk, chunk} -> 
              {[chunk], state}
            :stream_done -> 
              {:halt, state}
            {:stream_error, error} -> 
              Logger.error("Stream error: #{inspect(error)}")
              throw(error)
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
    
    # Use ModelLoader with API fetching from Ollama server
    ExLLM.ModelLoader.load_models(:ollama,
      Keyword.merge(options, [
        api_fetcher: fn(_opts) -> fetch_ollama_models(config) end,
        config_transformer: &ollama_model_transformer/2
      ])
    )
  end
  
  defp fetch_ollama_models(config) do
    url = "#{get_base_url(config)}/api/tags"

    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} ->
        models =
          body["models"]
          |> Enum.map(&parse_ollama_api_model/1)

        {:ok, models}

      {:ok, %{status: status, body: body}} ->
        Logger.debug("Ollama API returned status #{status}: #{inspect(body)}")
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        Logger.debug("Failed to connect to Ollama: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp parse_ollama_api_model(model) do
    %Types.Model{
      id: model["name"],
      name: model["name"],
      description: format_ollama_description(model),
      context_window: get_ollama_context_window(model),
      capabilities: %{
        supports_streaming: true,
        supports_functions: false,
        supports_vision: is_vision_model?(model["name"]),
        features: [:streaming]
      }
    }
  end
  
  defp format_ollama_description(model) do
    details = model["details"] || %{}
    family = details["family"]
    param_size = details["parameter_size"]
    quantization = details["quantization_level"]
    
    parts = [family, param_size, quantization]
    |> Enum.filter(&(&1))
    |> Enum.join(", ")
    
    if parts != "", do: parts, else: nil
  end
  
  defp get_ollama_context_window(model) do
    # Try to extract from model details or use default
    case get_in(model, ["details", "parameter_size"]) do
      nil -> 4_096
      size_str when is_binary(size_str) ->
        # Convert parameter size to approximate context window
        if String.contains?(size_str, "B") do
          # Rough estimation: larger models typically have larger context
          cond do
            String.contains?(size_str, "70B") -> 32_768
            String.contains?(size_str, "34B") -> 16_384
            String.contains?(size_str, "13B") -> 8_192
            String.contains?(size_str, "7B") -> 4_096
            true -> 4_096
          end
        else
          4_096
        end
      _ -> 4_096
    end
  end
  
  defp is_vision_model?(model_name) do
    String.contains?(model_name, "vision") || 
    String.contains?(model_name, "llava") ||
    String.contains?(model_name, "bakllava")
  end
  
  # Transform config data to Ollama model format
  defp ollama_model_transformer(model_id, config) do
    %Types.Model{
      id: to_string(model_id),
      name: Map.get(config, :name, to_string(model_id)),
      description: Map.get(config, :description),
      context_window: Map.get(config, :context_window, 4_096),
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
    model = ConfigHelper.ensure_default_model(:ollama)
    # Strip the "ollama/" prefix if present
    strip_provider_prefix(model)
  end
  
  defp strip_provider_prefix(model) when is_binary(model) do
    case String.split(model, "/", parts: 2) do
      ["ollama", actual_model] -> actual_model
      _ -> model
    end
  end
  
  defp strip_provider_prefix(nil), do: nil

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
      input_tokens: response["prompt_eval_count"] || 0,
      output_tokens: response["eval_count"] || 0,
      total_tokens: (response["prompt_eval_count"] || 0) + (response["eval_count"] || 0)
    }

    %Types.LLMResponse{
      content: get_in(response, ["message", "content"]) || "",
      usage: usage,
      model: model,
      finish_reason: if(response["done"], do: "stop", else: nil),
      cost:
        ExLLM.Cost.calculate("ollama", model, usage)
    }
  end

  defp flush_mailbox do
    receive do
      :stream_done -> 
        Logger.debug("Flushing stale :stream_done message")
        flush_mailbox()
      {:chunk, _} -> 
        Logger.debug("Flushing stale chunk message")
        flush_mailbox()
      {:stream_error, _} -> 
        Logger.debug("Flushing stale error message")
        flush_mailbox()
    after
      0 -> :ok
    end
  end

  defp handle_stream_response(response, parent, model) do
    %Req.Response.Async{ref: ref} = response.body

    receive do
      {^ref, {:data, data}} ->
        # Parse each line of the NDJSON response
        lines = String.split(data, "\n", trim: true)
        
        # Debug log raw response
        if length(lines) == 1 and String.contains?(data, "done") do
          Logger.debug("Ollama single-line response: #{inspect(data)}")
        end
        
        lines
        |> Enum.each(fn line ->
          case Jason.decode(line) do
            {:ok, chunk} ->
              if chunk["done"] do
                # Check if we got a finish reason or error
                finish_reason = chunk["finish_reason"]
                if finish_reason == "error" do
                  error_msg = chunk["error"] || "Unknown error"
                  Logger.warn("Ollama streaming error: #{error_msg}")
                end
                
                # Log if we finished without generating any content
                total_duration = chunk["total_duration"]
                eval_count = chunk["eval_count"] || 0
                if eval_count == 0 do
                  Logger.warn("Ollama finished without generating tokens. Total duration: #{total_duration / 1_000_000}ms")
                end
                
                send(parent, :stream_done)
              else
                content = get_in(chunk, ["message", "content"]) || ""
                
                # Log if we're getting chunks but no content
                if content == "" do
                  Logger.debug("Ollama: Received chunk with empty content: #{inspect(chunk)}")
                end

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

        # Continue receiving more data
        handle_stream_response(response, parent, model)

      {^ref, :done} ->
        Logger.debug("Ollama: Stream done")
        send(parent, :stream_done)

      {^ref, {:error, reason}} ->
        send(parent, {:stream_error, {:error, reason}})
    after
      120_000 ->  # Increase to 2 minutes for slower models
        send(parent, {:stream_error, {:error, :timeout}})
    end
  end
  
  @impl true
  def embeddings(inputs, options \\ []) do
    config_provider =
      Keyword.get(
        options,
        :config_provider,
        Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
      )

    config = get_config(config_provider)
    
    raw_model = Keyword.get(options, :model, Map.get(config, :embedding_model, "nomic-embed-text"))
    # Strip provider prefix if present
    model = strip_provider_prefix(raw_model)
    
    # Process each input
    embeddings_results = Enum.map(inputs, fn input ->
      body = %{
        model: model,
        prompt: input
      }
      
      headers = [{"content-type", "application/json"}]
      url = "#{get_base_url(config)}/api/embeddings"
      
      case Req.post(url, json: body, headers: headers, receive_timeout: 30_000) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body["embedding"]}
          
        {:ok, %{status: status, body: body}} ->
          {:error, "API returned status #{status}: #{inspect(body)}"}
          
        {:error, reason} ->
          {:error, reason}
      end
    end)
    
    # Check if all embeddings were successful
    case Enum.all?(embeddings_results, fn {status, _} -> status == :ok end) do
      true ->
        embeddings = Enum.map(embeddings_results, fn {:ok, embedding} -> embedding end)
        
        {:ok, %Types.EmbeddingResponse{
          embeddings: embeddings,
          model: model,
          usage: %{
            input_tokens: estimate_embedding_tokens(inputs),
            output_tokens: 0,  # Embeddings don't have output tokens
            total_tokens: estimate_embedding_tokens(inputs)
          }
        }}
        
      false ->
        # Find first error
        {:error, _} = Enum.find(embeddings_results, fn {status, _} -> status == :error end)
    end
  end
  
  @impl true
  def list_embedding_models(options \\ []) do
    case list_models(options) do
      {:ok, models} ->
        # Filter to only embedding models
        embedding_models = 
          models
          |> Enum.filter(fn model ->
            String.contains?(model.name, "embed") || 
            String.contains?(model.name, "embedding")
          end)
          |> Enum.map(fn model ->
            %Types.EmbeddingModel{
              name: model.name,
              dimensions: estimate_embedding_dimensions(model.name),
              max_inputs: 1,  # Ollama processes one at a time
              provider: :ollama,
              description: model.description
            }
          end)
          
        {:ok, embedding_models}
        
      error -> error
    end
  end
  
  defp estimate_embedding_tokens(inputs) when is_list(inputs) do
    inputs
    |> Enum.map(&String.length/1)
    |> Enum.sum()
    |> div(4)  # Rough estimate: 4 chars per token
  end
  
  defp estimate_embedding_dimensions(model_name) do
    cond do
      String.contains?(model_name, "nomic") -> 768
      String.contains?(model_name, "mxbai") -> 512
      String.contains?(model_name, "all-minilm") -> 384
      true -> 1024  # Default dimension
    end
  end
end
