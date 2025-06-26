defmodule ExLLM.Providers.Shared.HTTP.Authentication do
  @moduledoc """
  Tesla middleware for provider-specific authentication.

  This middleware handles authentication headers and API versioning for different
  LLM providers. Each provider has its own authentication requirements:

  - OpenAI: Bearer token in Authorization header
  - Anthropic: API key in x-api-key header + version header
  - Groq: Bearer token in Authorization header  
  - Gemini: API key in URL parameter or Authorization header
  - Others: Various patterns

  ## Usage

      middleware = [
        {HTTP.Authentication, provider: :openai, api_key: "sk-..."}
      ]
      
      client = Tesla.client(middleware)
  """

  @behaviour Tesla.Middleware

  alias ExLLM.Infrastructure.Logger

  @impl Tesla.Middleware
  def call(env, next, opts) do
    provider = Keyword.get(opts, :provider, :openai)
    api_key = Keyword.get(opts, :api_key)

    if api_key do
      env
      |> add_authentication_headers(provider, api_key, opts)
      |> add_version_headers(provider, opts)
      |> Tesla.run(next)
    else
      Logger.warning("No API key provided for #{provider}")
      Tesla.run(env, next)
    end
  end

  # Provider-specific authentication

  defp add_authentication_headers(env, :openai, api_key, _opts) when is_binary(api_key) do
    Tesla.put_header(env, "authorization", "Bearer #{api_key}")
  end

  defp add_authentication_headers(env, :openai, api_key, _opts) do
    require Logger
    Logger.warning("Invalid API key for OpenAI: #{inspect(api_key)}")
    env
  end

  defp add_authentication_headers(env, :anthropic, api_key, _opts) when is_binary(api_key) do
    env
    |> Tesla.put_header("x-api-key", api_key)
    |> Tesla.put_header("anthropic-version", "2023-06-01")
  end

  defp add_authentication_headers(env, :anthropic, api_key, _opts) do
    require Logger
    Logger.warning("Invalid API key for Anthropic: #{inspect(api_key)}")
    env
  end

  defp add_authentication_headers(env, :groq, api_key, _opts) when is_binary(api_key) do
    Tesla.put_header(env, "authorization", "Bearer #{api_key}")
  end

  defp add_authentication_headers(env, :groq, api_key, _opts) do
    require Logger
    Logger.warning("Invalid API key for Groq: #{inspect(api_key)}")
    env
  end

  defp add_authentication_headers(env, :gemini, api_key, opts) when is_binary(api_key) do
    auth_method = Keyword.get(opts, :auth_method, :query_param)

    case auth_method do
      :query_param ->
        # Add API key as query parameter
        current_query = env.query || []
        new_query = [{"key", api_key} | current_query]
        %{env | query: new_query}

      :header ->
        Tesla.put_header(env, "authorization", "Bearer #{api_key}")

      :oauth ->
        # OAuth token should already be in options
        oauth_token = Keyword.get(opts, :oauth_token)

        if oauth_token do
          Tesla.put_header(env, "authorization", "Bearer #{oauth_token}")
        else
          env
        end
    end
  end

  defp add_authentication_headers(env, :gemini, api_key, _opts) do
    require Logger
    Logger.warning("Invalid API key for Gemini: #{inspect(api_key)}")
    env
  end

  defp add_authentication_headers(env, :mistral, api_key, _opts) when is_binary(api_key) do
    Tesla.put_header(env, "authorization", "Bearer #{api_key}")
  end

  defp add_authentication_headers(env, :mistral, api_key, _opts) do
    require Logger
    Logger.warning("Invalid API key for Mistral: #{inspect(api_key)}")
    env
  end

  defp add_authentication_headers(env, :openrouter, api_key, opts) when is_binary(api_key) do
    env = Tesla.put_header(env, "authorization", "Bearer #{api_key}")

    # Add optional HTTP referer for OpenRouter
    case Keyword.get(opts, :http_referer) do
      nil -> env
      referer -> Tesla.put_header(env, "http-referer", referer)
    end
  end

  defp add_authentication_headers(env, :openrouter, api_key, _opts) do
    require Logger
    Logger.warning("Invalid API key for OpenRouter: #{inspect(api_key)}")
    env
  end

  defp add_authentication_headers(env, :perplexity, api_key, _opts) when is_binary(api_key) do
    Tesla.put_header(env, "authorization", "Bearer #{api_key}")
  end

  defp add_authentication_headers(env, :perplexity, api_key, _opts) do
    require Logger
    Logger.warning("Invalid API key for Perplexity: #{inspect(api_key)}")
    env
  end

  defp add_authentication_headers(env, :xai, api_key, _opts) when is_binary(api_key) do
    Tesla.put_header(env, "authorization", "Bearer #{api_key}")
  end

  defp add_authentication_headers(env, :xai, api_key, _opts) do
    require Logger
    Logger.warning("Invalid API key for XAI: #{inspect(api_key)}")
    env
  end

  defp add_authentication_headers(env, :ollama, _api_key, _opts) do
    # Ollama typically doesn't require authentication for local usage
    env
  end

  defp add_authentication_headers(env, :lmstudio, _api_key, _opts) do
    # LM Studio typically doesn't require authentication for local usage
    env
  end

  defp add_authentication_headers(env, :bedrock, _api_key, _opts) do
    # AWS Bedrock uses SigV4 signing, handled by separate AWSAuth plug
    # This middleware just passes through
    env
  end

  defp add_authentication_headers(env, provider, api_key, _opts) when is_binary(api_key) do
    Logger.warning("Unknown provider #{provider}, using default Bearer auth")
    Tesla.put_header(env, "authorization", "Bearer #{api_key}")
  end

  defp add_authentication_headers(env, provider, api_key, _opts) do
    require Logger
    Logger.warning("Unknown provider #{provider} with invalid API key: #{inspect(api_key)}")
    env
  end

  # Provider-specific version headers and additional headers

  defp add_version_headers(env, :anthropic, _opts) do
    env
    |> Tesla.put_header("anthropic-version", "2023-06-01")
    |> Tesla.put_header("anthropic-beta", "messages-2023-12-15")
  end

  defp add_version_headers(env, :openai, opts) do
    case Keyword.get(opts, :openai_version) do
      nil -> env
      version -> Tesla.put_header(env, "openai-version", version)
    end
  end

  defp add_version_headers(env, :gemini, opts) do
    # Add Google-specific headers
    env = Tesla.put_header(env, "x-goog-api-client", "ex_llm/1.0.0")

    case Keyword.get(opts, :safety_settings) do
      nil -> env
      :none -> Tesla.put_header(env, "x-goog-safety-setting", "BLOCK_NONE")
      _ -> env
    end
  end

  defp add_version_headers(env, :openrouter, opts) do
    env = Tesla.put_header(env, "x-title", Keyword.get(opts, :app_name, "ExLLM"))

    case Keyword.get(opts, :app_url) do
      nil -> env
      url -> Tesla.put_header(env, "x-source-url", url)
    end
  end

  defp add_version_headers(env, _provider, _opts) do
    # Default: no additional headers
    env
  end

  @doc """
  Validate authentication configuration for a provider.

  ## Examples

      iex> HTTP.Authentication.valid_auth?(:openai, api_key: "sk-...")
      true
      
      iex> HTTP.Authentication.valid_auth?(:openai, [])
      false
  """
  @spec valid_auth?(atom(), keyword()) :: boolean()
  def valid_auth?(provider, opts) do
    case provider do
      # No auth required
      :ollama -> true
      # No auth required
      :lmstudio -> true
      # Special case for AWS
      :bedrock -> has_aws_credentials?(opts)
      # Multiple auth methods
      :gemini -> has_gemini_auth?(opts)
      _ -> Keyword.has_key?(opts, :api_key) and not is_nil(Keyword.get(opts, :api_key))
    end
  end

  defp has_aws_credentials?(opts) do
    # Check for AWS credentials in various forms
    Keyword.has_key?(opts, :access_key_id) or
      Keyword.has_key?(opts, :aws_profile) or
      System.get_env("AWS_ACCESS_KEY_ID") != nil
  end

  defp has_gemini_auth?(opts) do
    # Gemini supports multiple auth methods
    Keyword.has_key?(opts, :api_key) or
      Keyword.has_key?(opts, :oauth_token) or
      Keyword.has_key?(opts, :service_account_key)
  end

  @doc """
  Extract API key from various sources for a provider.

  Checks in order:
  1. Explicit opts[:api_key]
  2. Environment variable
  3. Config provider
  """
  @spec get_api_key(atom(), keyword()) :: String.t() | nil
  def get_api_key(provider, opts) do
    opts[:api_key] ||
      get_env_api_key(provider) ||
      get_config_api_key(provider, opts)
  end

  defp get_env_api_key(provider) do
    case provider do
      :openai -> System.get_env("OPENAI_API_KEY")
      :anthropic -> System.get_env("ANTHROPIC_API_KEY")
      :groq -> System.get_env("GROQ_API_KEY")
      :gemini -> System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")
      :mistral -> System.get_env("MISTRAL_API_KEY")
      :openrouter -> System.get_env("OPENROUTER_API_KEY")
      :perplexity -> System.get_env("PERPLEXITY_API_KEY")
      :xai -> System.get_env("XAI_API_KEY")
      _ -> nil
    end
  end

  defp get_config_api_key(provider, opts) do
    case Keyword.get(opts, :config_provider) do
      nil ->
        nil

      config_provider ->
        case ExLLM.Infrastructure.ConfigProvider.get_config(config_provider, provider) do
          {:ok, config} -> config[:api_key]
          _ -> nil
        end
    end
  end
end
