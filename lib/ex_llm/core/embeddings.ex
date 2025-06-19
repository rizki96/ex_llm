defmodule ExLLM.Core.Embeddings do
  @moduledoc """
  Text embeddings generation across LLM providers.

  This module provides unified access to embedding generation capabilities
  across providers that support text vectorization.
  """

  alias ExLLM.Infrastructure.Config.{ModelConfig, ProviderCapabilities}

  @type embedding_input :: String.t() | [String.t()]
  @type embedding_options :: keyword()
  @type embedding_response :: %{
          embeddings: [[float()]],
          usage: map(),
          cost: map(),
          metadata: map()
        }

  @doc """
  Generate embeddings for text input(s).

  ## Examples

      # Single text
      {:ok, response} = ExLLM.Core.Embeddings.generate(:openai, "Hello world")
      
      # Multiple texts
      {:ok, response} = ExLLM.Core.Embeddings.generate(:openai, ["Hello", "World"])
      
      # With options
      {:ok, response} = ExLLM.Core.Embeddings.generate(:openai, "Hello", 
        model: "text-embedding-3-large",
        dimensions: 512
      )
      
  """
  @spec generate(atom(), embedding_input(), embedding_options()) ::
          {:ok, embedding_response()} | {:error, term()}
  def generate(provider, input, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} when is_atom(adapter) and not is_nil(adapter) ->
        try do
          # Use apply to avoid compile-time warnings about nil module
          apply(adapter, :embeddings, [input, options])
        rescue
          UndefinedFunctionError ->
            {:error, {:embeddings_not_supported, provider}}
        end

      {:error, _} = error ->
        error

      _ ->
        {:error, {:invalid_adapter, provider}}
    end
  end

  @doc """
  List available embedding models for a provider.

  ## Examples

      {:ok, models} = ExLLM.Core.Embeddings.list_models(:openai)
      # => ["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"]
      
  """
  @spec list_models(atom()) :: {:ok, [String.t()]} | {:error, term()}
  def list_models(provider) do
    # Use the provider's list_models function to get normalized model data
    case get_adapter(provider) do
      {:ok, adapter} when is_atom(adapter) and not is_nil(adapter) ->
        try do
          case apply(adapter, :list_models, []) do
            {:ok, models} ->
              # Filter models that have :embeddings capability
              embedding_models =
                models
                |> Enum.filter(fn model ->
                  case model.capabilities do
                    %{features: features} when is_list(features) ->
                      :embeddings in features
                    _ ->
                      false
                  end
                end)
                |> Enum.map(fn model -> model.id end)

              if length(embedding_models) > 0 do
                {:ok, embedding_models}
              else
                {:ok, []}
              end

            {:error, _} = error ->
              error
          end
        rescue
          UndefinedFunctionError ->
            # Fallback to config-based approach for providers without list_models
            fallback_list_models(provider)
        end

      {:error, _} = error ->
        error

      _ ->
        {:error, {:invalid_adapter, provider}}
    end
  end

  # Fallback method for providers that don't implement list_models
  defp fallback_list_models(provider) do
    models_map = ModelConfig.get_all_models(provider)

    if map_size(models_map) == 0 do
      {:error, :no_models_found}
    else
      embedding_models =
        models_map
        |> Enum.filter(fn {_model_id, model} ->
          # Check for embeddings in capabilities list
          has_embeddings_capability = 
            case Map.get(model, :capabilities) do
              nil -> false
              caps when is_list(caps) -> "embeddings" in caps
              _ -> false
            end
          
          # Check for embedding mode (used by OpenAI)
          has_embedding_mode = Map.get(model, :mode) == "embedding"
          
          has_embeddings_capability or has_embedding_mode
        end)
        |> Enum.map(fn {model_id, _model} -> model_id end)

      {:ok, embedding_models}
    end
  end

  @doc """
  Get embedding model information including dimensions and pricing.

  ## Examples

      {:ok, info} = ExLLM.Core.Embeddings.get_model_info(:openai, "text-embedding-3-large")
      # => %{
      #   id: "text-embedding-3-large",
      #   dimensions: 3072,
      #   max_input_tokens: 8191,
      #   pricing: %{input: 0.13}
      # }
      
  """
  @spec get_model_info(atom(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_model_info(provider, model_id) do
    case ModelConfig.get_model_config(provider, model_id) do
      {:ok, model} ->
        info = %{
          id: model.id,
          dimensions: get_model_dimensions(model),
          max_input_tokens: model.max_input_tokens || model.context_window,
          pricing: model.pricing,
          capabilities: model.capabilities || []
        }

        {:ok, info}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Find providers that support embeddings.

  ## Examples

      providers = ExLLM.Core.Embeddings.list_providers()
      # => [:openai, :gemini, :mistral, :ollama]
      
  """
  @spec list_providers() :: [atom()]
  def list_providers do
    ProviderCapabilities.list_providers()
    |> Enum.filter(fn provider ->
      case ProviderCapabilities.get_capabilities(provider) do
        {:ok, capabilities} ->
          :embeddings in (capabilities.features || []) or
            :embeddings in (capabilities.endpoints || [])

        {:error, _} ->
          false
      end
    end)
  end

  @doc """
  Calculate similarity between two embedding vectors.

  Uses cosine similarity by default, but supports other metrics.

  ## Examples

      similarity = ExLLM.Core.Embeddings.similarity(vector1, vector2)
      # => 0.8234
      
      similarity = ExLLM.Core.Embeddings.similarity(vector1, vector2, :euclidean)
      # => 0.1234
      
  """
  @spec similarity([float()], [float()], atom()) :: float()
  def similarity(vector1, vector2, metric \\ :cosine) do
    case metric do
      :cosine -> cosine_similarity(vector1, vector2)
      :euclidean -> euclidean_distance(vector1, vector2)
      :dot_product -> dot_product(vector1, vector2)
      _ -> raise ArgumentError, "Unsupported similarity metric: #{metric}"
    end
  end

  @doc """
  Estimate the cost for embedding generation.

  ## Examples

      {:ok, cost} = ExLLM.Core.Embeddings.estimate_cost(:openai, ["text1", "text2"], 
        model: "text-embedding-3-large"
      )
      # => %{estimated_tokens: 10, cost_usd: 0.0013}
      
  """
  @spec estimate_cost(atom(), embedding_input(), embedding_options()) ::
          {:ok, map()} | {:error, term()}
  def estimate_cost(provider, input, options \\ []) do
    with {:ok, model_info} <- get_embedding_model_info(provider, options),
         estimated_tokens <- estimate_tokens(input),
         {:ok, cost} <- calculate_embedding_cost(provider, estimated_tokens, model_info) do
      {:ok,
       %{
         estimated_tokens: estimated_tokens,
         cost_usd: cost,
         model: model_info.id
       }}
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Batch process multiple embedding requests efficiently.

  ## Examples

      requests = [
        {"Document 1 content", []},
        {"Document 2 content", []},
        {"Document 3 content", [model: "text-embedding-3-small"]}
      ]
      
      {:ok, results} = ExLLM.Core.Embeddings.batch_generate(:openai, requests)
      
  """
  @spec batch_generate(atom(), [{embedding_input(), embedding_options()}]) ::
          {:ok, [embedding_response()]} | {:error, term()}
  def batch_generate(provider, requests) when is_list(requests) do
    results =
      requests
      |> Enum.with_index()
      |> Enum.map(fn {{input, options}, index} ->
        case generate(provider, input, options) do
          {:ok, response} -> {:ok, Map.put(response, :batch_index, index)}
          {:error, error} -> {:error, {index, error}}
        end
      end)

    # Check if any failed
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      successes = Enum.map(results, fn {:ok, result} -> result end)
      {:ok, successes}
    else
      {:error, {:batch_errors, errors}}
    end
  end

  # Private helper functions

  defp get_adapter(provider) do
    case ProviderCapabilities.get_adapter_module(provider) do
      nil -> {:error, {:unsupported_provider, provider}}
      adapter when is_atom(adapter) -> {:ok, adapter}
      _ -> {:error, {:invalid_adapter, provider}}
    end
  end

  defp get_model_dimensions(model) do
    # Try to extract dimensions from model metadata or name
    cond do
      model.metadata && model.metadata["dimensions"] ->
        model.metadata["dimensions"]

      model.description && String.contains?(model.description, "dimensions") ->
        extract_dimensions_from_description(model.description)

      String.contains?(model.id, "3072") ->
        3072

      String.contains?(model.id, "1536") ->
        1536

      String.contains?(model.id, "768") ->
        768

      String.contains?(model.id, "small") ->
        1536

      String.contains?(model.id, "large") ->
        3072

      true ->
        nil
    end
  end

  defp extract_dimensions_from_description(description) do
    case Regex.run(~r/(\d+)\s*dimensions?/i, description) do
      [_, dims] -> String.to_integer(dims)
      _ -> nil
    end
  end

  defp get_embedding_model_info(provider, options) do
    model_id = Keyword.get(options, :model) || get_default_embedding_model(provider)
    get_model_info(provider, model_id)
  end

  defp get_default_embedding_model(provider) do
    case provider do
      :openai -> "text-embedding-3-small"
      :gemini -> "text-embedding-004"
      :mistral -> "mistral-embed"
      _ -> "default"
    end
  end

  defp estimate_tokens(input) when is_binary(input) do
    # Simple estimation: ~4 characters per token
    div(String.length(input), 4) + 1
  end

  defp estimate_tokens(inputs) when is_list(inputs) do
    inputs
    |> Enum.map(&estimate_tokens/1)
    |> Enum.sum()
  end

  defp calculate_embedding_cost(_provider, tokens, model_info) do
    case model_info.pricing do
      %{input: price_per_1m} when is_number(price_per_1m) ->
        cost = tokens / 1_000_000 * price_per_1m
        {:ok, cost}

      _ ->
        {:error, :pricing_not_available}
    end
  end

  defp cosine_similarity(v1, v2) when length(v1) == length(v2) do
    dot_prod = dot_product(v1, v2)
    magnitude1 = :math.sqrt(dot_product(v1, v1))
    magnitude2 = :math.sqrt(dot_product(v2, v2))

    if magnitude1 == 0 or magnitude2 == 0 do
      0.0
    else
      dot_prod / (magnitude1 * magnitude2)
    end
  end

  defp cosine_similarity(_, _), do: raise(ArgumentError, "Vectors must have the same length")

  defp euclidean_distance(v1, v2) when length(v1) == length(v2) do
    v1
    |> Enum.zip(v2)
    |> Enum.map(fn {a, b} -> (a - b) * (a - b) end)
    |> Enum.sum()
    |> :math.sqrt()
  end

  defp euclidean_distance(_, _), do: raise(ArgumentError, "Vectors must have the same length")

  defp dot_product(v1, v2) when length(v1) == length(v2) do
    v1
    |> Enum.zip(v2)
    |> Enum.map(fn {a, b} -> a * b end)
    |> Enum.sum()
  end

  defp dot_product(_, _), do: raise(ArgumentError, "Vectors must have the same length")

  @doc """
  Find similar items based on embeddings.

  ## Examples

      results = ExLLM.Core.Embeddings.find_similar(query_embedding, items, top_k: 5)
  """
  @spec find_similar([float()], list(map()), keyword()) ::
          list(%{item: any(), similarity: float()})
  def find_similar(query_embedding, items, opts \\ []) do
    top_k = Keyword.get(opts, :top_k, 10)
    similarity_metric = Keyword.get(opts, :metric, :cosine)
    threshold = Keyword.get(opts, :threshold, 0.0)

    items
    |> Enum.map(fn
      # Handle tuple format {item, embedding}
      {item, embedding} when is_list(embedding) ->
        sim = similarity(query_embedding, embedding, similarity_metric)
        %{item: item, similarity: sim}

      # Handle map format with embedding key
      %{embedding: embedding} = item_map ->
        sim = similarity(query_embedding, embedding, similarity_metric)
        %{item: item_map, similarity: sim}

      # Handle other map formats - try common keys
      item_map when is_map(item_map) ->
        embedding = Map.get(item_map, :embedding) || Map.get(item_map, "embedding")

        if embedding do
          sim = similarity(query_embedding, embedding, similarity_metric)
          %{item: item_map, similarity: sim}
        else
          raise ArgumentError, "Item must have :embedding key: #{inspect(item_map)}"
        end
    end)
    |> Enum.filter(fn %{similarity: sim} -> sim >= threshold end)
    |> Enum.sort_by(fn %{similarity: sim} -> sim end, :desc)
    |> Enum.take(top_k)
  end

  @doc """
  List models that support embeddings for a provider.

  ## Examples

      {:ok, models} = ExLLM.Core.Embeddings.list_embedding_models(:openai)
  """
  @spec list_embedding_models(atom()) :: {:ok, list(String.t())} | {:error, term()}
  def list_embedding_models(provider) do
    case list_models(provider) do
      {:ok, models} ->
        {:ok, models}

      {:error, :no_models_found} ->
        # If no models found for the provider, this means either:
        # 1. Provider is unknown, or 
        # 2. Provider has no embedding models
        # We need to check if provider exists by checking ModelConfig
        models_map = ModelConfig.get_all_models(provider)

        if map_size(models_map) == 0 do
          # Provider is unknown
          {:error, :no_models_found}
        else
          # Provider exists but has no embedding models
          {:ok, []}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
