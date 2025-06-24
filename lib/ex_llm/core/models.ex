defmodule ExLLM.Core.Models do
  @moduledoc """
  Model discovery and management across LLM providers.

  This module provides unified access to model information, configuration,
  and discovery across all ExLLM providers.
  """

  alias ExLLM.Infrastructure.Config.{ModelConfig, ProviderCapabilities}

  @doc """
  List all available models for all providers.

  Returns a list of model information including provider, model ID, and capabilities.

  ## Examples

      iex> ExLLM.Core.Models.list_all()
      {:ok, [
        %{provider: :anthropic, id: "claude-3-5-sonnet-20241022", ...},
        %{provider: :openai, id: "gpt-4-turbo", ...},
        ...
      ]}
      
  """
  @spec list_all() :: {:ok, [map()]} | {:error, term()}
  def list_all do
    providers = ProviderCapabilities.list_providers()

    models =
      providers
      |> Enum.flat_map(fn provider ->
        case list_for_provider(provider) do
          {:ok, models} ->
            Enum.map(models, &Map.put(&1, :provider, provider))

          {:error, _} ->
            []
        end
      end)

    {:ok, models}
  end

  @doc """
  List models for a specific provider.

  ## Examples

      iex> ExLLM.Core.Models.list_for_provider(:anthropic)
      {:ok, [
        %{id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", ...},
        %{id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", ...}
      ]}
      
  """
  @spec list_for_provider(atom()) :: {:ok, [map()]} | {:error, term()}
  def list_for_provider(provider) do
    models_map = ModelConfig.get_all_models(provider)

    if map_size(models_map) == 0 do
      {:error, :no_models_found}
    else
      formatted_models =
        models_map
        |> Enum.map(fn {model_id, model} ->
          %{
            id: model_id,
            name: Map.get(model, :name, model_id),
            description: Map.get(model, :description),
            context_window: Map.get(model, :context_window),
            max_output_tokens: Map.get(model, :max_output_tokens),
            pricing: Map.get(model, :pricing),
            capabilities: Map.get(model, :capabilities, [])
          }
        end)

      {:ok, formatted_models}
    end
  end

  @doc """
  Get detailed information about a specific model.

  ## Examples

      iex> ExLLM.Core.Models.get_info(:anthropic, "claude-3-5-sonnet-20241022")
      {:ok, %{
        id: "claude-3-5-sonnet-20241022",
        provider: :anthropic,
        name: "Claude 3.5 Sonnet",
        context_window: 200_000,
        max_output_tokens: 4_096,
        capabilities: [:streaming, :vision, :function_calling],
        pricing: %{input: 3.0, output: 15.0}
      }}
      
  """
  @spec get_info(atom(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_info(provider, model_id) do
    case ModelConfig.get_model_config(provider, model_id) do
      nil ->
        {:error, :model_not_found}

      model_map ->
        # Handle both atom and string keys in model configuration
        {:ok,
         %{
           id: get_field(model_map, [:id, "id"]) || model_id,
           provider: provider,
           name:
             get_field(model_map, [:name, "name"]) || get_field(model_map, [:id, "id"]) ||
               model_id,
           description: get_field(model_map, [:description, "description"]),
           context_window: get_field(model_map, [:context_window, "context_window"]),
           max_output_tokens: get_field(model_map, [:max_output_tokens, "max_output_tokens"]),
           pricing: get_field(model_map, [:pricing, "pricing"]),
           capabilities: get_field(model_map, [:capabilities, "capabilities"]) || [],
           metadata: get_field(model_map, [:metadata, "metadata"]) || %{}
         }}
    end
  end

  # Helper function to get field from map with multiple possible keys
  defp get_field(map, keys) when is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  @doc """
  Find models by capability.

  Returns models that support all the specified capabilities.

  ## Examples

      iex> ExLLM.Core.Models.find_by_capabilities([:vision, :streaming])
      {:ok, [
        %{provider: :anthropic, id: "claude-3-5-sonnet-20241022", ...},
        %{provider: :openai, id: "gpt-4-turbo", ...}
      ]}
      
  """
  @spec find_by_capabilities([atom()]) :: {:ok, [map()]} | {:error, term()}
  def find_by_capabilities(capabilities) when is_list(capabilities) do
    {:ok, models} = list_all()

    matching_models =
      models
      |> Enum.filter(fn model ->
        model_capabilities = model.capabilities || []
        Enum.all?(capabilities, fn cap -> cap in model_capabilities end)
      end)

    {:ok, matching_models}
  end

  @doc """
  Find models by minimum context window size.

  ## Examples

      iex> ExLLM.Core.Models.find_by_min_context(100_000)
      {:ok, [%{provider: :anthropic, id: "claude-3-5-sonnet-20241022", context_window: 200_000}, ...]}
      
  """
  @spec find_by_min_context(pos_integer()) :: {:ok, [map()]} | {:error, term()}
  def find_by_min_context(min_context) do
    {:ok, models} = list_all()

    matching_models =
      models
      |> Enum.filter(fn model ->
        case model.context_window do
          nil -> false
          window when is_integer(window) -> window >= min_context
          _ -> false
        end
      end)
      |> Enum.sort_by(& &1.context_window, :desc)

    {:ok, matching_models}
  end

  @doc """
  Find models within a cost range (per 1M tokens).

  ## Examples

      iex> ExLLM.Core.Models.find_by_cost_range(input: {0, 5.0}, output: {0, 20.0})
      {:ok, [%{provider: :openai, id: "gpt-3.5-turbo", pricing: %{input: 0.5, output: 1.5}}, ...]}
      
  """
  @spec find_by_cost_range(keyword()) :: {:ok, [map()]} | {:error, term()}
  def find_by_cost_range(cost_filters) do
    {:ok, models} = list_all()

    matching_models =
      models
      |> Enum.filter(fn model ->
        case model.pricing do
          nil -> false
          pricing -> matches_cost_criteria?(pricing, cost_filters)
        end
      end)
      |> Enum.sort_by(fn model ->
        case model.pricing do
          %{input: input} when is_number(input) -> input
          _ -> 0
        end
      end)

    {:ok, matching_models}
  end

  @doc """
  Get the default model for a provider.

  ## Examples

      iex> ExLLM.Core.Models.get_default(:anthropic)
      {:ok, "claude-3-5-sonnet-latest"}
      
  """
  @spec get_default(atom()) :: {:ok, String.t()} | {:error, term()}
  def get_default(provider) do
    case ModelConfig.get_default_model(provider) do
      {:ok, model_id} -> {:ok, model_id}
      {:error, _} = error -> error
    end
  end

  @doc """
  Compare models across different providers.

  Returns a comparison matrix showing capabilities, pricing, and context windows.

  ## Examples

      iex> ExLLM.Core.Models.compare(["claude-3-5-sonnet-20241022", "gpt-4-turbo", "gemini-1.5-pro"])
      {:ok, %{
        models: [...],
        capabilities: %{vision: [...], streaming: [...]},
        pricing: %{...},
        context_windows: %{...}
      }}
      
  """
  @spec compare([String.t()]) :: {:ok, map()} | {:error, term()}
  def compare(model_ids) when is_list(model_ids) do
    models_info =
      model_ids
      |> Enum.map(fn model_id ->
        # Find which provider has this model
        case find_model_provider(model_id) do
          {:ok, provider} ->
            case get_info(provider, model_id) do
              {:ok, info} -> {model_id, info}
              {:error, _} -> {model_id, nil}
            end

          {:error, _} ->
            {model_id, nil}
        end
      end)
      |> Enum.filter(fn {_id, info} -> info != nil end)
      |> Map.new()

    if Enum.empty?(models_info) do
      {:error, :no_valid_models}
    else
      comparison = build_comparison_matrix(models_info)
      {:ok, comparison}
    end
  end

  # Private helper functions

  defp matches_cost_criteria?(pricing, filters) do
    Enum.all?(filters, fn {cost_type, {min, max}} ->
      case Map.get(pricing, cost_type) do
        nil -> false
        cost when is_number(cost) -> cost >= min and cost <= max
        _ -> false
      end
    end)
  end

  defp find_model_provider(model_id) do
    providers = ProviderCapabilities.list_providers()

    Enum.find_value(providers, {:error, :not_found}, fn provider ->
      case ModelConfig.get_model_config(provider, model_id) do
        {:ok, _} -> {:ok, provider}
        {:error, _} -> nil
      end
    end)
  end

  defp build_comparison_matrix(models_info) do
    all_capabilities =
      models_info
      |> Map.values()
      |> Enum.flat_map(& &1.capabilities)
      |> Enum.uniq()
      |> Enum.sort()

    capability_matrix =
      all_capabilities
      |> Enum.map(fn capability ->
        supporting_models =
          models_info
          |> Enum.filter(fn {_id, info} -> capability in info.capabilities end)
          |> Enum.map(fn {id, _info} -> id end)

        {capability, supporting_models}
      end)
      |> Map.new()

    pricing_comparison =
      models_info
      |> Enum.map(fn {id, info} -> {id, info.pricing} end)
      |> Map.new()

    context_comparison =
      models_info
      |> Enum.map(fn {id, info} -> {id, info.context_window} end)
      |> Map.new()

    %{
      models: Map.values(models_info),
      capabilities: capability_matrix,
      pricing: pricing_comparison,
      context_windows: context_comparison,
      summary: %{
        total_models: map_size(models_info),
        providers: models_info |> Map.values() |> Enum.map(& &1.provider) |> Enum.uniq(),
        capabilities_count: length(all_capabilities)
      }
    }
  end
end
