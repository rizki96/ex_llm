#!/usr/bin/env elixir

# OAuth2 Token Refresh Script
# 
# ⚠️  MOST USERS DON'T NEED THIS SCRIPT
# As of September 2024, API keys are the primary authentication method.
# 
# This script is only needed if you use OAuth2 for:
# - Permissions API (tuned model access control)
# - Corpus Management API (user document collections)
# - Question Answering with user corpora
#
# For everything else, use API keys: https://aistudio.google.com/app/apikey
#
# Usage: elixir scripts/refresh_oauth2_token.exs

Mix.install([
  {:req, "~> 0.5.0"},
  {:jason, "~> 1.4"}
])

defmodule OAuth2Refresh do
  @token_endpoint "https://oauth2.googleapis.com/token"
  @token_file ".gemini_tokens"

  # Load environment variables from .env file if present
  defp load_env_file do
    env_file = ".env"
    
    if File.exists?(env_file) do
      IO.puts("✓ Loading environment variables from .env file")
      
      env_file
      |> File.read!()
      |> String.split("\n")
      |> Enum.each(fn line ->
        line = String.trim(line)
        
        # Skip empty lines and comments
        unless line == "" or String.starts_with?(line, "#") do
          case String.split(line, "=", parts: 2) do
            [key, value] ->
              # Remove quotes if present
              value = String.trim(value, "\"")
              System.put_env(key, value)
            _ ->
              :ignore
          end
        end
      end)
    end
  end

  def run do
    IO.puts("\n🔄 OAuth2 Token Refresh")
    IO.puts("=" <> String.duplicate("=", 40))
    
    case refresh_tokens() do
      {:ok, tokens} ->
        IO.puts("\n✅ Token refresh successful!")
        display_new_tokens(tokens)
        
      {:error, reason} ->
        IO.puts("\n❌ Token refresh failed: #{reason}")
        System.halt(1)
    end
  end

  defp refresh_tokens do
    # Load environment variables from .env file if present
    load_env_file()
    
    with {:ok, stored_tokens} <- load_stored_tokens(),
         {:ok, config} <- get_oauth_config(),
         {:ok, new_tokens} <- refresh_token(stored_tokens["refresh_token"], config),
         :ok <- save_new_tokens(new_tokens, stored_tokens) do
      {:ok, new_tokens}
    end
  end

  defp load_stored_tokens do
    token_path = Path.join(File.cwd!(), @token_file)
    
    case File.read(token_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, tokens} ->
            if tokens["refresh_token"] do
              IO.puts("✓ Loaded tokens from #{@token_file}")
              check_token_expiry(tokens)
              {:ok, tokens}
            else
              {:error, "No refresh token found in #{@token_file}"}
            end
          {:error, _} ->
            {:error, "Invalid JSON in #{@token_file}"}
        end
      {:error, :enoent} ->
        {:error, "Token file not found. Run setup_oauth2.exs first."}
      {:error, reason} ->
        {:error, "Failed to read token file: #{reason}"}
    end
  end

  defp check_token_expiry(tokens) do
    case tokens["expires_at"] do
      nil -> 
        IO.puts("⚠️  No expiry information found")
      expires_at ->
        case DateTime.from_iso8601(expires_at) do
          {:ok, expiry_time, _} ->
            now = DateTime.utc_now()
            diff = DateTime.diff(expiry_time, now)
            
            if diff > 0 do
              minutes = div(diff, 60)
              IO.puts("ℹ️  Current token expires in #{minutes} minutes")
              IO.puts("   (Refreshing anyway to get a fresh token)")
            else
              minutes = div(-diff, 60)
              IO.puts("⚠️  Token expired #{minutes} minutes ago")
            end
          _ ->
            IO.puts("⚠️  Invalid expiry time format")
        end
    end
  end

  defp get_oauth_config do
    client_id = get_env_or_ask("GOOGLE_CLIENT_ID", "Enter your Google OAuth2 Client ID")
    client_secret = get_env_or_ask("GOOGLE_CLIENT_SECRET", "Enter your Google OAuth2 Client Secret")
    
    {:ok, %{
      client_id: client_id,
      client_secret: client_secret
    }}
  end

  defp get_env_or_ask(env_var, prompt) do
    case System.get_env(env_var) do
      nil ->
        case IO.gets("\n#{prompt}: ") do
          :eof ->
            IO.puts("\n❌ Cannot read input. Please set #{env_var} environment variable:")
            IO.puts("   export #{env_var}=\"your-value\"")
            System.halt(1)
          input ->
            value = String.trim(input)
            if value == "" do
              IO.puts("❌ #{env_var} is required")
              System.halt(1)
            end
            value
        end
      value -> 
        IO.puts("✓ Using #{env_var} from environment")
        value
    end
  end

  defp refresh_token(refresh_token, config) do
    IO.puts("\n🔄 Refreshing access token...")
    
    body = %{
      "refresh_token" => refresh_token,
      "client_id" => config.client_id,
      "client_secret" => config.client_secret,
      "grant_type" => "refresh_token"
    }
    
    case Req.post(@token_endpoint, form: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, %{
          access_token: response["access_token"],
          expires_in: response["expires_in"],
          token_type: response["token_type"],
          scope: response["scope"]
        }}
        
      {:ok, %{status: 400, body: %{"error" => "invalid_grant"}}} ->
        {:error, """
        Invalid refresh token. This can happen if:
        1. The refresh token has been revoked
        2. The OAuth2 app credentials have changed
        3. The token is corrupted
        
        Please run setup_oauth2.exs to get new tokens.
        """}
        
      {:ok, %{status: status, body: body}} ->
        {:error, "Token refresh failed (#{status}): #{inspect(body)}"}
        
      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp save_new_tokens(new_tokens, stored_tokens) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    
    # Preserve the refresh token from stored tokens
    updated_tokens = %{
      "access_token" => new_tokens.access_token,
      "refresh_token" => stored_tokens["refresh_token"],
      "expires_in" => new_tokens.expires_in,
      "token_type" => new_tokens.token_type,
      "scope" => new_tokens.scope,
      "created_at" => timestamp,
      "expires_at" => DateTime.utc_now() 
        |> DateTime.add(new_tokens.expires_in, :second) 
        |> DateTime.to_iso8601(),
      "refreshed_at" => timestamp,
      "original_created_at" => stored_tokens["original_created_at"] || stored_tokens["created_at"]
    }
    
    token_path = Path.join(File.cwd!(), @token_file)
    
    # Backup old tokens
    backup_path = "#{token_path}.backup"
    File.copy!(token_path, backup_path)
    
    case File.write(token_path, Jason.encode!(updated_tokens, pretty: true)) do
      :ok ->
        IO.puts("💾 Updated tokens saved to: #{token_path}")
        IO.puts("📋 Backup saved to: #{backup_path}")
        :ok
      {:error, reason} ->
        {:error, "Failed to save tokens: #{reason}"}
    end
  end

  defp display_new_tokens(tokens) do
    IO.puts("\n🎉 New Access Token Retrieved!")
    IO.puts("=" <> String.duplicate("=", 40))
    
    IO.puts("\n🔑 New Access Token (valid for #{tokens.expires_in} seconds):")
    IO.puts("   #{String.slice(tokens.access_token, 0..50)}...")
    
    IO.puts("\n📋 Token Details:")
    IO.puts("   Type: #{tokens.token_type}")
    IO.puts("   Expires in: #{div(tokens.expires_in, 60)} minutes")
    IO.puts("   Scopes: #{tokens.scope}")
    
    IO.puts("\n💡 Quick Test:")
    IO.puts("""
    
    # Test the new token:
    iex> {:ok, tokens} = File.read!(".gemini_tokens") |> Jason.decode!()
    iex> {:ok, perms} = ExLLM.Gemini.Permissions.list_permissions(
    ...>   "tunedModels/your-model",
    ...>   oauth_token: tokens["access_token"]
    ...> )
    """)
    
    IO.puts("\n📅 Next Steps:")
    IO.puts("   - This token will expire in #{div(tokens.expires_in, 60)} minutes")
    IO.puts("   - Run this script again to refresh when needed")
    IO.puts("   - Or implement automatic refresh in your application")
  end
end

# Run the refresh
OAuth2Refresh.run()