defmodule ExLLM.Environment do
  @moduledoc """
  Centralized environment variable definitions and documentation for ExLLM.

  This module provides a single source of truth for all environment variables
  used throughout the ExLLM library, ensuring consistent naming and usage.

  ## Categories

  ### Provider API Keys
  - `ANTHROPIC_API_KEY` - API key for Anthropic Claude
  - `OPENAI_API_KEY` - API key for OpenAI GPT models
  - `GEMINI_API_KEY` / `GOOGLE_API_KEY` - API key for Google Gemini
  - `GROQ_API_KEY` - API key for Groq
  - `MISTRAL_API_KEY` - API key for Mistral AI
  - `OPENROUTER_API_KEY` - API key for OpenRouter
  - `PERPLEXITY_API_KEY` - API key for Perplexity
  - `XAI_API_KEY` - API key for X.AI (Grok)

  ### Provider Base URLs
  - `ANTHROPIC_BASE_URL` - Override Anthropic API endpoint (default: https://api.anthropic.com/v1)
  - `OPENAI_BASE_URL` - Override OpenAI API endpoint (default: https://api.openai.com/v1)
  - `GEMINI_BASE_URL` - Override Gemini API endpoint
  - `GROQ_BASE_URL` - Override Groq API endpoint
  - `MISTRAL_BASE_URL` - Override Mistral API endpoint
  - `OPENROUTER_BASE_URL` - Override OpenRouter endpoint (default: https://openrouter.ai)
  - `PERPLEXITY_BASE_URL` - Override Perplexity endpoint
  - `XAI_BASE_URL` - Override X.AI endpoint
  - `OLLAMA_HOST` / `OLLAMA_BASE_URL` - Ollama server URL (default: http://localhost:11434)
  - `LMSTUDIO_HOST` - LM Studio server URL

  ### Provider Models
  - `ANTHROPIC_MODEL` - Default model for Anthropic (default: claude-sonnet-4-20250514)
  - `OPENAI_MODEL` - Default model for OpenAI (default: gpt-4.1-nano)
  - `GEMINI_MODEL` - Default model for Gemini
  - `GROQ_MODEL` - Default model for Groq
  - `MISTRAL_MODEL` - Default model for Mistral
  - `OPENROUTER_MODEL` - Default model for OpenRouter (default: openai/gpt-4o-mini)
  - `PERPLEXITY_MODEL` - Default model for Perplexity
  - `XAI_MODEL` - Default model for X.AI
  - `OLLAMA_MODEL` - Default model for Ollama
  - `BUMBLEBEE_MODEL_PATH` - Path to local Bumblebee model

  ### Provider-Specific
  - `OPENAI_ORGANIZATION` - OpenAI organization ID
  - `OPENROUTER_APP_NAME` - Application name for OpenRouter requests
  - `OPENROUTER_APP_URL` - Application URL for OpenRouter requests
  - `BUMBLEBEE_DEVICE` - Device for Bumblebee inference (:cpu or :cuda)

  ### OAuth2 / Authentication
  - `GOOGLE_CLIENT_ID` - Google OAuth2 client ID
  - `GOOGLE_CLIENT_SECRET` - Google OAuth2 client secret
  - `GOOGLE_REFRESH_TOKEN` - Google OAuth2 refresh token

  ### AWS / Bedrock
  - `AWS_ACCESS_KEY_ID` - AWS access key
  - `AWS_SECRET_ACCESS_KEY` - AWS secret key
  - `AWS_SESSION_TOKEN` - AWS session token (optional)
  - `AWS_REGION` - AWS region (default: us-east-1)
  - `BEDROCK_ACCESS_KEY_ID` - Bedrock-specific access key
  - `BEDROCK_SECRET_ACCESS_KEY` - Bedrock-specific secret key
  - `BEDROCK_REGION` - Bedrock region

  ### Test Environment
  - `EX_LLM_ENV_FILE` - Custom .env file path (default: .env)
  - `EX_LLM_TEST_CACHE_ENABLED` - Enable test response caching (true/false)
  - `EX_LLM_LOG_LEVEL` - Log level for tests (debug/info/warn/error/none)
  - `MIX_RUN_LIVE` - Force live API calls in tests (true/false)
  - `TEST_TUNED_MODEL` - Tuned model ID for testing
  - `TEST_CORPUS_NAME` - Pre-existing corpus for testing
  - `TEST_DOCUMENT_NAME` - Pre-existing document for testing

  ### Cache Configuration
  - `EX_LLM_CACHE_ENABLED` - Global cache enable (true/false)
  - `EX_LLM_CACHE_TTL` - Cache time-to-live in seconds
  - `EX_LLM_CACHE_MAX_SIZE` - Maximum cache size
  - `EX_LLM_CACHE_STRATEGY` - Cache strategy (memory/disk/hybrid)

  ### Development
  - `HEX_API_KEY` - Hex.pm API key for publishing
  - `MOCK_RESPONSE_MODE` - Mock response mode for testing
  """

  @provider_api_keys %{
    anthropic: "ANTHROPIC_API_KEY",
    openai: "OPENAI_API_KEY",
    gemini: ["GEMINI_API_KEY", "GOOGLE_API_KEY"],
    groq: "GROQ_API_KEY",
    mistral: "MISTRAL_API_KEY",
    openrouter: "OPENROUTER_API_KEY",
    perplexity: "PERPLEXITY_API_KEY",
    xai: "XAI_API_KEY",
    ollama: "OLLAMA_HOST",
    lmstudio: "LMSTUDIO_HOST"
  }

  @provider_base_urls %{
    anthropic: {"ANTHROPIC_BASE_URL", "https://api.anthropic.com"},
    openai: {"OPENAI_BASE_URL", "https://api.openai.com"},
    gemini: {"GEMINI_BASE_URL", nil},
    groq: {"GROQ_BASE_URL", nil},
    mistral: {"MISTRAL_BASE_URL", nil},
    openrouter: {"OPENROUTER_BASE_URL", "https://openrouter.ai"},
    perplexity: {"PERPLEXITY_BASE_URL", nil},
    xai: {"XAI_BASE_URL", nil},
    ollama: {"OLLAMA_BASE_URL", "http://localhost:11434"},
    lmstudio: {"LMSTUDIO_BASE_URL", "http://localhost:1234"}
  }

  @provider_models %{
    anthropic: {"ANTHROPIC_MODEL", "claude-sonnet-4-20250514"},
    openai: {"OPENAI_MODEL", "gpt-4.1-nano"},
    gemini: {"GEMINI_MODEL", nil},
    groq: {"GROQ_MODEL", nil},
    mistral: {"MISTRAL_MODEL", nil},
    openrouter: {"OPENROUTER_MODEL", "openai/gpt-4o-mini"},
    perplexity: {"PERPLEXITY_MODEL", nil},
    xai: {"XAI_MODEL", nil},
    ollama: {"OLLAMA_MODEL", nil}
  }

  @doc """
  Get the API key environment variable name for a provider.

  ## Examples

      iex> ExLLM.Environment.api_key_var(:openai)
      "OPENAI_API_KEY"

      iex> ExLLM.Environment.api_key_var(:gemini)
      ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
  """
  def api_key_var(provider) when is_atom(provider) do
    Map.get(@provider_api_keys, provider)
  end

  @doc """
  Get the base URL environment variable and default for a provider.

  ## Examples

      iex> ExLLM.Environment.base_url_var(:openai)
      {"OPENAI_BASE_URL", "https://api.openai.com"}
  """
  def base_url_var(provider) when is_atom(provider) do
    Map.get(@provider_base_urls, provider)
  end

  @doc """
  Get the model environment variable and default for a provider.

  ## Examples

      iex> ExLLM.Environment.model_var(:anthropic)
      {"ANTHROPIC_MODEL", "claude-sonnet-4-20250514"}
  """
  def model_var(provider) when is_atom(provider) do
    Map.get(@provider_models, provider)
  end

  @doc """
  Get an environment variable with optional default.

  ## Examples

      iex> ExLLM.Environment.get("OPENAI_API_KEY")
      "sk-..."

      iex> ExLLM.Environment.get("CUSTOM_VAR", "default")
      "default"
  """
  def get(var_name, default \\ nil) do
    System.get_env(var_name, default)
  end

  @doc """
  Check if an environment variable is set.

  ## Examples

      iex> ExLLM.Environment.set?("OPENAI_API_KEY")
      true
  """
  def set?(var_name) do
    System.get_env(var_name) != nil
  end

  @doc """
  Get all provider API key environment variables.

  ## Examples

      iex> ExLLM.Environment.all_api_key_vars()
      ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", ...]
  """
  def all_api_key_vars do
    @provider_api_keys
    |> Map.values()
    |> Enum.flat_map(fn
      vars when is_list(vars) -> vars
      var -> [var]
    end)
    |> Enum.uniq()
  end

  @doc """
  Get provider configuration from environment variables.

  ## Examples

      iex> ExLLM.Environment.provider_config(:openai)
      %{
        api_key: "sk-...",
        base_url: "https://api.openai.com/v1",
        model: "gpt-4.1-nano"
      }
  """
  def provider_config(provider) when is_atom(provider) do
    config = %{}

    # Add API key
    config =
      case api_key_var(provider) do
        vars when is_list(vars) ->
          key = Enum.find_value(vars, &System.get_env/1)
          Map.put(config, :api_key, key)

        var when is_binary(var) ->
          Map.put(config, :api_key, System.get_env(var))

        _ ->
          config
      end

    # Add base URL
    config =
      case base_url_var(provider) do
        {var, default} ->
          Map.put(config, :base_url, System.get_env(var, default))

        _ ->
          config
      end

    # Add model
    config =
      case model_var(provider) do
        {var, default} ->
          Map.put(config, :model, System.get_env(var, default))

        _ ->
          config
      end

    config
  end

  @doc """
  Check which provider API keys are available in the environment.

  ## Examples

      iex> ExLLM.Environment.available_providers()
      [:openai, :anthropic]
  """
  def available_providers do
    @provider_api_keys
    |> Enum.filter(fn {_provider, vars} ->
      case vars do
        vars when is_list(vars) -> Enum.any?(vars, &System.get_env/1)
        var -> System.get_env(var) != nil
      end
    end)
    |> Enum.map(&elem(&1, 0))
  end
end
