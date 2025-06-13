defmodule ExLLM.Test.GeminiOAuth2Helper do
  @moduledoc """
  Test helper for Gemini OAuth2 authentication.

  This module provides utilities for using OAuth2 tokens in tests,
  including automatic token refresh when needed.
  """

  @token_file ".gemini_tokens"
  @token_refresh_script "scripts/refresh_oauth2_token.exs"

  @doc """
  Gets a valid OAuth2 token for testing.

  This function:
  1. Checks for tokens in environment variables (CI/CD friendly)
  2. Falls back to loading from .gemini_tokens file
  3. Automatically refreshes if token is expired
  4. Returns nil if no tokens are available

  ## Usage in Tests

      setup do
        case ExLLM.Test.GeminiOAuth2Helper.get_valid_token() do
          {:ok, token} ->
            {:ok, oauth_token: token}
          {:error, :no_token} ->
            :ok  # Skip OAuth tests
          {:error, reason} ->
            raise "OAuth2 setup error: \#{reason}"
        end
      end
      
      @tag :oauth_required
      test "list permissions", %{oauth_token: token} do
        {:ok, perms} = ExLLM.Gemini.Permissions.list_permissions(
          "tunedModels/test",
          oauth_token: token
        )
        # assertions...
      end
  """
  @spec get_valid_token() :: {:ok, String.t()} | {:error, :no_token | String.t()}
  def get_valid_token do
    # First check environment variable (for CI/CD)
    case System.get_env("GEMINI_OAUTH_TOKEN") do
      nil -> get_token_from_file()
      token -> {:ok, token}
    end
  end

  @doc """
  Checks if OAuth2 tokens are available for testing.
  """
  @spec oauth_available?() :: boolean()
  def oauth_available? do
    case get_valid_token() do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Skips a test if OAuth2 tokens are not available.

  ## Usage

      setup :skip_without_oauth
      
      test "requires oauth" do
        # This test will be skipped if no OAuth tokens are available
      end
  """
  def skip_without_oauth(_context) do
    if oauth_available?() do
      case get_valid_token() do
        {:ok, token} -> {:ok, oauth_token: token}
        _ -> {:ok, oauth_token: nil}
      end
    else
      IO.puts("\n⚠️  Skipping test: OAuth2 tokens not available")
      IO.puts("   Run: elixir scripts/setup_oauth2.exs")
      {:ok, skip: true}
    end
  end

  @doc """
  Gets stored refresh token.
  """
  @spec get_refresh_token() :: {:ok, String.t()} | {:error, :no_token | String.t()}
  def get_refresh_token do
    case System.get_env("GEMINI_REFRESH_TOKEN") do
      nil ->
        case load_tokens() do
          {:ok, tokens} ->
            case tokens["refresh_token"] do
              nil -> {:error, :no_token}
              token -> {:ok, token}
            end

          error ->
            error
        end

      token ->
        {:ok, token}
    end
  end

  # Private functions

  defp get_token_from_file do
    with {:ok, tokens} <- load_tokens(),
         :ok <- ensure_token_valid(tokens) do
      {:ok, tokens["access_token"]}
    end
  end

  defp load_tokens do
    token_path = Path.join(File.cwd!(), @token_file)

    case File.read(token_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, tokens} -> {:ok, tokens}
          {:error, _} -> {:error, "Invalid token file format"}
        end

      {:error, :enoent} ->
        {:error, :no_token}

      {:error, reason} ->
        {:error, "Failed to read tokens: #{reason}"}
    end
  end

  defp ensure_token_valid(tokens) do
    case tokens["expires_at"] do
      nil ->
        # No expiry info, assume valid
        :ok

      expires_at ->
        case DateTime.from_iso8601(expires_at) do
          {:ok, expiry_time, _} ->
            if DateTime.compare(DateTime.utc_now(), expiry_time) == :lt do
              :ok
            else
              # Token expired, try to refresh
              IO.puts("\n🔄 OAuth2 token expired, attempting refresh...")
              refresh_token()
            end

          _ ->
            # Can't parse expiry, assume valid
            :ok
        end
    end
  end

  defp refresh_token do
    refresh_script = Path.join(File.cwd!(), @token_refresh_script)

    if File.exists?(refresh_script) do
      case System.cmd("elixir", [refresh_script], stderr_to_stdout: true) do
        {output, 0} ->
          if String.contains?(output, "✅") do
            IO.puts("✅ Token refreshed successfully")
            :ok
          else
            {:error, "Token refresh failed"}
          end

        {output, _} ->
          {:error, "Token refresh failed: #{output}"}
      end
    else
      {:error, "Refresh script not found. Token expired."}
    end
  end

  @doc """
  Creates a mock OAuth2 token for testing error scenarios.
  """
  def mock_token(type \\ :invalid) do
    case type do
      :invalid -> "invalid-token-123"
      :expired -> "ya29.expired-#{:rand.uniform(1000)}"
      :malformed -> "not-a-valid-jwt"
      _ -> "mock-token-#{type}"
    end
  end

  @doc """
  Test helper to assert OAuth2 authentication errors.
  """
  def assert_oauth_error({:error, %{status: 401} = error}) do
    if error.message =~ "API keys are not supported" or
         error.message =~ "authentication" or
         error.message =~ "unauthorized" do
      :ok
    else
      {:error, "Expected OAuth2 authentication message, got: #{error.message}"}
    end
  end

  def assert_oauth_error(other) do
    {:error, "Expected OAuth2 authentication error (401), got: #{inspect(other)}"}
  end
end
