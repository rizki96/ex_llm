defmodule ExLLM.Adapters.Shared.ModelUtils do
  @moduledoc """
  Shared utilities for model management across adapters.

  Provides common functionality for:
  - Model name formatting and normalization
  - Description generation based on model characteristics
  - Capability inference from model IDs
  - Model categorization and filtering
  """

  @doc """
  Format a model ID into a human-readable name.

  ## Examples

      iex> ModelUtils.format_model_name("gpt-4-turbo")
      "GPT 4 Turbo"
      
      iex> ModelUtils.format_model_name("claude-3-5-sonnet")
      "Claude 3 5 Sonnet"
  """
  @spec format_model_name(String.t()) :: String.t()
  def format_model_name(model_id) when is_binary(model_id) do
    model_id
    |> String.replace(".", "-")
    |> String.split(["-", "_", "/"])
    |> Enum.map(&capitalize_part/1)
    |> Enum.join(" ")
  end

  defp capitalize_part(part) do
    cond do
      # Keep version numbers as-is
      Regex.match?(~r/^\d+$/, part) -> part
      # Handle common abbreviations
      String.upcase(part) == part and String.length(part) <= 3 -> part
      # Normal capitalization
      true -> String.capitalize(part)
    end
  end

  @doc """
  Generate a model description based on its ID and characteristics.

  ## Examples

      iex> ModelUtils.generate_description("gpt-4-turbo", :openai)
      "OpenAI's GPT-4 Turbo model with improved performance"
  """
  @spec generate_description(String.t(), atom()) :: String.t()
  def generate_description(model_id, provider) do
    base =
      case provider do
        :openai -> "OpenAI's"
        :anthropic -> "Anthropic's"
        :groq -> "Groq-optimized"
        :gemini -> "Google's"
        :meta -> "Meta's"
        _ -> "Provider's"
      end

    cond do
      String.contains?(model_id, "turbo") -> "#{base} optimized model with improved performance"
      String.contains?(model_id, "mini") -> "#{base} lightweight model for fast responses"
      String.contains?(model_id, "vision") -> "#{base} multimodal model with vision capabilities"
      String.contains?(model_id, "instruct") -> "#{base} instruction-following model"
      String.contains?(model_id, "chat") -> "#{base} conversational model"
      true -> "#{base} language model"
    end
  end

  @doc """
  Infer model capabilities from its ID and provider.

  Returns a map with capability flags.
  """
  @spec infer_capabilities(String.t(), atom()) :: map()
  def infer_capabilities(model_id, provider) do
    base_capabilities = %{
      supports_streaming: true,
      supports_functions: provider not in [:local, :ollama],
      supports_vision: false,
      supports_json_mode: provider in [:openai, :groq],
      features: []
    }

    # Add vision support for known vision models
    base_capabilities =
      if contains_any?(model_id, ["vision", "4o", "gemini-pro-vision", "claude-3"]) do
        %{
          base_capabilities
          | supports_vision: true,
            features: [:vision | base_capabilities.features]
        }
      else
        base_capabilities
      end

    # Add function calling to features if supported
    if base_capabilities.supports_functions do
      %{base_capabilities | features: [:function_calling | base_capabilities.features]}
    else
      base_capabilities
    end
  end

  @doc """
  Check if a model ID indicates a chat/conversational model.
  """
  @spec is_chat_model?(String.t()) :: boolean()
  def is_chat_model?(model_id) do
    chat_indicators = ["chat", "turbo", "claude", "gemini", "llama", "mixtral"]
    non_chat_indicators = ["embed", "whisper", "tts", "dall-e", "stable"]

    contains_any?(model_id, chat_indicators) and not contains_any?(model_id, non_chat_indicators)
  end

  @doc """
  Extract model family from model ID.

  ## Examples

      iex> ModelUtils.get_model_family("gpt-4-turbo-preview")
      "gpt-4"
      
      iex> ModelUtils.get_model_family("claude-3-5-sonnet")
      "claude-3"
  """
  @spec get_model_family(String.t()) :: String.t()
  def get_model_family(model_id) do
    cond do
      String.starts_with?(model_id, "gpt-4") -> "gpt-4"
      String.starts_with?(model_id, "gpt-3.5") -> "gpt-3.5"
      String.starts_with?(model_id, "claude-3") -> "claude-3"
      String.starts_with?(model_id, "claude-2") -> "claude-2"
      String.starts_with?(model_id, "llama-3") -> "llama-3"
      String.starts_with?(model_id, "llama-2") -> "llama-2"
      String.starts_with?(model_id, "gemini") -> "gemini"
      String.starts_with?(model_id, "mixtral") -> "mixtral"
      true -> model_id
    end
  end

  # Private helpers

  defp contains_any?(string, substrings) do
    string_lower = String.downcase(string)
    Enum.any?(substrings, &String.contains?(string_lower, &1))
  end
end
