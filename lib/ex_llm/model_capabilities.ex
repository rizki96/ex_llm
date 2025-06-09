defmodule ExLLM.ModelCapabilities do
  @moduledoc """
  Model capability discovery and management for ExLLM.

  This module provides information about what features and capabilities
  each model supports across different providers. It helps users make
  informed decisions about which model to use for their specific needs.

  ## Features

  - Automatic capability detection
  - Provider-specific feature mapping
  - Capability comparison across models
  - Feature availability checking
  - Model recommendation based on requirements

  ## Usage

      # Get capabilities for a specific model
      {:ok, caps} = ExLLM.ModelCapabilities.get_capabilities(:openai, "gpt-4-turbo")
      
      # Check if a model supports a specific feature
      ExLLM.ModelCapabilities.supports?(:anthropic, "claude-3-opus-20240229", :vision)
      
      # Find models that support specific features
      models = ExLLM.ModelCapabilities.find_models_with_features([:function_calling, :streaming])
      
      # Compare models
      comparison = ExLLM.ModelCapabilities.compare_models([
        {:openai, "gpt-4"},
        {:anthropic, "claude-3-sonnet-20240229"}
      ])
  """

  # alias ExLLM.Types

  defmodule Capability do
    @moduledoc """
    Represents a model capability or feature.
    """
    defstruct [
      :feature,
      :supported,
      :details,
      :limitations
    ]

    @type t :: %__MODULE__{
            feature: atom(),
            supported: boolean(),
            details: map() | nil,
            limitations: list(String.t()) | nil
          }
  end

  defmodule ModelInfo do
    @moduledoc """
    Complete information about a model's capabilities.
    """
    defstruct [
      :provider,
      :model_id,
      :display_name,
      :context_window,
      :max_output_tokens,
      :capabilities,
      :pricing,
      :release_date,
      :deprecation_date
    ]

    @type t :: %__MODULE__{
            provider: atom(),
            model_id: String.t(),
            display_name: String.t(),
            context_window: non_neg_integer(),
            max_output_tokens: non_neg_integer() | nil,
            capabilities: map(),
            pricing: map() | nil,
            release_date: Date.t() | nil,
            deprecation_date: Date.t() | nil
          }
  end

  # Core features we track
  @features [
    :streaming,
    :function_calling,
    :vision,
    :audio,
    :code_execution,
    :web_search,
    :file_upload,
    :structured_output,
    :json_mode,
    :system_messages,
    :multi_turn,
    :context_caching,
    :fine_tuning,
    :embeddings,
    :logprobs,
    :token_counting,
    :stop_sequences,
    :temperature_control,
    :top_p,
    :presence_penalty,
    :frequency_penalty
  ]

  # Model capability database - we'll build this at runtime from YAML files
  defp model_capabilities do
    # Get all providers that have YAML config files
    providers = [
      :openai,
      :anthropic,
      :gemini,
      :groq,
      :ollama,
      :openrouter,
      :mock,
      :bumblebee,
      :bedrock,
      :mistral,
      :cohere,
      :perplexity,
      :deepseek,
      :together_ai,
      :anyscale,
      :replicate
    ]

    # Build the capabilities map from YAML files
    dynamic_capabilities =
      providers
      |> Enum.flat_map(fn provider ->
        models = ExLLM.ModelConfig.get_all_models(provider)

        Enum.map(models, fn {model_id, config} ->
          key = "#{provider}:#{model_id}"

          # Convert capabilities list to Capability structs
          capabilities =
            (Map.get(config, :capabilities, []) || [])
            |> Enum.map(fn
              cap when is_atom(cap) ->
                {cap, %Capability{feature: cap, supported: true}}

              cap when is_binary(cap) ->
                # Handle string capabilities from YAML safely
                atom_cap = normalize_capability_string(cap)

                if atom_cap do
                  {atom_cap, %Capability{feature: atom_cap, supported: true}}
                else
                  nil
                end
            end)
            |> Enum.filter(&(&1 != nil))
            |> Map.new()

          # Add default capabilities that most models support
          default_caps = %{
            multi_turn: %Capability{feature: :multi_turn, supported: true},
            temperature_control: %Capability{feature: :temperature_control, supported: true},
            stop_sequences: %Capability{feature: :stop_sequences, supported: true}
          }

          info = %ModelInfo{
            provider: provider,
            model_id: to_string(model_id),
            display_name: to_string(model_id),
            context_window: Map.get(config, :context_window, 4_096),
            max_output_tokens: Map.get(config, :max_output_tokens),
            capabilities: Map.merge(default_caps, capabilities),
            pricing: Map.get(config, :pricing)
          }

          {key, info}
        end)
      end)
      |> Map.new()

    # Merge with hardcoded capabilities for special cases
    Map.merge(dynamic_capabilities, hardcoded_capabilities())
  end

  # Keep some hardcoded entries for models with special capability details
  defp hardcoded_capabilities do
    %{
      "openai:gpt-4-turbo" => %ModelInfo{
        provider: :openai,
        model_id: "gpt-4-turbo",
        display_name: "GPT-4 Turbo",
        context_window: 128_000,
        max_output_tokens: 4_096,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          function_calling: %Capability{
            feature: :function_calling,
            supported: true,
            details: %{parallel_calls: true, json_mode: true}
          },
          vision: %Capability{feature: :vision, supported: true},
          structured_output: %Capability{feature: :structured_output, supported: true},
          json_mode: %Capability{feature: :json_mode, supported: true},
          system_messages: %Capability{feature: :system_messages, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          logprobs: %Capability{feature: :logprobs, supported: true},
          stop_sequences: %Capability{feature: :stop_sequences, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true},
          top_p: %Capability{feature: :top_p, supported: true}
        },
        release_date: ~D[2023-11-06]
      },
      "openai:gpt-4" => %ModelInfo{
        provider: :openai,
        model_id: "gpt-4",
        display_name: "GPT-4",
        context_window: 8_192,
        max_output_tokens: 4_096,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          function_calling: %Capability{feature: :function_calling, supported: true},
          system_messages: %Capability{feature: :system_messages, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          stop_sequences: %Capability{feature: :stop_sequences, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true}
        },
        release_date: ~D[2023-03-14]
      },
      "openai:gpt-3.5-turbo" => %ModelInfo{
        provider: :openai,
        model_id: "gpt-3.5-turbo",
        display_name: "GPT-3.5 Turbo",
        context_window: 4_096,
        max_output_tokens: 4_096,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          function_calling: %Capability{feature: :function_calling, supported: true},
          system_messages: %Capability{feature: :system_messages, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          json_mode: %Capability{feature: :json_mode, supported: true},
          stop_sequences: %Capability{feature: :stop_sequences, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true}
        },
        release_date: ~D[2022-11-30]
      },

      # Anthropic Models
      "anthropic:claude-3-opus-20240229" => %ModelInfo{
        provider: :anthropic,
        model_id: "claude-3-opus-20240229",
        display_name: "Claude 3 Opus",
        context_window: 200_000,
        max_output_tokens: 4_096,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          function_calling: %Capability{
            feature: :function_calling,
            supported: true,
            details: %{tools_api: true}
          },
          vision: %Capability{
            feature: :vision,
            supported: true,
            details: %{formats: ["image/jpeg", "image/png", "image/gif", "image/webp"]}
          },
          system_messages: %Capability{feature: :system_messages, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          stop_sequences: %Capability{feature: :stop_sequences, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true},
          top_p: %Capability{feature: :top_p, supported: true}
        },
        release_date: ~D[2024-02-29]
      },
      "anthropic:claude-3-sonnet-20240229" => %ModelInfo{
        provider: :anthropic,
        model_id: "claude-3-sonnet-20240229",
        display_name: "Claude 3 Sonnet",
        context_window: 200_000,
        max_output_tokens: 4_096,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          function_calling: %Capability{
            feature: :function_calling,
            supported: true,
            details: %{tools_api: true}
          },
          vision: %Capability{feature: :vision, supported: true},
          system_messages: %Capability{feature: :system_messages, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          stop_sequences: %Capability{feature: :stop_sequences, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true}
        },
        release_date: ~D[2024-02-29]
      },
      "anthropic:claude-3-haiku-20240307" => %ModelInfo{
        provider: :anthropic,
        model_id: "claude-3-haiku-20240307",
        display_name: "Claude 3 Haiku",
        context_window: 200_000,
        max_output_tokens: 4_096,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          function_calling: %Capability{
            feature: :function_calling,
            supported: true,
            details: %{tools_api: true}
          },
          vision: %Capability{feature: :vision, supported: true},
          system_messages: %Capability{feature: :system_messages, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          stop_sequences: %Capability{feature: :stop_sequences, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true}
        },
        release_date: ~D[2024-03-07]
      },
      "anthropic:claude-3-5-sonnet-20241022" => %ModelInfo{
        provider: :anthropic,
        model_id: "claude-3-5-sonnet-20241022",
        display_name: "Claude 3.5 Sonnet",
        context_window: 200_000,
        max_output_tokens: 8_192,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          function_calling: %Capability{
            feature: :function_calling,
            supported: true,
            details: %{tools_api: true, computer_use: true}
          },
          vision: %Capability{feature: :vision, supported: true},
          system_messages: %Capability{feature: :system_messages, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          stop_sequences: %Capability{feature: :stop_sequences, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true},
          context_caching: %Capability{feature: :context_caching, supported: true}
        },
        release_date: ~D[2024-10-22]
      },

      # Google Gemini Models
      "gemini:gemini-pro" => %ModelInfo{
        provider: :gemini,
        model_id: "gemini-pro",
        display_name: "Gemini Pro",
        context_window: 30_720,
        max_output_tokens: 2_048,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          function_calling: %Capability{feature: :function_calling, supported: true},
          system_messages: %Capability{feature: :system_messages, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          stop_sequences: %Capability{feature: :stop_sequences, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true},
          top_p: %Capability{feature: :top_p, supported: true}
        },
        release_date: ~D[2023-12-06]
      },
      "gemini:gemini-pro-vision" => %ModelInfo{
        provider: :gemini,
        model_id: "gemini-pro-vision",
        display_name: "Gemini Pro Vision",
        context_window: 12_288,
        max_output_tokens: 4_096,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          vision: %Capability{
            feature: :vision,
            supported: true,
            details: %{
              formats: ["image/png", "image/jpeg", "image/webp", "image/heic", "image/heif"]
            }
          },
          multi_turn: %Capability{
            feature: :multi_turn,
            supported: false,
            limitations: ["Single turn only for vision"]
          },
          temperature_control: %Capability{feature: :temperature_control, supported: true}
        },
        release_date: ~D[2023-12-06]
      },

      # Bumblebee Models
      "bumblebee:microsoft/phi-2" => %ModelInfo{
        provider: :bumblebee,
        model_id: "microsoft/phi-2",
        display_name: "Phi-2",
        context_window: 2_048,
        max_output_tokens: 2_048,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true},
          stop_sequences: %Capability{feature: :stop_sequences, supported: true}
        }
      },
      "bumblebee:meta-llama/Llama-2-7b-hf" => %ModelInfo{
        provider: :bumblebee,
        model_id: "meta-llama/Llama-2-7b-hf",
        display_name: "Llama 2 7B",
        context_window: 4_096,
        max_output_tokens: 4_096,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true},
          stop_sequences: %Capability{feature: :stop_sequences, supported: true}
        }
      },

      # Mock Model (for testing)
      "mock:mock-model" => %ModelInfo{
        provider: :mock,
        model_id: "mock-model",
        display_name: "Mock Model",
        context_window: 4_096,
        max_output_tokens: 4_096,
        capabilities: %{
          streaming: %Capability{feature: :streaming, supported: true},
          function_calling: %Capability{feature: :function_calling, supported: true},
          vision: %Capability{feature: :vision, supported: true},
          system_messages: %Capability{feature: :system_messages, supported: true},
          multi_turn: %Capability{feature: :multi_turn, supported: true},
          temperature_control: %Capability{feature: :temperature_control, supported: true}
        }
      }
    }
  end

  @doc """
  Get complete capability information for a model.
  """
  @spec get_capabilities(atom(), String.t()) :: {:ok, ModelInfo.t()} | {:error, :not_found}
  def get_capabilities(provider, model_id) do
    key = "#{provider}:#{model_id}"

    case Map.get(model_capabilities(), key) do
      nil ->
        # Try to fetch dynamically
        fetch_dynamic_capabilities(provider, model_id)

      info ->
        {:ok, info}
    end
  end

  @doc """
  Check if a model supports a specific feature.
  """
  @spec supports?(atom(), String.t(), atom()) :: boolean()
  def supports?(provider, model_id, feature) do
    case get_capabilities(provider, model_id) do
      {:ok, info} ->
        case Map.get(info.capabilities, feature) do
          %Capability{supported: true} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  @doc """
  Get detailed information about a specific capability.
  """
  @spec get_capability_details(atom(), String.t(), atom()) ::
          {:ok, Capability.t()} | {:error, :not_found | :not_supported}
  def get_capability_details(provider, model_id, feature) do
    case get_capabilities(provider, model_id) do
      {:ok, info} ->
        case Map.get(info.capabilities, feature) do
          nil -> {:error, :not_supported}
          capability -> {:ok, capability}
        end

      error ->
        error
    end
  end

  @doc """
  Find all models that support specific features.

  This function searches both the hardcoded model database and dynamically
  loads models from YAML configuration files to provide comprehensive results.
  """
  @spec find_models_with_features(list(atom())) :: list({atom(), String.t()})
  def find_models_with_features(required_features) do
    # First get models from the hardcoded database
    hardcoded_models =
      model_capabilities()
      |> Enum.filter(fn {_key, info} ->
        Enum.all?(required_features, fn feature ->
          case Map.get(info.capabilities, feature) do
            %Capability{supported: true} -> true
            _ -> false
          end
        end)
      end)
      |> Enum.map(fn {_key, info} ->
        {info.provider, info.model_id}
      end)

    # Then search through YAML files for additional models
    yaml_models = find_models_in_yaml_configs(required_features)

    # Combine and deduplicate results
    (hardcoded_models ++ yaml_models)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Helper function to search YAML configurations
  defp find_models_in_yaml_configs(required_features) do
    providers = [
      :openai,
      :anthropic,
      :gemini,
      :groq,
      :ollama,
      :openrouter,
      :mock,
      :bumblebee,
      :bedrock,
      :mistral,
      :cohere,
      :perplexity,
      :deepseek,
      :together_ai,
      :anyscale,
      :replicate,
      :azure,
      :cloudflare,
      :databricks,
      :fireworks_ai,
      :meta_llama,
      :sambanova,
      :xai
    ]

    providers
    |> Enum.flat_map(fn provider ->
      try do
        models = ExLLM.ModelConfig.get_all_models(provider)

        models
        |> Enum.filter(fn {_model_id, config} ->
          capabilities = Map.get(config, :capabilities, []) || []

          # Check if all required features are in the capabilities list
          Enum.all?(required_features, fn feature ->
            feature in capabilities or to_string(feature) in Enum.map(capabilities, &to_string/1)
          end)
        end)
        |> Enum.map(fn {model_id, _config} ->
          {provider, to_string(model_id)}
        end)
      rescue
        _ -> []
      end
    end)
  end

  @doc """
  Compare capabilities across multiple models.
  """
  @spec compare_models(list({atom(), String.t()})) :: map()
  def compare_models(model_specs) do
    models =
      Enum.map(model_specs, fn {provider, model_id} ->
        case get_capabilities(provider, model_id) do
          {:ok, info} -> info
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if models == [] do
      %{error: "No valid models found"}
    else
      %{
        models:
          Enum.map(models, fn m ->
            %{
              provider: m.provider,
              model_id: m.model_id,
              display_name: m.display_name,
              context_window: m.context_window,
              max_output_tokens: m.max_output_tokens
            }
          end),
        features: compare_features(models)
      }
    end
  end

  @doc """
  Get all available features.
  """
  @spec list_features() :: list(atom())
  def list_features do
    @features
  end

  @doc """
  Get models grouped by capability.

  This function searches both the hardcoded model database and dynamically
  loads models from YAML configuration files to provide comprehensive results.
  """
  @spec models_by_capability(atom()) :: map()
  def models_by_capability(feature) do
    # First get models from the hardcoded database
    hardcoded_result =
      model_capabilities()
      |> Enum.reduce(%{supported: [], not_supported: []}, fn {_key, info}, acc ->
        case Map.get(info.capabilities, feature) do
          %Capability{supported: true} ->
            %{acc | supported: [{info.provider, info.model_id} | acc.supported]}

          _ ->
            %{acc | not_supported: [{info.provider, info.model_id} | acc.not_supported]}
        end
      end)

    # Then search through YAML files
    yaml_result = get_yaml_models_by_capability(feature)

    # Combine results
    %{
      supported:
        (hardcoded_result.supported ++ yaml_result.supported) |> Enum.uniq() |> Enum.sort(),
      not_supported:
        (hardcoded_result.not_supported ++ yaml_result.not_supported)
        |> Enum.uniq()
        |> Enum.sort()
    }
  end

  # Helper function to get YAML models by capability
  defp get_yaml_models_by_capability(feature) do
    providers = [
      :openai,
      :anthropic,
      :gemini,
      :groq,
      :ollama,
      :openrouter,
      :mock,
      :bumblebee,
      :bedrock,
      :mistral,
      :cohere,
      :perplexity,
      :deepseek,
      :together_ai,
      :anyscale,
      :replicate,
      :azure,
      :cloudflare,
      :databricks,
      :fireworks_ai,
      :meta_llama,
      :sambanova,
      :xai
    ]

    providers
    |> Enum.reduce(%{supported: [], not_supported: []}, fn provider, acc ->
      try do
        models = ExLLM.ModelConfig.get_all_models(provider)

        Enum.reduce(models, acc, fn {model_id, config}, inner_acc ->
          capabilities = Map.get(config, :capabilities, []) || []

          if feature in capabilities or to_string(feature) in Enum.map(capabilities, &to_string/1) do
            %{inner_acc | supported: [{provider, to_string(model_id)} | inner_acc.supported]}
          else
            %{
              inner_acc
              | not_supported: [{provider, to_string(model_id)} | inner_acc.not_supported]
            }
          end
        end)
      rescue
        _ -> acc
      end
    end)
  end

  @doc """
  Get recommended models based on requirements.
  """
  @spec recommend_models(keyword()) :: list({atom(), String.t(), map()})
  def recommend_models(requirements) do
    required_features = Keyword.get(requirements, :features, [])
    min_context = Keyword.get(requirements, :min_context_window, 0)
    max_cost = Keyword.get(requirements, :max_cost_per_1k_tokens, :infinity)

    model_capabilities()
    |> Enum.filter(fn {_key, info} ->
      # Check required features
      has_features =
        Enum.all?(required_features, fn feature ->
          case Map.get(info.capabilities, feature) do
            %Capability{supported: true} -> true
            _ -> false
          end
        end)

      # Check context window
      has_context = info.context_window >= min_context

      # Check cost constraint
      within_cost_limit = check_cost_limit(info, max_cost)

      # Apply filters
      has_features and has_context and within_cost_limit
    end)
    |> Enum.map(fn {_key, info} ->
      # Calculate score based on preferences
      score = calculate_recommendation_score(info, requirements)
      {info.provider, info.model_id, %{score: score, info: info}}
    end)
    |> Enum.sort_by(fn {_, _, %{score: score}} -> score end, :desc)
    |> Enum.take(Keyword.get(requirements, :limit, 5))
  end

  # Private functions

  defp fetch_dynamic_capabilities(_provider, _model_id) do
    # This could be extended to fetch capabilities from the provider
    # For now, return not found
    {:error, :not_found}
  end

  defp compare_features(models) do
    @features
    |> Enum.map(fn feature ->
      support =
        Enum.map(models, fn model ->
          case Map.get(model.capabilities, feature) do
            %Capability{supported: true} = cap ->
              %{supported: true, details: cap.details, limitations: cap.limitations}

            _ ->
              %{supported: false}
          end
        end)

      {feature, support}
    end)
    |> Enum.into(%{})
  end

  defp check_cost_limit(_info, :infinity), do: true

  defp check_cost_limit(info, max_cost) do
    case info.pricing do
      %{input_cost_per_token: input_cost, output_cost_per_token: output_cost}
      when is_number(input_cost) and is_number(output_cost) ->
        # Calculate cost per 1k tokens (assuming equal input/output ratio for simplicity)
        avg_cost_per_1k = (input_cost + output_cost) * 500
        avg_cost_per_1k <= max_cost

      # If no pricing data available, allow it (don't filter out)
      _ ->
        true
    end
  end

  defp calculate_recommendation_score(model_info, requirements) do
    score = 100.0

    # Prefer local models if requested
    score =
      if Keyword.get(requirements, :prefer_local, false) do
        if model_info.provider == :bumblebee, do: score + 50, else: score
      else
        score
      end

    # Prefer larger context windows
    context_bonus = :math.log(model_info.context_window) * 2
    score = score + context_bonus

    # Penalize deprecated models
    score =
      if model_info.deprecation_date &&
           Date.compare(Date.utc_today(), model_info.deprecation_date) == :gt do
        score - 50
      else
        score
      end

    # Bonus for more capabilities
    capability_count =
      model_info.capabilities
      |> Enum.count(fn {_k, v} -> v.supported end)

    score = score + capability_count * 2

    score
  end

  @doc """
  Get model information for a specific provider and model.

  ## Parameters
  - `provider` - Provider atom (e.g., :openai, :anthropic)
  - `model` - Model identifier

  ## Returns
  - `{:ok, model_info}` on success
  - `{:error, :not_found}` if model not found

  ## Examples

      {:ok, info} = ExLLM.ModelCapabilities.get_model_info(:openai, "gpt-4o")
  """
  @spec get_model_info(atom(), String.t()) :: {:ok, ModelInfo.t()} | {:error, :not_found}
  def get_model_info(provider, model) do
    # Get the model database
    db = model_capabilities()

    # First try with provider prefix
    key = "#{provider}:#{model}"

    case Map.get(db, key) do
      nil ->
        # Try without provider prefix (some models might be stored without it)
        case Map.get(db, model) do
          nil -> {:error, :not_found}
          info -> {:ok, info}
        end

      info ->
        {:ok, info}
    end
  end

  # Helper to safely convert capability strings to atoms
  defp normalize_capability_string(cap) when is_binary(cap) do
    case cap do
      "streaming" -> :streaming
      "function_calling" -> :function_calling
      "vision" -> :vision
      "audio" -> :audio
      "embeddings" -> :embeddings
      "multi_turn" -> :multi_turn
      "system_messages" -> :system_messages
      "temperature_control" -> :temperature_control
      "stop_sequences" -> :stop_sequences
      "tools" -> :tools
      "tool_choice" -> :tool_choice
      "parallel_tool_calls" -> :parallel_tool_calls
      "response_format" -> :response_format
      "json_mode" -> :json_mode
      "structured_output" -> :structured_output
      "logprobs" -> :logprobs
      "reasoning" -> :reasoning
      "computer_use" -> :computer_use
      _ -> nil
    end
  end
end
