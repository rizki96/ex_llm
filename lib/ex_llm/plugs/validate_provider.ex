defmodule ExLLM.Plugs.ValidateProvider do
  @moduledoc """
  Validates that the requested provider is supported.

  This plug should typically be the first in any pipeline to ensure we're
  working with a valid provider before proceeding with other operations.

  ## Options

    * `:providers` - List of allowed providers (defaults to all supported providers)
    
  ## Examples

      # Default - validates against all supported providers
      plug ExLLM.Plugs.ValidateProvider
      
      # Restrict to specific providers
      plug ExLLM.Plugs.ValidateProvider, providers: [:openai, :anthropic]
  """

  use ExLLM.Plug

  @supported_providers [
    :anthropic,
    :openai,
    :gemini,
    :groq,
    :mistral,
    :openrouter,
    :perplexity,
    :ollama,
    :lmstudio,
    :bumblebee,
    :xai,
    :bedrock,
    :mock
  ]

  @impl true
  def init(opts) do
    providers = opts[:providers] || @supported_providers

    unless is_list(providers) and Enum.all?(providers, &is_atom/1) do
      raise ArgumentError, "providers must be a list of atoms"
    end

    %{providers: MapSet.new(providers)}
  end

  @impl true
  def call(%Request{provider: provider} = request, %{providers: allowed_providers}) do
    if MapSet.member?(allowed_providers, provider) do
      request
      |> Request.assign(:provider_validated, true)
      |> Request.put_metadata(:provider, provider)
    else
      error = %{
        plug: __MODULE__,
        error: :unsupported_provider,
        message:
          "Provider #{inspect(provider)} is not supported. " <>
            "Supported providers: #{format_providers(allowed_providers)}",
        provider: provider,
        allowed_providers: MapSet.to_list(allowed_providers)
      }

      request
      |> Request.halt_with_error(error)
    end
  end

  defp format_providers(providers) do
    providers
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(&inspect/1)
    |> Enum.join(", ")
  end

  @doc """
  Returns the list of all supported providers.

  ## Examples

      iex> ExLLM.Plugs.ValidateProvider.supported_providers()
      [:anthropic, :openai, :gemini, ...]
  """
  @spec supported_providers() :: [atom()]
  def supported_providers, do: @supported_providers

  @doc """
  Checks if a provider is supported.

  ## Examples

      iex> ExLLM.Plugs.ValidateProvider.supported?(:openai)
      true
      
      iex> ExLLM.Plugs.ValidateProvider.supported?(:unknown)
      false
  """
  @spec supported?(atom()) :: boolean()
  def supported?(provider) when is_atom(provider) do
    provider in @supported_providers
  end
end
