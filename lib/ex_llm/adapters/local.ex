defmodule ExLLM.Adapters.Local do
  @moduledoc """
  Local LLM adapter using Bumblebee for on-device inference.
  
  This adapter enables running language models locally using Bumblebee and EXLA/EMLX backends.
  It supports Apple Silicon (via EMLX), NVIDIA GPUs (via CUDA), and CPU inference.
  
  ## Configuration
  
  The local adapter doesn't require API keys but may need backend configuration:
  
      # For Apple Silicon (automatic detection)
      {:ok, response} = ExLLM.chat(:local, messages)
      
      # With specific model
      {:ok, response} = ExLLM.chat(:local, messages, model: "microsoft/phi-2")
  
  ## Available Models
  
  - `microsoft/phi-2` - Phi-2 (2.7B) - Default
  - `meta-llama/Llama-2-7b-hf` - Llama 2 (7B)
  - `mistralai/Mistral-7B-v0.1` - Mistral (7B)
  - `EleutherAI/gpt-neo-1.3B` - GPT-Neo (1.3B)
  - `google/flan-t5-base` - Flan-T5 Base
  
  ## Features
  
  - On-device inference with no API calls
  - Automatic hardware acceleration detection
  - Support for Apple Silicon, NVIDIA GPUs, and CPUs
  - Model caching for faster subsequent loads
  - Streaming support for real-time generation
  """

  @behaviour ExLLM.Adapter

  require Logger
  alias ExLLM.{Local.ModelLoader, Types}

  @available_models [
    "microsoft/phi-2",
    "meta-llama/Llama-2-7b-hf",
    "mistralai/Mistral-7B-v0.1",
    "EleutherAI/gpt-neo-1.3B",
    "google/flan-t5-base"
  ]

  @impl true
  def chat(messages, opts \\ []) do
    if bumblebee_available?() do
      do_chat(messages, opts)
    else
      {:error, "Bumblebee is not available. Please add {:bumblebee, \"~> 0.5\"} to your dependencies."}
    end
  end

  @impl true
  def stream_chat(messages, opts \\ []) do
    if bumblebee_available?() do
      do_stream_chat(messages, opts)
    else
      {:error, "Bumblebee is not available. Please add {:bumblebee, \"~> 0.5\"} to your dependencies."}
    end
  end

  @impl true
  def configured?(_opts \\ []) do
    # Check if at least Bumblebee is available and ModelLoader is running
    bumblebee_available?() and model_loader_running?()
  end

  @impl true
  def default_model do
    "microsoft/phi-2"
  end

  @impl true
  def list_models(opts \\ []) do
    if bumblebee_available?() do
      do_list_models(opts)
    else
      {:ok, []}
    end
  end

  # Private functions when Bumblebee is available

  defp do_chat(messages, opts) do
    model = Keyword.get(opts, :model, default_model())
    stream = Keyword.get(opts, :stream, false)
    max_tokens = Keyword.get(opts, :max_tokens, 2048)
    temperature = Keyword.get(opts, :temperature, 0.7)

    # Format messages for the model
    prompt = format_messages(messages, model)

    # Get or load the model
    case ModelLoader.load_model(model) do
      {:ok, model_data} ->
        generate_response(prompt, model_data, %{
          stream: stream,
          max_tokens: max_tokens,
          temperature: temperature
        })

      {:error, reason} ->
        {:error, "Failed to load model: #{inspect(reason)}"}
    end
  end

  defp do_stream_chat(messages, opts) do
    # For now, use chat with streaming enabled
    opts = Keyword.put(opts, :stream, true)
    
    case do_chat(messages, opts) do
      {:ok, chunks} when is_list(chunks) ->
        # Convert to stream format expected by ExLLM
        stream = Stream.map(chunks, fn chunk ->
          case chunk do
            {:data, %{"content" => content}} ->
              %Types.StreamChunk{
                content: content,
                finish_reason: nil
              }
            {:error, reason} ->
              %Types.StreamChunk{
                content: "Error: #{inspect(reason)}",
                finish_reason: "error"
              }
          end
        end)
        {:ok, stream}

      {:ok, response} ->
        # Single response, wrap in stream
        stream = Stream.iterate(
          %Types.StreamChunk{
            content: response.content,
            finish_reason: "stop"
          },
          fn _ -> nil end
        )
        |> Stream.take(1)
        
        {:ok, stream}

      error ->
        error
    end
  end

  defp do_list_models(_opts) do
    # Get loaded and available models
    loaded = ModelLoader.list_loaded_models()
    acceleration = ModelLoader.get_acceleration_info()

    # Convert to ExLLM Model format
    models = Enum.map(@available_models, fn model_id ->
      is_loaded = model_id in loaded
      
      %Types.Model{
        id: model_id,
        name: humanize_model_name(model_id),
        description: "#{humanize_model_name(model_id)} - #{if is_loaded, do: "Loaded", else: "Available"} (#{acceleration.name})",
        context_window: get_context_window(model_id),
        pricing: %{input: 0.0, output: 0.0}  # Local models are free
      }
    end)

    {:ok, models}
  end

  defp format_messages(messages, model) do
    # Format messages based on model requirements
    case model do
      "meta-llama/Llama-2" <> _ ->
        format_llama2_messages(messages)

      "mistralai/Mistral" <> _ ->
        format_mistral_messages(messages)

      _ ->
        # Generic format
        messages
        |> Enum.map(fn msg ->
          role = format_role(msg["role"] || msg[:role])
          content = msg["content"] || msg[:content]
          "#{role}: #{content}"
        end)
        |> Enum.join("\n\n")
    end
  end

  defp format_role(role) do
    case to_string(role) do
      "system" -> "System"
      "user" -> "Human"
      "assistant" -> "Assistant"
      other -> String.capitalize(other)
    end
  end

  defp format_llama2_messages(messages) do
    messages
    |> Enum.map_join("\n", fn msg ->
      role = to_string(msg["role"] || msg[:role])
      content = msg["content"] || msg[:content]
      
      case role do
        "system" -> "<<SYS>>\n#{content}\n<</SYS>>\n\n"
        "user" -> "[INST] #{content} [/INST]"
        "assistant" -> content
        _ -> content
      end
    end)
  end

  defp format_mistral_messages(messages) do
    messages
    |> Enum.map_join("\n", fn msg ->
      role = to_string(msg["role"] || msg[:role])
      content = msg["content"] || msg[:content]
      
      case role do
        "user" -> "[INST] #{content} [/INST]"
        "assistant" -> content
        _ -> content
      end
    end)
  end

  defp generate_response(prompt, model_data, opts) do
    %{serving: serving} = model_data

    if opts.stream do
      # Stream the response
      stream_task = Task.async(fn ->
        try do
          # Use the Nx.Serving with conditional compilation
          apply(Nx.Serving, :run, [serving, %{text: prompt}])
          |> Stream.map(fn chunk ->
            {:data, %{"content" => chunk.text}}
          end)
          |> Enum.to_list()
        rescue
          e ->
            Logger.error("Error during generation: #{inspect(e)}")
            [{:error, "Generation failed: #{inspect(e)}"}]
        end
      end)

      {:ok, Task.await(stream_task, :infinity)}
    else
      # Non-streaming response
      try do
        result = apply(Nx.Serving, :run, [serving, %{text: prompt}])
        
        response = %Types.LLMResponse{
          content: result.text,
          usage: nil,  # TODO: Extract token usage if available
          model: opts[:model] || default_model(),
          finish_reason: "stop"
        }
        
        {:ok, response}
      rescue
        e ->
          Logger.error("Error during generation: #{inspect(e)}")
          {:error, "Generation failed: #{inspect(e)}"}
      end
    end
  end

  defp humanize_model_name(model_id) do
    case model_id do
      "microsoft/phi-2" -> "Phi-2 (2.7B)"
      "meta-llama/Llama-2-7b-hf" -> "Llama 2 (7B)"
      "mistralai/Mistral-7B-v0.1" -> "Mistral (7B)"
      "EleutherAI/gpt-neo-1.3B" -> "GPT-Neo (1.3B)"
      "google/flan-t5-base" -> "Flan-T5 Base"
      _ -> model_id
    end
  end

  defp get_context_window(model) do
    case model do
      "meta-llama/Llama-2" <> _ -> 4_096
      "mistralai/Mistral" <> _ -> 8_192
      "microsoft/phi-2" -> 2_048
      "EleutherAI/gpt-neo-1.3B" -> 2_048
      "google/flan-t5-base" -> 512
      _ -> 2_048
    end
  end


  # Conditional compilation helpers

  defp bumblebee_available? do
    Code.ensure_loaded?(Bumblebee)
  end

  defp model_loader_running? do
    case Process.whereis(ExLLM.Local.ModelLoader) do
      nil -> false
      _pid -> true
    end
  end
end