defmodule ExLLM.ProviderCapabilities do
  @moduledoc """
  Provider-level capability tracking for ExLLM.
  
  This module provides information about what features and capabilities
  each provider supports at the API level, independent of specific models.
  It helps users understand what operations are available with each provider.
  
  ## Features
  
  - Provider endpoint discovery (chat, embeddings, images, etc.)
  - Authentication method tracking
  - Cost tracking availability
  - API feature support
  - Provider metadata
  
  ## Usage
  
      # Check if a provider supports a specific feature
      ExLLM.ProviderCapabilities.supports?(:openai, :embeddings)
      
      # Get all capabilities for a provider
      {:ok, caps} = ExLLM.ProviderCapabilities.get_capabilities(:anthropic)
      
      # Find providers that support specific features
      providers = ExLLM.ProviderCapabilities.find_providers_with_features([:embeddings, :streaming])
  """
  
  defmodule ProviderInfo do
    @moduledoc """
    Represents provider-level information and capabilities.
    """
    defstruct [
      :id,
      :name,
      :description,
      :documentation_url,
      :status_url,
      :endpoints,
      :authentication,
      :features,
      :limitations
    ]
    
    @type endpoint :: :chat | :embeddings | :images | :audio | :completions | :fine_tuning | :files
    @type auth_method :: :api_key | :oauth | :aws_signature | :service_account | :bearer_token
    @type feature :: :streaming | :function_calling | :cost_tracking | :usage_tracking | 
                     :dynamic_model_listing | :batch_operations | :file_uploads | 
                     :rate_limiting_headers | :system_messages | :json_mode | 
                     :context_caching | :vision | :audio_input | :audio_output |
                     :web_search | :tool_use | :computer_use
    
    @type t :: %__MODULE__{
      id: atom(),
      name: String.t(),
      description: String.t() | nil,
      documentation_url: String.t() | nil,
      status_url: String.t() | nil,
      endpoints: [endpoint()],
      authentication: [auth_method()],
      features: [feature()],
      limitations: map()
    }
  end
  
  # Provider database - built at runtime to avoid compile-time struct issues
  defp provider_database do
    %{
    # OpenAI
    openai: %__MODULE__.ProviderInfo{
      id: :openai,
      name: "OpenAI",
      description: "OpenAI API with GPT-4, GPT-3.5, DALL-E, and more",
      documentation_url: "https://platform.openai.com/docs",
      status_url: "https://status.openai.com",
      endpoints: [:chat, :embeddings, :images, :audio, :completions, :fine_tuning, :files],
      authentication: [:api_key, :bearer_token],
      features: [
        :streaming, :function_calling, :cost_tracking, :usage_tracking,
        :dynamic_model_listing, :batch_operations, :file_uploads,
        :rate_limiting_headers, :system_messages, :json_mode,
        :vision, :audio_input, :audio_output, :tool_use
      ],
      limitations: %{
        max_file_size: 512 * 1024 * 1024, # 512MB
        max_context_tokens: 128_000,
        rate_limits_vary_by_tier: true
      }
    },
    
    # Anthropic
    anthropic: %__MODULE__.ProviderInfo{
      id: :anthropic,
      name: "Anthropic",
      description: "Claude AI models with advanced reasoning capabilities",
      documentation_url: "https://docs.anthropic.com",
      status_url: "https://status.anthropic.com",
      endpoints: [:chat],
      authentication: [:api_key],
      features: [
        :streaming, :function_calling, :cost_tracking, :usage_tracking,
        :dynamic_model_listing, :rate_limiting_headers, :system_messages,
        :vision, :tool_use, :context_caching, :computer_use
      ],
      limitations: %{
        max_context_tokens: 200_000,
        max_output_tokens: 8_192,
        beta_features: [:computer_use, :context_caching]
      }
    },
    
    # Google Gemini
    gemini: %__MODULE__.ProviderInfo{
      id: :gemini,
      name: "Google Gemini",
      description: "Google's multimodal AI models",
      documentation_url: "https://ai.google.dev/docs",
      endpoints: [:chat],
      authentication: [:api_key, :service_account],
      features: [
        :streaming, :function_calling, :cost_tracking, :usage_tracking,
        :dynamic_model_listing, :system_messages, :vision,
        :tool_use, :json_mode
      ],
      limitations: %{
        max_context_tokens: 1_000_000, # Gemini 1.5 Pro
        requires_google_cloud_for_some_features: true
      }
    },
    
    # Ollama (Local)
    ollama: %__MODULE__.ProviderInfo{
      id: :ollama,
      name: "Ollama",
      description: "Run large language models locally",
      documentation_url: "https://github.com/ollama/ollama",
      endpoints: [:chat, :embeddings],
      authentication: [], # No auth required for local
      features: [
        :streaming, :usage_tracking, :dynamic_model_listing,
        :system_messages
      ],
      limitations: %{
        no_cost_tracking: true,
        performance_depends_on_hardware: true,
        limited_function_calling: true
      }
    },
    
    # AWS Bedrock
    bedrock: %__MODULE__.ProviderInfo{
      id: :bedrock,
      name: "AWS Bedrock",
      description: "Fully managed foundation models from AWS",
      documentation_url: "https://docs.aws.amazon.com/bedrock",
      endpoints: [:chat, :embeddings],
      authentication: [:aws_signature],
      features: [
        :streaming, :function_calling, :cost_tracking, :usage_tracking,
        :system_messages, :vision, :tool_use
      ],
      limitations: %{
        requires_aws_account: true,
        model_access_requires_approval: true,
        region_specific_availability: true
      }
    },
    
    # OpenRouter
    openrouter: %__MODULE__.ProviderInfo{
      id: :openrouter,
      name: "OpenRouter",
      description: "Unified API for multiple LLM providers",
      documentation_url: "https://openrouter.ai/docs",
      endpoints: [:chat],
      authentication: [:api_key],
      features: [
        :streaming, :function_calling, :cost_tracking, :usage_tracking,
        :dynamic_model_listing, :rate_limiting_headers, :system_messages,
        :vision
      ],
      limitations: %{
        features_depend_on_underlying_provider: true,
        pricing_markup: true
      }
    },
    
    # Groq
    groq: %__MODULE__.ProviderInfo{
      id: :groq,
      name: "Groq",
      description: "Ultra-fast LLM inference",
      documentation_url: "https://console.groq.com/docs",
      endpoints: [:chat],
      authentication: [:api_key],
      features: [
        :streaming, :function_calling, :cost_tracking, :usage_tracking,
        :dynamic_model_listing, :rate_limiting_headers, :system_messages,
        :json_mode, :tool_use
      ],
      limitations: %{
        limited_model_selection: true,
        optimized_for_speed_not_size: true
      }
    },
    
    # Local (Bumblebee)
    local: %__MODULE__.ProviderInfo{
      id: :local,
      name: "Local (Bumblebee)",
      description: "Run models locally using Elixir's Bumblebee",
      documentation_url: "https://github.com/elixir-nx/bumblebee",
      endpoints: [:chat, :embeddings],
      authentication: [], # No auth required
      features: [
        :usage_tracking, :system_messages
      ],
      limitations: %{
        no_streaming: true,
        no_cost_tracking: true,
        limited_model_selection: true,
        performance_depends_on_hardware: true,
        requires_model_download: true
      }
    },
    
    # Mock (Testing)
    mock: %__MODULE__.ProviderInfo{
      id: :mock,
      name: "Mock Provider",
      description: "Mock provider for testing",
      endpoints: [:chat, :embeddings],
      authentication: [], # No auth required
      features: [
        :streaming, :function_calling, :cost_tracking, :usage_tracking,
        :system_messages, :vision, :tool_use, :json_mode
      ],
      limitations: %{
        for_testing_only: true
      }
    }
  }
  end
  
  @doc """
  Get capabilities for a specific provider.
  
  ## Parameters
  - `provider` - Provider atom (e.g., :openai, :anthropic)
  
  ## Returns
  - `{:ok, provider_info}` on success
  - `{:error, :not_found}` if provider not found
  
  ## Examples
  
      {:ok, info} = ExLLM.ProviderCapabilities.get_capabilities(:openai)
  """
  @spec get_capabilities(atom()) :: {:ok, ProviderInfo.t()} | {:error, :not_found}
  def get_capabilities(provider) do
    case Map.get(provider_database(), provider) do
      nil -> {:error, :not_found}
      info -> {:ok, info}
    end
  end
  
  @doc """
  Check if a provider supports a specific feature.
  
  ## Parameters
  - `provider` - Provider atom
  - `feature` - Feature to check (endpoint or capability)
  
  ## Returns
  - `true` if supported
  - `false` if not supported or provider not found
  
  ## Examples
  
      ExLLM.ProviderCapabilities.supports?(:openai, :embeddings)
      # => true
      
      ExLLM.ProviderCapabilities.supports?(:ollama, :cost_tracking)
      # => false
  """
  @spec supports?(atom(), atom()) :: boolean()
  def supports?(provider, feature) do
    case get_capabilities(provider) do
      {:ok, info} ->
        feature in info.endpoints || feature in info.features
      {:error, _} ->
        false
    end
  end
  
  @doc """
  Find providers that support all specified features.
  
  ## Parameters
  - `features` - List of required features
  
  ## Returns
  - List of provider atoms that support all features
  
  ## Examples
  
      providers = ExLLM.ProviderCapabilities.find_providers_with_features([:embeddings, :streaming])
      # => [:openai, :groq]
  """
  @spec find_providers_with_features([atom()]) :: [atom()]
  def find_providers_with_features(features) do
    provider_database()
    |> Enum.filter(fn {_provider, info} ->
      Enum.all?(features, fn feature ->
        feature in info.endpoints || feature in info.features
      end)
    end)
    |> Enum.map(fn {provider, _info} -> provider end)
    |> Enum.sort()
  end
  
  @doc """
  Get authentication methods for a provider.
  
  ## Parameters
  - `provider` - Provider atom
  
  ## Returns
  - List of authentication methods or empty list
  
  ## Examples
  
      ExLLM.ProviderCapabilities.get_auth_methods(:openai)
      # => [:api_key, :bearer_token]
  """
  @spec get_auth_methods(atom()) :: [atom()]
  def get_auth_methods(provider) do
    case get_capabilities(provider) do
      {:ok, info} -> info.authentication
      {:error, _} -> []
    end
  end
  
  @doc """
  Get available endpoints for a provider.
  
  ## Parameters
  - `provider` - Provider atom
  
  ## Returns
  - List of available endpoints or empty list
  
  ## Examples
  
      ExLLM.ProviderCapabilities.get_endpoints(:openai)
      # => [:chat, :embeddings, :images, :audio, :completions, :fine_tuning, :files]
  """
  @spec get_endpoints(atom()) :: [atom()]
  def get_endpoints(provider) do
    case get_capabilities(provider) do
      {:ok, info} -> info.endpoints
      {:error, _} -> []
    end
  end
  
  @doc """
  List all known providers.
  
  ## Returns
  - List of provider atoms
  
  ## Examples
  
      ExLLM.ProviderCapabilities.list_providers()
      # => [:anthropic, :bedrock, :gemini, :groq, :local, :mock, :ollama, :openai, :openrouter]
  """
  @spec list_providers() :: [atom()]
  def list_providers do
    Map.keys(provider_database()) |> Enum.sort()
  end
  
  @doc """
  Get provider limitations.
  
  ## Parameters
  - `provider` - Provider atom
  
  ## Returns
  - Map of limitations or empty map
  
  ## Examples
  
      ExLLM.ProviderCapabilities.get_limitations(:ollama)
      # => %{no_cost_tracking: true, performance_depends_on_hardware: true}
  """
  @spec get_limitations(atom()) :: map()
  def get_limitations(provider) do
    case get_capabilities(provider) do
      {:ok, info} -> info.limitations
      {:error, _} -> %{}
    end
  end
  
  @doc """
  Compare capabilities across multiple providers.
  
  ## Parameters
  - `providers` - List of provider atoms to compare
  
  ## Returns
  - Map with comparison data
  
  ## Examples
  
      comparison = ExLLM.ProviderCapabilities.compare_providers([:openai, :anthropic, :ollama])
  """
  @spec compare_providers([atom()]) :: map()
  def compare_providers(providers) do
    provider_infos = 
      providers
      |> Enum.map(fn provider ->
        case get_capabilities(provider) do
          {:ok, info} -> {provider, info}
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()
    
    # Collect all unique features and endpoints
    all_features = 
      provider_infos
      |> Enum.flat_map(fn {_provider, info} -> info.features end)
      |> Enum.uniq()
      |> Enum.sort()
    
    all_endpoints = 
      provider_infos
      |> Enum.flat_map(fn {_provider, info} -> info.endpoints end)
      |> Enum.uniq()
      |> Enum.sort()
    
    %{
      providers: Map.keys(provider_infos),
      features: all_features,
      endpoints: all_endpoints,
      comparison: 
        Map.new(provider_infos, fn {provider, info} ->
          {provider, %{
            features: info.features,
            endpoints: info.endpoints,
            authentication: info.authentication,
            limitations: info.limitations
          }}
        end)
    }
  end
end