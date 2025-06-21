defmodule ExLLM.Testing.OAuth2.Providers.Microsoft do
  @moduledoc """
  Microsoft Azure AD OAuth2 provider implementation for ExLLM testing.

  This is a placeholder implementation for future Azure AD OAuth2 support.
  """

  @behaviour ExLLM.Testing.OAuth2.Provider

  @impl true
  def config do
    %{
      token_endpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
      scopes: ["https://graph.microsoft.com/.default"],
      token_file: ".azure_tokens",
      client_id_env: "AZURE_CLIENT_ID",
      client_secret_env: "AZURE_CLIENT_SECRET"
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
  def validate_environment, do: {:error, ["Microsoft OAuth2 not implemented"]}

  @impl true
  def cleanup, do: :ok

  @impl true
  def global_cleanup, do: :ok
end
