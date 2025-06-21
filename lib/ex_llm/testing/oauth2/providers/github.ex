defmodule ExLLM.Testing.OAuth2.Providers.GitHub do
  @moduledoc """
  GitHub OAuth2 provider implementation for ExLLM testing.

  This is a placeholder implementation for future GitHub OAuth2 support.
  """

  @behaviour ExLLM.Testing.OAuth2.Provider

  @impl true
  def config do
    %{
      token_endpoint: "https://github.com/login/oauth/access_token",
      scopes: ["repo", "user"],
      token_file: ".github_tokens",
      client_id_env: "GITHUB_CLIENT_ID",
      client_secret_env: "GITHUB_CLIENT_SECRET"
    }
  end

  @impl true
  def oauth_available?, do: false

  @impl true
  def get_valid_token, do: {:error, :not_implemented}

  @impl true
  def refresh_token, do: {:error, :not_implemented}

  @impl true
  def load_stored_tokens, do: {:error, :not_implemented}

  @impl true
  def save_tokens(_tokens), do: {:error, :not_implemented}

  @impl true
  def validate_environment, do: {:error, ["GitHub OAuth2 not implemented"]}

  @impl true
  def cleanup, do: :ok

  @impl true
  def global_cleanup, do: :ok
end
