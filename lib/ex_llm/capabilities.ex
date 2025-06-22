defmodule ExLLM.Capabilities do
  @moduledoc """
  Provider capability detection system for ExLLM.

  This module provides a centralized registry of what capabilities each provider
  supports, allowing tests and application code to gracefully handle feature
  availability differences between providers.
  """

  @capabilities %{
    # Core providers with full feature sets
    :anthropic => [
      :chat,
      :cost_tracking,
      :function_calling,
      :json_mode,
      :list_models,
      :streaming,
      :system_prompt,
      :temperature,
      :vision
    ],
    :openai => [
      :chat,
      :cost_tracking,
      :embeddings,
      :function_calling,
      :json_mode,
      :list_models,
      :streaming,
      :system_prompt,
      :temperature,
      :vision
    ],
    :gemini => [
      :chat,
      :cost_tracking,
      :embeddings,
      :function_calling,
      :json_mode,
      :list_models,
      :streaming,
      :system_prompt,
      :temperature,
      :vision
    ],

    # Fast inference providers
    :groq => [
      :chat,
      :cost_tracking,
      :function_calling,
      :json_mode,
      :list_models,
      :streaming,
      :system_prompt,
      :temperature
    ],
    :xai => [
      :chat,
      :cost_tracking,
      :function_calling,
      :list_models,
      :streaming,
      :system_prompt,
      :temperature
    ],

    # Specialized providers
    :openrouter => [
      :chat,
      :cost_tracking,
      :function_calling,
      :json_mode,
      :list_models,
      :streaming,
      :system_prompt,
      :temperature,
      :vision
    ],
    :mistral => [
      :chat,
      :cost_tracking,
      :function_calling,
      :json_mode,
      :list_models,
      :streaming,
      :system_prompt,
      :temperature
    ],
    :perplexity => [
      :chat,
      :cost_tracking,
      :list_models,
      :streaming,
      :system_prompt,
      :temperature
    ],

    # Local providers
    :ollama => [:chat, :embeddings, :list_models, :streaming, :system_prompt, :temperature],
    :lmstudio => [:chat, :list_models, :streaming, :system_prompt, :temperature],
    :bumblebee => [:chat, :embeddings, :system_prompt, :temperature],

    # Testing provider
    :mock => [
      :chat,
      :cost_tracking,
      :embeddings,
      :function_calling,
      :json_mode,
      :list_models,
      :streaming,
      :system_prompt,
      :temperature,
      :vision
    ]
  }

  @doc """
  Check if a provider supports a specific capability.

  ## Examples

      iex> ExLLM.Capabilities.supports?(:anthropic, :vision)
      true
      
      iex> ExLLM.Capabilities.supports?(:ollama, :vision)
      false
  """
  def supports?(provider, capability) when is_atom(provider) and is_atom(capability) do
    provider_capabilities = Map.get(@capabilities, provider, [])
    capability in provider_capabilities
  end

  @doc """
  Get all capabilities supported by a provider.

  ## Examples

      iex> ExLLM.Capabilities.get_capabilities(:anthropic)
      [:chat, :cost_tracking, :function_calling, :json_mode, :list_models, :streaming, :system_prompt, :temperature, :vision]
  """
  def get_capabilities(provider) when is_atom(provider) do
    Map.get(@capabilities, provider, [])
  end

  @doc """
  Get all providers that support a specific capability.

  ## Examples

      iex> ExLLM.Capabilities.providers_with_capability(:vision)
      [:anthropic, :gemini, :mock, :openai, :openrouter]
  """
  def providers_with_capability(capability) when is_atom(capability) do
    @capabilities
    |> Enum.filter(fn {_provider, capabilities} -> capability in capabilities end)
    |> Enum.map(fn {provider, _capabilities} -> provider end)
    |> Enum.sort()
  end

  @doc """
  Check if provider is configured and supports capability.
  Useful for test gating.
  """
  def configured_and_supports?(provider, capability) do
    ExLLM.configured?(provider) and supports?(provider, capability)
  end

  @doc """
  Get all supported providers.
  """
  def supported_providers do
    Map.keys(@capabilities) |> Enum.sort()
  end

  @doc """
  Get all supported capabilities.
  """
  def supported_capabilities do
    @capabilities
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end
end
