defmodule ExLLM.Providers.Bumblebee do
  @moduledoc """
  Bumblebee adapter for on-device LLM inference.

  This adapter enables running language models locally using Bumblebee and EXLA/EMLX backends.
  It supports Apple Silicon (via EMLX), NVIDIA GPUs (via CUDA), and CPU inference.

  ## Configuration

  The Bumblebee adapter doesn't require API keys but may need backend configuration:

      # For Apple Silicon (automatic detection)
      {:ok, response} = ExLLM.chat(:bumblebee, messages)
      
      # With specific model
      {:ok, response} = ExLLM.chat(:bumblebee, messages, model: "microsoft/phi-2")

  ## Available Models

  - `HuggingFaceTB/SmolLM2-1.7B-Instruct` - SmolLM2 (1.7B) - Default
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

  @behaviour ExLLM.Provider

  alias ExLLM.{Infrastructure.Logger, Types}
  alias ExLLM.Providers.Bumblebee.ModelLoader

  @available_models [
    "HuggingFaceTB/SmolLM2-1.7B-Instruct",
    "microsoft/phi-2",
    "meta-llama/Llama-2-7b-hf",
    "mistralai/Mistral-7B-v0.1",
    "EleutherAI/gpt-neo-1.3B",
    "google/flan-t5-base"
  ]

  @model_metadata %{
    "HuggingFaceTB/SmolLM2-1.7B-Instruct" => %{
      name: "SmolLM2 (1.7B)",
      context_window: 2_048,
      description: "HuggingFace's SmolLM2 - efficient 1.7B instruction-tuned model"
    },
    "microsoft/phi-2" => %{
      name: "Phi-2 (2.7B)",
      context_window: 2_048,
      description: "Microsoft's Phi-2 model - efficient 2.7B parameter model"
    },
    "meta-llama/Llama-2-7b-hf" => %{
      name: "Llama 2 (7B)",
      context_window: 4_096,
      description: "Meta's Llama 2 7B model - powerful open source LLM"
    },
    "mistralai/Mistral-7B-v0.1" => %{
      name: "Mistral (7B)",
      context_window: 8_192,
      description: "Mistral AI's 7B model - high performance with sliding window attention"
    },
    "EleutherAI/gpt-neo-1.3B" => %{
      name: "GPT-Neo (1.3B)",
      context_window: 2_048,
      description: "EleutherAI's GPT-Neo 1.3B - lightweight GPT-3 style model"
    },
    "google/flan-t5-base" => %{
      name: "Flan-T5 Base",
      context_window: 512,
      description: "Google's Flan-T5 Base - instruction-tuned encoder-decoder model"
    }
  }

  @impl true
  def chat(messages, opts \\ []) do
    if bumblebee_available?() do
      do_chat(messages, opts)
    else
      {:error,
       "Bumblebee is not available. Please add {:bumblebee, \"~> 0.5\"} to your dependencies."}
    end
  end

  @impl true
  def stream_chat(messages, opts \\ []) do
    if bumblebee_available?() do
      do_stream_chat(messages, opts)
    else
      {:error,
       "Bumblebee is not available. Please add {:bumblebee, \"~> 0.5\"} to your dependencies."}
    end
  end

  @impl true
  def configured?(_opts \\ []) do
    # Check if at least Bumblebee is available and ModelLoader is running
    bumblebee_available?() and model_loader_running?()
  end

  @impl true
  def default_model do
    "HuggingFaceTB/SmolLM2-1.7B-Instruct"
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
    with :ok <- validate_messages(messages),
         {:ok, model} <- validate_model(Keyword.get(opts, :model, default_model())),
         {:ok, validated_opts} <- validate_options(opts) do
      stream = Keyword.get(validated_opts, :stream, false)
      max_tokens = Keyword.get(validated_opts, :max_tokens, 2048)
      temperature = Keyword.get(validated_opts, :temperature, 0.7)

      # Format messages for the model
      prompt = format_messages(messages, model)

      # Get or load the model
      case ModelLoader.load_model(model) do
        {:ok, model_data} ->
          generate_response(prompt, model_data, %{
            model: model,
            stream: stream,
            max_tokens: max_tokens,
            temperature: temperature
          })

        {:error, reason} ->
          {:error, "Failed to load model: #{inspect(reason)}"}
      end
    end
  end

  defp validate_messages([]), do: {:error, "Messages cannot be empty"}

  defp validate_messages(messages) when is_list(messages) do
    if Enum.all?(messages, &valid_message?/1) do
      :ok
    else
      {:error, "Invalid message format"}
    end
  end

  defp validate_messages(_), do: {:error, "Messages must be a list"}

  defp valid_message?(%{role: role, content: content}) when is_binary(content) do
    role in ["system", "user", "assistant"] or is_atom(role)
  end

  defp valid_message?(%{"role" => role, "content" => content}) when is_binary(content) do
    role in ["system", "user", "assistant"]
  end

  defp valid_message?(_), do: false

  defp validate_model(model) when is_binary(model) do
    # Check against all available models (including cached ones)
    all_available = @available_models ++ discover_cached_models()

    if model in all_available do
      {:ok, model}
    else
      {:error,
       "Model '#{model}' is not available. Available models: #{Enum.join(all_available, ", ")}"}
    end
  end

  defp validate_model(_), do: {:error, "Model must be a string"}

  defp validate_options(opts) do
    # Validate common options
    validated = opts

    with :ok <- validate_temperature(Keyword.get(opts, :temperature)),
         :ok <- validate_max_tokens(Keyword.get(opts, :max_tokens)) do
      {:ok, validated}
    end
  end

  defp validate_temperature(nil), do: :ok
  defp validate_temperature(temp) when is_number(temp) and temp >= 0 and temp <= 2, do: :ok
  defp validate_temperature(_), do: {:error, "Temperature must be between 0 and 2"}

  defp validate_max_tokens(nil), do: :ok
  defp validate_max_tokens(tokens) when is_integer(tokens) and tokens > 0, do: :ok
  defp validate_max_tokens(_), do: {:error, "Max tokens must be a positive integer"}

  defp do_stream_chat(messages, opts) do
    # For now, use chat with streaming enabled
    opts = Keyword.put(opts, :stream, true)

    case do_chat(messages, opts) do
      {:ok, chunks} when is_list(chunks) ->
        # Convert to stream format expected by ExLLM
        stream =
          Stream.map(chunks, fn chunk ->
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
        stream =
          Stream.iterate(
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

  defp do_list_models(opts) do
    # Get loaded and available models
    loaded = ModelLoader.list_loaded_models()
    acceleration = ModelLoader.get_acceleration_info()

    # Include locally cached models if requested
    all_models =
      if Keyword.get(opts, :include_cached, true) do
        @available_models ++ discover_cached_models()
      else
        @available_models
      end

    # Convert to ExLLM Model format
    models =
      all_models
      |> Enum.uniq()
      |> Enum.map(fn model_id ->
        is_loaded = model_id in loaded
        is_cached = is_model_cached?(model_id)
        metadata = Map.get(@model_metadata, model_id, %{})

        # Determine status
        status =
          cond do
            is_loaded -> "Loaded"
            is_cached -> "Cached"
            true -> "Available"
          end

        # Determine context window - use config or infer from model name
        context_window = Map.get(metadata, :context_window, infer_context_window(model_id))

        %Types.Model{
          id: model_id,
          name: Map.get(metadata, :name, format_model_name(model_id)),
          description:
            "#{Map.get(metadata, :description, generate_model_description(model_id))} - #{status} (#{acceleration.name})",
          context_window: context_window,
          max_output_tokens: context_window,
          # Local models are free
          pricing: %{input: 0.0, output: 0.0},
          capabilities: %{
            features: determine_model_features(model_id)
          }
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
      stream_task =
        Task.async(fn ->
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

        usage = extract_token_usage(result, prompt)

        response = %Types.LLMResponse{
          content: result.text,
          usage: usage,
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

  # Conditional compilation helpers

  defp bumblebee_available? do
    Code.ensure_loaded?(Bumblebee)
  end

  defp model_loader_running? do
    case Process.whereis(ExLLM.Providers.Bumblebee.ModelLoader) do
      nil -> false
      _pid -> true
    end
  end

  defp extract_token_usage(result, prompt) do
    # Try to extract token counts from the result
    # Some local models may provide this information
    input_tokens = estimate_token_count(prompt)
    output_tokens = estimate_token_count(result.text || "")

    cond do
      # If the result contains token usage information, use it
      Map.has_key?(result, :usage) and Map.has_key?(result.usage, :input_tokens) ->
        result.usage

      Map.has_key?(result, :input_tokens) ->
        %{
          input_tokens: result.input_tokens,
          output_tokens: result.output_tokens || output_tokens,
          total_tokens: (result.input_tokens || 0) + (result.output_tokens || output_tokens)
        }

      # Otherwise, provide estimates
      true ->
        %{
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: input_tokens + output_tokens
        }
    end
  end

  defp estimate_token_count(text) when is_binary(text) do
    # Rough estimation: 4 characters per token
    div(String.length(text), 4)
  end

  defp estimate_token_count(_), do: 0

  # Helper functions for cached model discovery

  defp discover_cached_models() do
    hf_cache_home = System.get_env("HF_HOME") || Path.expand("~/.cache/huggingface")
    hf_hub_cache = Path.join(hf_cache_home, "hub")

    if File.exists?(hf_hub_cache) do
      case File.ls(hf_hub_cache) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.starts_with?(&1, "models--"))
          |> Enum.map(fn dir ->
            # Extract model name from directory format "models--org--name"
            dir
            |> String.replace_prefix("models--", "")
            |> String.replace("--", "/")
          end)
          |> Enum.filter(&has_snapshots?/1)

        {:error, _} ->
          []
      end
    else
      []
    end
  end

  defp has_snapshots?(model_name) do
    hf_cache_home = System.get_env("HF_HOME") || Path.expand("~/.cache/huggingface")
    hf_hub_cache = Path.join(hf_cache_home, "hub")

    # Convert model name back to directory format
    dir_name = "models--" <> String.replace(model_name, "/", "--")
    model_path = Path.join(hf_hub_cache, dir_name)
    snapshots_path = Path.join(model_path, "snapshots")

    if File.exists?(snapshots_path) do
      case File.ls(snapshots_path) do
        {:ok, [_ | _]} -> true
        _ -> false
      end
    else
      false
    end
  end

  defp is_model_cached?(model_id) do
    # Check if model is in our available models list or cached
    model_id in @available_models or has_snapshots?(model_id)
  end

  defp format_model_name(model_id) do
    case String.split(model_id, "/") do
      [org, name] -> "#{String.capitalize(org)} #{name}"
      [name] -> String.capitalize(name)
      _ -> model_id
    end
  end

  defp generate_model_description(model_id) do
    cond do
      String.contains?(model_id, "qwen") -> "Qwen model - efficient multilingual LLM"
      String.contains?(model_id, "llama") -> "Llama model - Meta's open source LLM"
      String.contains?(model_id, "mistral") -> "Mistral model - high performance LLM"
      String.contains?(model_id, "phi") -> "Phi model - Microsoft's efficient small LLM"
      String.contains?(model_id, "flux") -> "FLUX model - text-to-image generation"
      String.contains?(model_id, "gpt") -> "GPT-style autoregressive language model"
      String.contains?(model_id, "bert") -> "BERT-style bidirectional encoder"
      String.contains?(model_id, "t5") -> "T5-style encoder-decoder model"
      true -> "Language model for text generation"
    end
  end

  defp infer_context_window(model_id) do
    cond do
      String.contains?(model_id, "32b") or String.contains?(model_id, "32B") -> 32_768
      String.contains?(model_id, "16k") -> 16_384
      String.contains?(model_id, "8k") -> 8_192
      String.contains?(model_id, "4k") -> 4_096
      String.contains?(model_id, "long") -> 32_768
      String.contains?(model_id, "7b") or String.contains?(model_id, "7B") -> 8_192
      String.contains?(model_id, "3b") or String.contains?(model_id, "3B") -> 4_096
      String.contains?(model_id, "1b") or String.contains?(model_id, "1B") -> 2_048
      true -> 2_048
    end
  end

  defp determine_model_features(model_id) do
    features = ["text-generation"]

    features =
      if String.contains?(model_id, "flux") do
        ["text-to-image" | features]
      else
        features
      end

    features =
      if String.contains?(model_id, "omni") do
        ["multimodal" | features]
      else
        features
      end

    features =
      if String.contains?(model_id, "code") do
        ["code-generation" | features]
      else
        features
      end

    features
  end

  @doc """
  Generate embeddings for text using Bumblebee models.

  This function is a placeholder for Bumblebee embeddings support.
  Bumblebee can support embeddings through models like sentence transformers.
  """
  @impl ExLLM.Provider
  @spec embeddings(list(String.t()), keyword()) :: {:error, term()}
  def embeddings(_inputs, _options \\ []) do
    {:error, {:not_implemented, :bumblebee_embeddings}}
  end
end
