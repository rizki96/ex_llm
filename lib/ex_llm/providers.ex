defmodule ExLLM.Providers do
  @moduledoc """
  Registry and configuration for LLM providers.

  This module manages provider registration and their default pipelines.
  Each provider can define multiple pipelines for different operations
  (chat, streaming, embeddings, etc.).
  """

  alias ExLLM.Pipeline
  alias ExLLM.Plugs

  @type pipeline_type :: :chat | :stream | :embeddings | :completion | :list_models | :validate

  @doc """
  Gets the pipeline for a specific provider and operation type.

  ## Examples

      pipeline = ExLLM.Providers.get_pipeline(:openai, :chat)
  """
  @spec get_pipeline(atom(), pipeline_type()) :: Pipeline.pipeline()
  def get_pipeline(provider, type \\ :chat) do
    case type do
      :chat -> get_chat_pipeline(provider)
      :stream -> get_stream_pipeline(provider)
      :embeddings -> get_embeddings_pipeline(provider)
      :list_models -> get_list_models_pipeline(provider)
      :validate -> validation_pipeline()
      _ -> default_chat_pipeline()
    end
  end

  @doc """
  Returns a list of all supported providers.
  """
  @spec supported_providers() :: [atom()]
  def supported_providers do
    [
      :openai,
      :anthropic,
      :gemini,
      :groq,
      :mistral,
      :openrouter,
      :perplexity,
      :xai,
      :ollama,
      :lmstudio,
      :bedrock,
      :bumblebee,
      :mock
    ]
  end

  @doc """
  Checks if a provider is supported.
  """
  @spec supported?(atom()) :: boolean()
  def supported?(provider) when is_atom(provider) do
    provider in supported_providers()
  end

  # Helper functions to reduce complexity of get_pipeline/2
  defp get_chat_pipeline(:openai), do: openai_chat_pipeline()
  defp get_chat_pipeline(:anthropic), do: anthropic_chat_pipeline()
  defp get_chat_pipeline(:gemini), do: gemini_chat_pipeline()
  defp get_chat_pipeline(:groq), do: groq_chat_pipeline()
  defp get_chat_pipeline(:mistral), do: mistral_chat_pipeline()
  defp get_chat_pipeline(:openrouter), do: openrouter_chat_pipeline()
  defp get_chat_pipeline(:xai), do: xai_chat_pipeline()
  defp get_chat_pipeline(:ollama), do: ollama_chat_pipeline()
  defp get_chat_pipeline(:bedrock), do: bedrock_chat_pipeline()
  defp get_chat_pipeline(:bumblebee), do: bumblebee_chat_pipeline()
  defp get_chat_pipeline(:mock), do: mock_chat_pipeline()
  defp get_chat_pipeline(_), do: default_chat_pipeline()

  defp get_stream_pipeline(:openai), do: openai_stream_pipeline()
  defp get_stream_pipeline(:anthropic), do: anthropic_stream_pipeline()
  defp get_stream_pipeline(:gemini), do: gemini_stream_pipeline()
  defp get_stream_pipeline(:groq), do: groq_stream_pipeline()
  defp get_stream_pipeline(:mistral), do: mistral_stream_pipeline()
  defp get_stream_pipeline(:openrouter), do: openrouter_stream_pipeline()
  defp get_stream_pipeline(:perplexity), do: perplexity_stream_pipeline()
  defp get_stream_pipeline(:xai), do: xai_stream_pipeline()
  defp get_stream_pipeline(:ollama), do: ollama_stream_pipeline()
  defp get_stream_pipeline(:lmstudio), do: lmstudio_stream_pipeline()
  defp get_stream_pipeline(:bedrock), do: bedrock_stream_pipeline()
  defp get_stream_pipeline(:bumblebee), do: bumblebee_stream_pipeline()
  defp get_stream_pipeline(:mock), do: mock_stream_pipeline()
  defp get_stream_pipeline(_), do: default_chat_pipeline()

  defp get_embeddings_pipeline(provider) do
    case provider do
      :openai -> openai_embeddings_pipeline()
      :gemini -> gemini_embeddings_pipeline()
      :ollama -> ollama_embeddings_pipeline()
      :mock -> mock_embeddings_pipeline()
      _ -> default_embeddings_pipeline()
    end
  end

  defp get_list_models_pipeline(provider) do
    case provider do
      :openai -> openai_list_models_pipeline()
      :anthropic -> anthropic_list_models_pipeline()
      :gemini -> gemini_list_models_pipeline()
      :groq -> groq_list_models_pipeline()
      :openrouter -> openrouter_list_models_pipeline()
      :ollama -> ollama_list_models_pipeline()
      :mock -> mock_list_models_pipeline()
      _ -> default_list_models_pipeline()
    end
  end

  # Pipeline definitions

  defp openai_chat_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 300},
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OpenAIParseResponse,
      Plugs.TrackCost
    ]
  end

  defp openai_stream_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.Providers.OpenAIParseStreamResponse,
      Plugs.ExecuteStreamRequest
    ]
  end

  defp anthropic_chat_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 300},
      Plugs.Providers.AnthropicPrepareRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.AnthropicParseResponse,
      Plugs.TrackCost
    ]
  end

  defp anthropic_stream_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.AnthropicPrepareRequest,
      Plugs.Providers.AnthropicParseStreamResponse,
      Plugs.ExecuteStreamRequest
    ]
  end

  defp gemini_chat_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 300},
      Plugs.Providers.GeminiPrepareRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.GeminiParseResponse,
      Plugs.TrackCost
    ]
  end

  defp groq_chat_pipeline do
    # Groq uses OpenAI-compatible API
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 300},
      # Reuse OpenAI format
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.ExecuteRequest,
      # Reuse OpenAI parser
      Plugs.Providers.OpenAIParseResponse,
      Plugs.TrackCost
    ]
  end

  defp mistral_chat_pipeline do
    # Mistral uses OpenAI-compatible API
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 300},
      # Reuse OpenAI format
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.ExecuteRequest,
      # Reuse OpenAI parser
      Plugs.Providers.OpenAIParseResponse,
      Plugs.TrackCost
    ]
  end

  defp ollama_chat_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      # Ollama handles context internally
      {Plugs.ManageContext, strategy: :none},
      Plugs.BuildTeslaClient,
      Plugs.Providers.OllamaPrepareRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OllamaParseResponse
      # No cost tracking for local models
    ]
  end

  defp mock_chat_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.Cache, ttl: 300},
      Plugs.Providers.MockHandler
    ]
  end

  defp mock_stream_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.StreamCoordinator,
      Plugs.Providers.MockHandler
    ]
  end

  defp groq_stream_pipeline do
    # Groq uses OpenAI-compatible streaming
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.Providers.OpenAIParseStreamResponse,
      Plugs.ExecuteStreamRequest
    ]
  end

  defp gemini_stream_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :sliding_window},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.GeminiPrepareRequest,
      Plugs.Providers.GeminiParseStreamResponse,
      Plugs.ExecuteStreamRequest
    ]
  end

  defp default_chat_pipeline do
    # Basic pipeline that works for most OpenAI-compatible APIs
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 300},
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OpenAIParseResponse,
      Plugs.TrackCost
    ]
  end

  defp mistral_stream_pipeline do
    # Mistral uses OpenAI-compatible streaming
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.Providers.OpenAIParseStreamResponse,
      Plugs.ExecuteStreamRequest,
      Plugs.TrackCost
    ]
  end

  defp openrouter_chat_pipeline do
    # OpenRouter uses OpenAI-compatible API
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 300},
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OpenAIParseResponse,
      Plugs.TrackCost
    ]
  end

  defp openrouter_stream_pipeline do
    # OpenRouter uses OpenAI-compatible streaming
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.Providers.OpenAIParseStreamResponse,
      Plugs.ExecuteStreamRequest,
      Plugs.TrackCost
    ]
  end

  defp perplexity_stream_pipeline do
    # Perplexity uses OpenAI-compatible streaming
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.Providers.OpenAIParseStreamResponse,
      Plugs.ExecuteStreamRequest,
      Plugs.TrackCost
    ]
  end

  defp ollama_stream_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :none},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.OllamaPrepareRequest,
      Plugs.Providers.OllamaParseStreamResponse,
      Plugs.ExecuteStreamRequest
      # No cost tracking for local models
    ]
  end

  defp lmstudio_stream_pipeline do
    # LMStudio uses OpenAI-compatible streaming
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.Providers.OpenAIParseStreamResponse,
      Plugs.ExecuteStreamRequest
      # No cost tracking for local models
    ]
  end

  defp bumblebee_chat_pipeline do
    # Bumblebee is a local provider that bypasses HTTP infrastructure
    # Use direct provider call instead of building HTTP clients
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :none},
      Plugs.Providers.BumblebeeHandler
    ]
  end

  defp bumblebee_stream_pipeline do
    # Bumblebee doesn't support streaming yet
    # Fall back to regular chat for now
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :none},
      Plugs.Providers.BumblebeeHandler
    ]
  end

  defp xai_chat_pipeline do
    # X.AI uses OpenAI-compatible API
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 300},
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OpenAIParseResponse,
      Plugs.TrackCost
    ]
  end

  defp xai_stream_pipeline do
    # X.AI uses OpenAI-compatible streaming
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.OpenAIPrepareRequest,
      Plugs.Providers.OpenAIParseStreamResponse,
      Plugs.ExecuteStreamRequest,
      Plugs.TrackCost
    ]
  end

  defp bedrock_chat_pipeline do
    # AWS Bedrock requires special handling
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 300},
      Plugs.Providers.BedrockPrepareRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.BedrockParseResponse,
      Plugs.TrackCost
    ]
  end

  defp bedrock_stream_pipeline do
    # AWS Bedrock streaming
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.ManageContext, strategy: :truncate},
      Plugs.BuildTeslaClient,
      Plugs.StreamCoordinator,
      Plugs.Providers.BedrockPrepareRequest,
      Plugs.Providers.BedrockParseStreamResponse,
      Plugs.ExecuteStreamRequest,
      Plugs.TrackCost
    ]
  end

  # Embeddings pipelines

  defp openai_embeddings_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.BuildTeslaClient,
      # Cache embeddings longer
      {Plugs.Cache, ttl: 600},
      Plugs.Providers.OpenAIPrepareEmbeddingRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OpenAIParseEmbeddingResponse,
      Plugs.TrackCost
    ]
  end

  defp gemini_embeddings_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 600},
      Plugs.Providers.GeminiPrepareEmbeddingRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.GeminiParseEmbeddingResponse,
      Plugs.TrackCost
    ]
  end

  defp ollama_embeddings_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.BuildTeslaClient,
      # No cost tracking for local models
      Plugs.Providers.OllamaPrepareEmbeddingRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OllamaParseEmbeddingResponse
    ]
  end

  defp mock_embeddings_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.Cache, ttl: 300},
      Plugs.Providers.MockEmbeddingHandler
    ]
  end

  defp default_embeddings_pipeline do
    # Default pipeline for OpenAI-compatible embedding APIs
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 600},
      Plugs.Providers.OpenAIPrepareEmbeddingRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OpenAIParseEmbeddingResponse,
      Plugs.TrackCost
    ]
  end

  @doc """
  Registers a custom pipeline for a provider.

  This is useful for extending ExLLM with custom providers or
  overriding default pipelines.

  ## Examples

      ExLLM.Providers.register_pipeline(:my_provider, :chat, [
        ExLLM.Plugs.ValidateProvider,
        MyApp.Plugs.CustomAuth,
        ExLLM.Plugs.ExecuteRequest
      ])
  """
  @spec register_pipeline(atom(), pipeline_type(), Pipeline.pipeline()) :: :ok
  def register_pipeline(provider, _type, pipeline) when is_atom(provider) and is_list(pipeline) do
    # In a real implementation, this would store in ETS or similar
    # For now, this is a placeholder
    :ok
  end

  # List models pipelines

  defp openai_list_models_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.BuildTeslaClient,
      # Cache model lists for 1 hour
      {Plugs.Cache, ttl: 3600},
      Plugs.Providers.OpenAIPrepareListModelsRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OpenAIParseListModelsResponse
    ]
  end

  defp anthropic_list_models_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      # Anthropic doesn't have a models API, return static list
      Plugs.Providers.AnthropicStaticModelsList
    ]
  end

  defp gemini_list_models_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 3600},
      Plugs.Providers.GeminiPrepareListModelsRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.GeminiParseListModelsResponse
    ]
  end

  defp groq_list_models_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 3600},
      Plugs.Providers.GroqPrepareListModelsRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.GroqParseListModelsResponse
    ]
  end

  defp openrouter_list_models_pipeline do
    # OpenRouter has its own model listing format with richer metadata
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.BuildTeslaClient,
      {Plugs.Cache, ttl: 3600},
      Plugs.Providers.OpenRouterPrepareListModelsRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OpenRouterParseListModelsResponse
    ]
  end

  defp ollama_list_models_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.BuildTeslaClient,
      # No caching for local models as they can change
      Plugs.Providers.OllamaPrepareListModelsRequest,
      Plugs.ExecuteRequest,
      Plugs.Providers.OllamaParseListModelsResponse
    ]
  end

  defp mock_list_models_pipeline do
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      {Plugs.Cache, ttl: 300},
      Plugs.Providers.MockListModelsHandler
    ]
  end

  defp default_list_models_pipeline do
    # Default pipeline that returns an error for unsupported providers
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.Providers.UnsupportedListModels
    ]
  end

  defp validation_pipeline do
    # Simple pipeline for checking if a provider is configured
    [
      Plugs.ValidateProvider,
      Plugs.FetchConfig,
      Plugs.ValidateConfiguration
    ]
  end
end
