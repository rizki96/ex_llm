defmodule ExLLM.Testing.OAuth2.Provider do
  @moduledoc """
  Behavior for OAuth2 providers in the ExLLM testing framework.

  This behavior defines the interface that all OAuth2 providers must implement
  to support token management, refresh, and validation.
  """

  @doc """
  Returns the provider configuration including endpoints, scopes, and token storage.
  """
  @callback config() :: %{
              token_endpoint: String.t(),
              scopes: [String.t()],
              token_file: String.t(),
              client_id_env: String.t(),
              client_secret_env: String.t()
            }

  @doc """
  Checks if OAuth2 is available for this provider.

  Returns true if all required credentials and token files are present.
  """
  @callback oauth_available?() :: boolean()

  @doc """
  Gets a valid OAuth2 token for this provider.

  Returns {:ok, token} if a valid token is available, or {:error, reason} otherwise.
  Automatically attempts token refresh if the current token is expired.
  """
  @callback get_valid_token() :: {:ok, String.t()} | {:error, atom() | String.t()}

  @doc """
  Refreshes the OAuth2 token using the refresh token.

  Returns {:ok, new_tokens} if refresh is successful, or {:error, reason} otherwise.
  """
  @callback refresh_token() :: {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Loads stored tokens from the provider's token file.

  Returns {:ok, tokens} if tokens are found and valid, or {:error, reason} otherwise.
  """
  @callback load_stored_tokens() :: {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Saves tokens to the provider's token file.

  Returns :ok if successful, or {:error, reason} otherwise.
  """
  @callback save_tokens(map()) :: :ok | {:error, atom() | String.t()}

  @doc """
  Validates that the required environment variables are present.

  Returns :ok if all required variables are set, or {:error, missing_vars} otherwise.
  """
  @callback validate_environment() :: :ok | {:error, [String.t()]}

  @doc """
  Performs cleanup of test resources for this provider.

  This is called during test teardown to clean up any resources created during testing.
  """
  @callback cleanup() :: :ok | {:error, String.t()}

  @doc """
  Performs global cleanup of all test resources for this provider.

  This is called before test suites to ensure a clean state.
  """
  @callback global_cleanup() :: :ok | {:error, String.t()}
end
