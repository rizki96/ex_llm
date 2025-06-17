defmodule ExLLM.Providers do
  @moduledoc """
  Registry and configuration for LLM providers.

  This module manages provider registration and their default pipelines.
  Each provider can define multiple pipelines for different operations
  (chat, streaming, embeddings, etc.).
  """

  alias ExLLM.Pipeline
  alias ExLLM.Plugs

  @type pipeline_type :: :chat | :stream | :embeddings | :completion

  @doc """
  Gets the pipeline for a specific provider and operation type.

  ## Examples

      pipeline = ExLLM.Providers.get_pipeline(:openai, :chat)
  """
  @spec get_pipeline(atom(), pipeline_type()) :: Pipeline.pipeline()
  def get_pipeline(provider, type \\ :chat) do
    case {provider, type} do
      {:openai, :chat} -> openai_chat_pipeline()
      {:openai, :stream} -> openai_stream_pipeline()
      {:anthropic, :chat} -> anthropic_chat_pipeline()
      {:anthropic, :stream} -> anthropic_stream_pipeline()
      {:gemini, :chat} -> gemini_chat_pipeline()
      {:groq, :chat} -> groq_chat_pipeline()
      {:mistral, :chat} -> mistral_chat_pipeline()
      {:ollama, :chat} -> ollama_chat_pipeline()
      {:mock, :chat} -> mock_chat_pipeline()
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
      Plugs.Providers.MockHandler
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
end
