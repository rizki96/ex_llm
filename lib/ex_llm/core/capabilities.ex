defmodule ExLLM.Core.Capabilities do
  @moduledoc """
  Unified capability querying with automatic normalization.

  This is the main interface for checking capabilities across providers and models.
  It handles normalization of different capability names used by various providers.

  ## Examples

      # Check if a provider supports a capability
      ExLLM.Core.Capabilities.supports?(:openai, :function_calling)
      # => true
      
      # Works with provider-specific names too
      ExLLM.Core.Capabilities.supports?(:anthropic, :tool_use)  # normalized to :function_calling
      # => true
      
      # Check if a specific model supports a capability
      ExLLM.Core.Capabilities.model_supports?(:openai, "gpt-4o", :vision)
      # => true
      
      # Find all providers that support a capability
      ExLLM.Core.Capabilities.find_providers(:image_generation)
      # => [:openai]
  """

  alias ExLLM.Infrastructure.Config.{ModelCapabilities, ProviderCapabilities}

  # Capability normalization mappings
  # Maps various provider-specific names to our normalized capability names
  @capability_mappings %{
    # Function calling variations
    "tools" => :function_calling,
    "tool_use" => :function_calling,
    "functions" => :function_calling,
    "function_call" => :function_calling,
    "parallel_tool_calls" => :parallel_function_calling,

    # Image generation
    "images" => :image_generation,
    "dalle" => :image_generation,
    "image_gen" => :image_generation,
    "text_to_image" => :image_generation,

    # Speech synthesis
    "tts" => :speech_synthesis,
    "text_to_speech" => :speech_synthesis,
    "audio_generation" => :speech_synthesis,
    "speech_generation" => :speech_synthesis,

    # Speech recognition
    "whisper" => :speech_recognition,
    "stt" => :speech_recognition,
    "speech_to_text" => :speech_recognition,
    "audio_transcription" => :speech_recognition,
    "transcribe" => :speech_recognition,

    # Embeddings
    "embed" => :embeddings,
    "embedding" => :embeddings,
    "text_embedding" => :embeddings,
    "vectorization" => :embeddings,

    # Computer interaction
    "computer_use" => :computer_interaction,
    "desktop_control" => :computer_interaction,
    "screen_control" => :computer_interaction,

    # Vision/image understanding
    "image_understanding" => :vision,
    "visual_understanding" => :vision,
    "image_input" => :vision,
    "multimodal" => :vision,

    # Audio understanding
    "audio_understanding" => :audio_input,
    "audio_analysis" => :audio_input,
    "sound_input" => :audio_input,

    # JSON/structured output
    "json" => :json_mode,
    "json_output" => :json_mode,
    "structured_data" => :structured_outputs,
    "typed_outputs" => :structured_outputs,

    # Context features
    "extended_context" => :long_context,
    "large_context" => :long_context,
    "context_window" => :long_context,

    # Caching features
    "prompt_cache" => :prompt_caching,
    "context_cache" => :context_caching,
    "conversation_cache" => :context_caching,

    # System messages
    "system_prompt" => :system_messages,
    "system_instruction" => :system_messages,

    # Reasoning
    "chain_of_thought" => :reasoning,
    "cot" => :reasoning,
    "deep_thinking" => :reasoning,

    # Code features
    "code_exec" => :code_execution,
    "code_runner" => :code_execution,
    "code_interpreter" => :code_execution,

    # Assistants
    "assistant_api" => :assistants_api,
    "assistants" => :assistants_api,

    # Fine-tuning
    "fine_tune" => :fine_tuning,
    "finetuning" => :fine_tuning,
    "model_training" => :fine_tuning,

    # Grounding/search
    "web_grounding" => :grounding,
    "search_grounding" => :grounding,
    "rag" => :grounding,

    # Streaming
    "stream" => :streaming,
    "sse" => :streaming,
    "server_sent_events" => :streaming
  }

  # Inverse mappings for display purposes
  @display_names %{
    function_calling: "Function Calling",
    image_generation: "Image Generation",
    speech_synthesis: "Speech Synthesis (TTS)",
    speech_recognition: "Speech Recognition (STT)",
    embeddings: "Text Embeddings",
    computer_interaction: "Computer Use",
    vision: "Vision/Image Understanding",
    audio_input: "Audio Understanding",
    json_mode: "JSON Mode",
    structured_outputs: "Structured Outputs",
    long_context: "Extended Context Window",
    prompt_caching: "Prompt Caching",
    context_caching: "Context Caching",
    system_messages: "System Messages",
    reasoning: "Advanced Reasoning",
    code_execution: "Code Execution",
    assistants_api: "Assistants API",
    fine_tuning: "Fine-tuning",
    grounding: "Grounding/Web Search",
    streaming: "Streaming (Server-Sent Events)"
  }

  @doc """
  Check if a provider supports a capability (normalized).

  This checks both provider-level capabilities and model-level capabilities.
  """
  @spec supports?(atom(), atom() | String.t()) :: boolean()
  def supports?(provider, feature) do
    normalized_feature = normalize_capability(feature)

    # First check provider-level support
    provider_supports = ProviderCapabilities.supports?(provider, normalized_feature)

    # If not at provider level, check if any model supports it
    if provider_supports do
      true
    else
      # Also check the original feature name in case it's already normalized
      original_check = ProviderCapabilities.supports?(provider, feature)

      if original_check do
        true
      else
        # Check if any of the provider's models support this feature
        model_supports?(provider, normalized_feature)
      end
    end
  end

  @doc """
  Check if a specific model supports a capability (normalized).
  """
  @spec model_supports?(atom(), String.t(), atom() | String.t()) :: boolean()
  def model_supports?(provider, model_id, feature) do
    normalized_feature = normalize_capability(feature)

    case ModelCapabilities.get_capabilities(provider, model_id) do
      {:ok, model_info} ->
        capabilities = Map.get(model_info.capabilities, normalized_feature)
        !!(capabilities && capabilities.supported)

      _ ->
        false
    end
  end

  @doc """
  Check if any model from a provider supports a capability.
  """
  @spec model_supports?(atom(), atom() | String.t()) :: boolean()
  def model_supports?(provider, feature) do
    normalized_feature = normalize_capability(feature)

    models = ModelCapabilities.find_models_with_features([normalized_feature])
    Enum.any?(models, fn {p, _model} -> p == provider end)
  end

  @doc """
  Find all providers that support a capability (normalized).
  """
  @spec find_providers(atom() | String.t()) :: [atom()]
  def find_providers(feature) do
    normalized_feature = normalize_capability(feature)

    # Get providers that support it at the provider level
    provider_level = ProviderCapabilities.find_providers_with_features([normalized_feature])

    # Get providers that have models supporting it
    model_level =
      ModelCapabilities.find_models_with_features([normalized_feature])
      |> Enum.map(fn {provider, _model} -> provider end)
      |> Enum.uniq()

    # Combine and deduplicate
    (provider_level ++ model_level)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Find all models that support a capability (normalized).
  """
  @spec find_models(atom() | String.t()) :: [{atom(), String.t()}]
  def find_models(feature) do
    normalized_feature = normalize_capability(feature)
    ModelCapabilities.find_models_with_features([normalized_feature])
  end

  @doc """
  Group models by a specific capability.

  Returns a map where the keys are provider names and values are lists
  of models that support the given capability.
  """
  @spec models_by_capability(atom() | String.t()) :: %{atom() => [String.t()]}
  def models_by_capability(capability) do
    normalized_capability = normalize_capability(capability)

    find_models(normalized_capability)
    |> Enum.group_by(fn {provider, _model} -> provider end, fn {_provider, model} -> model end)
  end

  @doc """
  Get normalized capability name.
  """
  @spec normalize_capability(atom() | String.t()) :: atom()
  def normalize_capability(feature) when is_atom(feature) do
    normalize_capability(to_string(feature))
  end

  def normalize_capability(feature) when is_binary(feature) do
    # First check if it's in our mappings
    normalized = Map.get(@capability_mappings, feature)

    if normalized do
      normalized
    else
      # Try with underscores converted to match our atom style
      feature_string =
        feature
        |> String.downcase()
        |> String.replace("-", "_")

      # Check if this string form exists in our mappings
      case Map.get(@capability_mappings, feature_string) do
        nil -> find_normalized_capability(feature_string, feature)
        mapped -> mapped
      end
    end
  end

  @doc """
  Get human-readable name for a capability.
  """
  @spec display_name(atom()) :: String.t()
  def display_name(capability) do
    Map.get(
      @display_names,
      capability,
      to_string(capability) |> String.replace("_", " ") |> String.capitalize()
    )
  end

  @doc """
  List all normalized capability names.
  """
  @spec list_capabilities() :: [atom()]
  def list_capabilities do
    @display_names
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Get detailed capability information for a provider.

  Returns both provider-level and model-level capabilities with normalization applied.
  """
  @spec get_provider_capability_summary(atom()) :: map()
  def get_provider_capability_summary(provider) do
    # Get provider capabilities
    {:ok, provider_info} = ProviderCapabilities.get_capabilities(provider)

    # Normalize provider features
    normalized_features =
      provider_info.features
      |> Enum.map(&normalize_capability/1)
      |> Enum.uniq()

    # Get all models and their capabilities
    # Note: Some providers may not support list_models operation
    models =
      case ExLLM.list_models(provider) do
        {:ok, model_list} -> model_list
        _error -> []
      end

    model_capabilities =
      models
      |> Enum.map(fn model ->
        case ModelCapabilities.get_capabilities(provider, model.id) do
          {:ok, caps} ->
            # Get supported capabilities
            supported =
              caps.capabilities
              |> Enum.filter(fn {_feature, info} -> info.supported end)
              |> Enum.map(fn {feature, _} -> normalize_capability(feature) end)
              |> Enum.uniq()

            {model.id, supported}

          _ ->
            {model.id, []}
        end
      end)
      |> Map.new()

    %{
      provider: provider,
      provider_features: normalized_features,
      endpoints: provider_info.endpoints,
      model_capabilities: model_capabilities,
      all_features: get_all_features(normalized_features, model_capabilities)
    }
  end

  defp get_all_features(provider_features, model_capabilities) do
    model_features =
      model_capabilities
      |> Map.values()
      |> List.flatten()

    (provider_features ++ model_features)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Helper function to find normalized capability
  defp find_normalized_capability(feature_string, _original_feature) do
    feature_atom = String.to_atom(feature_string)

    if feature_atom in Map.keys(@display_names) do
      feature_atom
    else
      nil
    end
  end
end
