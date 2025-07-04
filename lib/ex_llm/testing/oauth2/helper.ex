defmodule ExLLM.Testing.OAuth2.Helper do
  @moduledoc """
  Generalized OAuth2 helper for testing with multiple providers.

  This module provides a unified interface for OAuth2 operations across different
  providers while maintaining backward compatibility with existing code.
  """

  require Logger

  alias ExLLM.Testing.OAuth2.TokenStorage

  @providers %{
    google: ExLLM.Testing.OAuth2.Providers.Google,
    # Alias for backward compatibility
    gemini: ExLLM.Testing.OAuth2.Providers.Google,
    microsoft: ExLLM.Testing.OAuth2.Providers.Microsoft,
    github: ExLLM.Testing.OAuth2.Providers.GitHub
  }

  @doc """
  Checks if OAuth2 is available for the specified provider.

  ## Examples

      iex> ExLLM.Testing.OAuth2.Helper.oauth_available?(:google)
      true
      
      iex> ExLLM.Testing.OAuth2.Helper.oauth_available?(:microsoft)
      false
  """
  @spec oauth_available?(atom()) :: boolean()
  def oauth_available?(provider) do
    case get_provider_module(provider) do
      {:ok, module} -> module.oauth_available?()
      {:error, _} -> false
    end
  end

  @doc """
  Gets a valid OAuth2 token for the specified provider.

  Automatically attempts token refresh if the current token is expired.

  ## Examples

      iex> ExLLM.Testing.OAuth2.Helper.get_valid_token(:google)
      {:ok, "ya29.a0AfH6SMBx..."}
      
      iex> ExLLM.Testing.OAuth2.Helper.get_valid_token(:invalid_provider)
      {:error, :provider_not_supported}
  """
  @spec get_valid_token(atom()) :: {:ok, String.t()} | {:error, atom() | String.t()}
  def get_valid_token(provider) do
    case get_provider_module(provider) do
      {:ok, module} -> module.get_valid_token()
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Refreshes the OAuth2 token for the specified provider.

  ## Examples

      iex> ExLLM.Testing.OAuth2.Helper.refresh_token(:google)
      {:ok, %{"access_token" => "...", "refresh_token" => "..."}}
  """
  @spec refresh_token(atom()) :: {:ok, map()} | {:error, atom() | String.t()}
  def refresh_token(provider) do
    case get_provider_module(provider) do
      {:ok, module} -> module.refresh_token()
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets up OAuth2 for testing by attempting to refresh tokens if needed.

  This is the main function used by OAuth2TestCase to ensure valid tokens
  are available before running tests.

  ## Examples

      iex> ExLLM.Testing.OAuth2.Helper.setup_oauth(:google, %{})
      %{oauth_token: "ya29.a0AfH6SMBx..."}
  """
  @spec setup_oauth(atom(), map()) :: map()
  def setup_oauth(provider, context \\ %{}) do
    case refresh_if_needed(provider) do
      :ok ->
        case get_valid_token(provider) do
          {:ok, token} ->
            Logger.debug("✅ OAuth2 setup successful for #{provider}")
            Map.put(context, :oauth_token, token)

          {:error, reason} ->
            Logger.warning("⚠️  OAuth2 token unavailable for #{provider}: #{reason}")
            context
        end

      {:ok, _token_data} ->
        # Token was refreshed successfully, now get the valid token
        case get_valid_token(provider) do
          {:ok, token} ->
            Logger.debug("✅ OAuth2 setup successful for #{provider} (after refresh)")
            Map.put(context, :oauth_token, token)

          {:error, reason} ->
            Logger.warning("⚠️  OAuth2 token unavailable for #{provider}: #{reason}")
            context
        end

      {:error, reason} ->
        Logger.warning("⚠️  OAuth2 refresh failed for #{provider}: #{reason}")

        # Try to get existing token even if refresh failed
        case get_valid_token(provider) do
          {:ok, token} ->
            Logger.info("Using existing token for #{provider}")
            Map.put(context, :oauth_token, token)

          {:error, _} ->
            context
        end
    end
  end

  @doc """
  Performs cleanup for the specified provider.

  This is called during test teardown to clean up resources.
  """
  @spec cleanup(atom()) :: :ok | {:error, String.t()}
  def cleanup(provider) do
    case get_provider_module(provider) do
      {:ok, module} -> module.cleanup()
      {:error, _} -> :ok
    end
  end

  @doc """
  Performs global cleanup for the specified provider.

  This is called before test suites to ensure a clean state.
  """
  @spec global_cleanup(atom()) :: :ok | {:error, String.t()}
  def global_cleanup(provider) do
    case get_provider_module(provider) do
      {:ok, module} -> module.global_cleanup()
      {:error, _} -> :ok
    end
  end

  @doc """
  Lists all supported OAuth2 providers.

  ## Examples

      iex> ExLLM.Testing.OAuth2.Helper.supported_providers()
      [:google, :gemini, :microsoft, :github]
  """
  @spec supported_providers() :: [atom()]
  def supported_providers do
    Map.keys(@providers)
  end

  @doc """
  Gets the configuration for the specified provider.

  ## Examples

      iex> ExLLM.Testing.OAuth2.Helper.get_provider_config(:google)
      {:ok, %{token_endpoint: "...", scopes: [...], ...}}
  """
  @spec get_provider_config(atom()) :: {:ok, map()} | {:error, atom()}
  def get_provider_config(provider) do
    case get_provider_module(provider) do
      {:ok, module} -> {:ok, module.config()}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates the environment for the specified provider.

  Checks that all required environment variables are present.
  """
  @spec validate_environment(atom()) :: :ok | {:error, [String.t()]}
  def validate_environment(provider) do
    case get_provider_module(provider) do
      {:ok, module} -> module.validate_environment()
      {:error, _} -> {:error, ["Provider #{provider} not supported"]}
    end
  end

  # Private helper functions

  defp get_provider_module(provider) do
    case Map.get(@providers, provider) do
      nil -> {:error, :provider_not_supported}
      module -> {:ok, module}
    end
  end

  defp refresh_if_needed(provider) do
    case get_provider_module(provider) do
      {:ok, module} ->
        case module.load_stored_tokens() do
          {:ok, tokens} ->
            if TokenStorage.token_needs_refresh?(tokens) do
              Logger.info("🔄 Refreshing OAuth2 tokens for #{provider}...")
              module.refresh_token()
            else
              :ok
            end

          {:error, _} ->
            # No existing tokens, try to refresh anyway
            Logger.info("🔄 Attempting OAuth2 token refresh for #{provider}...")
            module.refresh_token()
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
