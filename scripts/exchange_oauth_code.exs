#!/usr/bin/env elixir

# Exchange OAuth2 Authorization Code for Tokens
#
# Usage: elixir scripts/exchange_oauth_code.exs "authorization_code"

Mix.install([
  {:req, "~> 0.5.0"},
  {:jason, "~> 1.4"}
])

defmodule ExchangeCode do
  @token_endpoint "https://oauth2.googleapis.com/token"
  @token_file ".gemini_tokens"
  @redirect_uri "http://localhost:8080/callback"

  def run(args) do
    case args do
      [code] ->
        exchange_code(code)
      _ ->
        IO.puts("Usage: elixir scripts/exchange_oauth_code.exs \"authorization_code\"")
        IO.puts("\nYou can get the code from the URL after authorizing in your browser.")
        IO.puts("Look for the 'code=' parameter in the redirect URL.")
        System.halt(1)
    end
  end

  defp exchange_code(code) do
    client_id = System.get_env("GOOGLE_CLIENT_ID")
    client_secret = System.get_env("GOOGLE_CLIENT_SECRET")
    
    if !client_id || !client_secret do
      IO.puts("❌ Error: Missing credentials")
      IO.puts("Please set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET environment variables")
      System.halt(1)
    end
    
    IO.puts("\n🔄 Exchanging authorization code for tokens...")
    
    body = %{
      "code" => code,
      "client_id" => client_id,
      "client_secret" => client_secret,
      "redirect_uri" => @redirect_uri,
      "grant_type" => "authorization_code"
    }
    
    case Req.post(@token_endpoint, form: body) do
      {:ok, %{status: 200, body: response}} ->
        save_tokens(response)
        
      {:ok, %{status: status, body: body}} ->
        IO.puts("\n❌ Token exchange failed (#{status})")
        IO.puts("Error: #{inspect(body)}")
        System.halt(1)
        
      {:error, reason} ->
        IO.puts("\n❌ Network error: #{inspect(reason)}")
        System.halt(1)
    end
  end
  
  defp save_tokens(response) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    
    token_data = %{
      "access_token" => response["access_token"],
      "refresh_token" => response["refresh_token"],
      "expires_in" => response["expires_in"],
      "token_type" => response["token_type"],
      "scope" => response["scope"],
      "created_at" => timestamp,
      "expires_at" => DateTime.utc_now() 
        |> DateTime.add(response["expires_in"], :second) 
        |> DateTime.to_iso8601(),
      "original_created_at" => timestamp
    }
    
    token_path = Path.join(File.cwd!(), @token_file)
    
    case File.write(token_path, Jason.encode!(token_data, pretty: true)) do
      :ok ->
        File.chmod!(token_path, 0o600)
        
        IO.puts("\n✅ Tokens saved successfully!")
        IO.puts("\n💾 Tokens saved to: #{token_path}")
        IO.puts("\n🔑 Access Token (valid for #{response["expires_in"]} seconds):")
        IO.puts("   #{String.slice(response["access_token"], 0..50)}...")
        
        IO.puts("\n🔄 Refresh Token:")
        IO.puts("   #{String.slice(response["refresh_token"], 0..30)}...")
        
        IO.puts("\n✅ You can now run the OAuth2 tests:")
        IO.puts("   mix test test/ex_llm/adapters/gemini/permissions_oauth2_test.exs")
        
      {:error, reason} ->
        IO.puts("\n❌ Failed to save tokens: #{reason}")
        System.halt(1)
    end
  end
end

# Run with command line arguments
ExchangeCode.run(System.argv())