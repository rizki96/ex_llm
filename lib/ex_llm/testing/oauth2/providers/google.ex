defmodule ExLLM.Testing.OAuth2.Providers.Google do
  @moduledoc """
  Google OAuth2 provider implementation for ExLLM testing.

  Handles OAuth2 authentication for Google/Gemini APIs including token refresh,
  validation, and storage management.
  """

  @behaviour ExLLM.Testing.OAuth2.Provider

  require Logger

  alias ExLLM.Testing.OAuth2.TokenStorage

  @token_endpoint "https://oauth2.googleapis.com/token"
  @token_file ".gemini_tokens"
  @scopes [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/generative-language.tuning",
    "https://www.googleapis.com/auth/generative-language.retriever",
    "openid",
    "https://www.googleapis.com/auth/userinfo.email"
  ]

  @impl true
  def config do
    %{
      token_endpoint: @token_endpoint,
      scopes: @scopes,
      token_file: @token_file,
      client_id_env: "GOOGLE_CLIENT_ID",
      client_secret_env: "GOOGLE_CLIENT_SECRET"
    }
  end

  @impl true
  def oauth_available? do
    case get_valid_token() do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def get_valid_token do
    # First check environment variable (for CI/CD)
    case System.get_env("GEMINI_OAUTH_TOKEN") do
      nil -> get_token_from_file()
      token -> {:ok, token}
    end
  end

  @impl true
  def refresh_token do
    with {:ok, stored_tokens} <- load_stored_tokens(),
         {:ok, config} <- get_oauth_config(),
         {:ok, new_tokens} <- refresh_token_request(stored_tokens["refresh_token"], config),
         :ok <- save_new_tokens(new_tokens, stored_tokens) do
      {:ok, new_tokens}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def load_stored_tokens do
    TokenStorage.load_tokens(@token_file)
  end

  @impl true
  def save_tokens(tokens) do
    TokenStorage.save_tokens(tokens, @token_file)
  end

  @impl true
  def validate_environment do
    required_vars = ["GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET"]
    missing_vars = Enum.filter(required_vars, &(System.get_env(&1) == nil))

    case missing_vars do
      [] -> :ok
      vars -> {:error, vars}
    end
  end

  @impl true
  def cleanup do
    # Quick cleanup after each test to prevent accumulation
    Logger.debug("Performing quick OAuth2 cleanup for Google")
    :ok
  end

  @impl true
  def global_cleanup do
    # Aggressive cleanup to avoid quota limits
    Logger.info("Performing global OAuth2 cleanup for Google")
    :ok
  end

  # Private helper functions

  defp get_token_from_file do
    case load_stored_tokens() do
      {:ok, tokens} ->
        if TokenStorage.token_needs_refresh?(tokens) do
          Logger.info("🔄 Token expired, attempting refresh...")

          case refresh_token() do
            {:ok, new_tokens} ->
              {:ok, new_tokens["access_token"]}

            {:error, reason} ->
              Logger.warning("Token refresh failed: #{reason}")
              # Return existing token even if expired, let the API handle it
              {:ok, tokens["access_token"]}
          end
        else
          {:ok, tokens["access_token"]}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_oauth_config do
    client_id = System.get_env("GOOGLE_CLIENT_ID")
    client_secret = System.get_env("GOOGLE_CLIENT_SECRET")

    cond do
      is_nil(client_id) ->
        {:error, "GOOGLE_CLIENT_ID environment variable not set"}

      is_nil(client_secret) ->
        {:error, "GOOGLE_CLIENT_SECRET environment variable not set"}

      true ->
        {:ok, %{client_id: client_id, client_secret: client_secret}}
    end
  end

  defp refresh_token_request(refresh_token, config) do
    body = %{
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: config.client_id,
      client_secret: config.client_secret
    }

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Accept", "application/json"}
    ]

    case Req.post(@token_endpoint, form: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        Logger.info("✅ OAuth2 token refresh successful")
        {:ok, response_body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("OAuth2 token refresh failed: #{status} - #{inspect(body)}")
        {:error, "Token refresh failed with status #{status}"}

      {:error, reason} ->
        Logger.error("OAuth2 token refresh request failed: #{inspect(reason)}")
        {:error, "Network error during token refresh"}
    end
  end

  defp save_new_tokens(new_tokens, stored_tokens) do
    # Merge new tokens with existing ones, preserving refresh_token if not provided
    updated_tokens =
      stored_tokens
      |> Map.merge(new_tokens)
      |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())

    case save_tokens(updated_tokens) do
      :ok ->
        Logger.info("✅ Updated OAuth2 tokens saved")
        :ok

      {:error, reason} ->
        Logger.error("Failed to save updated tokens: #{reason}")
        {:error, reason}
    end
  end
end
