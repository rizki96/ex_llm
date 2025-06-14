#!/usr/bin/env elixir

# OAuth2 Setup Script for Gemini API Permission Testing
# 
# This script helps you set up OAuth2 authentication for testing
# the Permissions API and other OAuth2-only features.
#
# Usage: elixir scripts/setup_oauth2.exs

Mix.install([
  {:req, "~> 0.5.0"},
  {:jason, "~> 1.4"},
  {:plug, "~> 1.15"},
  {:plug_cowboy, "~> 2.6"}
])

defmodule OAuth2Setup do
  @auth_endpoint "https://accounts.google.com/o/oauth2/v2/auth"
  @token_endpoint "https://oauth2.googleapis.com/token"
  @token_file ".gemini_tokens"
  @redirect_port 8080
  @redirect_uri "http://localhost:#{@redirect_port}/callback"
  
  # Required scopes for Gemini API OAuth2
  @scopes [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/generative-language.tuning",
    "https://www.googleapis.com/auth/generative-language.retriever",
    "openid",
    "https://www.googleapis.com/auth/userinfo.email"
  ]

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
    IO.puts("\n🔐 Gemini OAuth2 Setup")
    IO.puts("=" <> String.duplicate("=", 50))
    IO.puts("\n⚠️  Note: Most Gemini APIs work with API keys.")
    IO.puts("   OAuth2 is only needed for:")
    IO.puts("   - Permissions API (tuned model access control)")
    IO.puts("   - Corpus Management API")
    IO.puts("")
    
    # Load environment variables from .env file if present
    load_env_file()
    
    # Check if we have credentials
    if !System.get_env("GOOGLE_CLIENT_ID") || !System.get_env("GOOGLE_CLIENT_SECRET") do
      IO.puts("\n📋 First Time Setup Instructions:")
      IO.puts("1. Go to https://console.cloud.google.com/")
      IO.puts("2. Create a new project or select existing")
      IO.puts("3. Enable the Generative Language API")
      IO.puts("4. Go to APIs & Services > Credentials")
      IO.puts("5. Create OAuth 2.0 Client ID (Desktop app type)")
      IO.puts("6. Download the credentials JSON file")
      IO.puts("7. Run: elixir scripts/extract_oauth_creds.exs path/to/downloaded.json")
      IO.puts("\nSee docs/gemini/OAUTH2_SETUP_GUIDE.md for detailed instructions.\n")
    end
    
    case setup_oauth2() do
      {:ok, tokens} ->
        IO.puts("\n✅ OAuth2 setup successful!")
        display_tokens(tokens)
        
      {:error, reason} ->
        IO.puts("\n❌ Setup failed: #{reason}")
        System.halt(1)
    end
  end

  defp setup_oauth2 do
    with {:ok, config} <- get_oauth_config(),
         {:ok, auth_code} <- get_authorization_code(config),
         {:ok, tokens} <- exchange_code_for_tokens(auth_code, config),
         :ok <- save_tokens(tokens) do
      {:ok, tokens}
    end
  end

  defp get_oauth_config do
    IO.puts("\n📋 OAuth2 Configuration")
    IO.puts("You'll need OAuth2 credentials from Google Cloud Console.")
    IO.puts("Create them at: https://console.cloud.google.com/apis/credentials")
    IO.puts("")
    
    client_id = get_env_or_ask("GOOGLE_CLIENT_ID", "Enter your OAuth2 Client ID")
    client_secret = get_env_or_ask("GOOGLE_CLIENT_SECRET", "Enter your OAuth2 Client Secret")
    
    {:ok, %{
      client_id: client_id,
      client_secret: client_secret
    }}
  end

  defp get_env_or_ask(env_var, prompt) do
    case System.get_env(env_var) do
      nil ->
        case IO.gets("#{prompt}: ") do
          :eof ->
            IO.puts("\n❌ Cannot read input in non-interactive mode.")
            IO.puts("   Please set environment variables:")
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

  defp get_authorization_code(config) do
    # Generate a random state for security
    state = :crypto.strong_rand_bytes(16) |> Base.encode16()
    
    # Build authorization URL
    auth_params = %{
      "client_id" => config.client_id,
      "redirect_uri" => @redirect_uri,
      "response_type" => "code",
      "scope" => Enum.join(@scopes, " "),
      "access_type" => "offline",
      "prompt" => "consent",
      "state" => state
    }
    
    auth_url = "#{@auth_endpoint}?#{URI.encode_query(auth_params)}"
    
    IO.puts("\n🌐 Starting local server on port #{@redirect_port}...")
    
    # Start a simple web server to receive the callback
    {:ok, code_ref} = Agent.start_link(fn -> nil end)
    
    # Configure Plug router
    defmodule CallbackRouter do
      use Plug.Router
      
      plug :match
      plug Plug.Parsers, parsers: [:urlencoded]
      plug :dispatch
      
      def init(opts), do: opts
      
      def call(conn, opts) do
        conn = assign(conn, :code_ref, opts[:code_ref])
        super(conn, opts)
      end
      
      get "/callback" do
        code = conn.params["code"]
        state = conn.params["state"]
        
        if code do
          Agent.update(conn.assigns.code_ref, fn _ -> {code, state} end)
          
          html = """
          <html>
          <head><title>OAuth2 Success</title></head>
          <body style="font-family: Arial; text-align: center; padding: 50px;">
            <h1 style="color: green;">✅ Authorization Successful!</h1>
            <p>You can close this window and return to your terminal.</p>
            <script>setTimeout(() => window.close(), 3000);</script>
          </body>
          </html>
          """
          
          conn
          |> put_resp_content_type("text/html")
          |> send_resp(200, html)
        else
          error = conn.params["error"] || "Unknown error"
          
          html = """
          <html>
          <head><title>OAuth2 Error</title></head>
          <body style="font-family: Arial; text-align: center; padding: 50px;">
            <h1 style="color: red;">❌ Authorization Failed</h1>
            <p>Error: #{error}</p>
          </body>
          </html>
          """
          
          conn
          |> put_resp_content_type("text/html")
          |> send_resp(400, html)
        end
      end
      
      match _ do
        send_resp(conn, 404, "Not found")
      end
    end
    
    # Start the server
    {:ok, server_pid} = Plug.Cowboy.http(CallbackRouter, [code_ref: code_ref], port: @redirect_port)
    
    IO.puts("✓ Server started!")
    IO.puts("\n🔗 Please visit this URL to authorize:")
    IO.puts("\n#{auth_url}\n")
    IO.puts("Waiting for authorization...")
    
    # Wait for the authorization code
    wait_for_code(code_ref, state)
  end

  defp wait_for_code(code_ref, expected_state, attempts \\ 0) do
    if attempts > 60 do  # 1 minute timeout
      {:error, "Timeout waiting for authorization"}
    else
      case Agent.get(code_ref, & &1) do
        nil ->
          :timer.sleep(1000)
          wait_for_code(code_ref, expected_state, attempts + 1)
          
        {code, received_state} ->
          # Stop the agent
          Agent.stop(code_ref)
          
          # Stop the web server
          :timer.sleep(100)  # Give time for response to be sent
          
          # Verify state matches
          if received_state == expected_state do
            IO.puts("\n✓ Authorization code received!")
            {:ok, code}
          else
            {:error, "State mismatch - possible CSRF attack"}
          end
      end
    end
  end

  defp exchange_code_for_tokens(code, config) do
    IO.puts("\n🔄 Exchanging authorization code for tokens...")
    
    body = %{
      "code" => code,
      "client_id" => config.client_id,
      "client_secret" => config.client_secret,
      "redirect_uri" => @redirect_uri,
      "grant_type" => "authorization_code"
    }
    
    case Req.post(@token_endpoint, form: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, %{
          access_token: response["access_token"],
          refresh_token: response["refresh_token"],
          expires_in: response["expires_in"],
          token_type: response["token_type"],
          scope: response["scope"]
        }}
        
      {:ok, %{status: status, body: body}} ->
        {:error, "Token exchange failed (#{status}): #{inspect(body)}"}
        
      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp save_tokens(tokens) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    
    token_data = %{
      "access_token" => tokens.access_token,
      "refresh_token" => tokens.refresh_token,
      "expires_in" => tokens.expires_in,
      "token_type" => tokens.token_type,
      "scope" => tokens.scope,
      "created_at" => timestamp,
      "expires_at" => DateTime.utc_now() 
        |> DateTime.add(tokens.expires_in, :second) 
        |> DateTime.to_iso8601(),
      "original_created_at" => timestamp
    }
    
    token_path = Path.join(File.cwd!(), @token_file)
    
    case File.write(token_path, Jason.encode!(token_data, pretty: true)) do
      :ok ->
        IO.puts("\n💾 Tokens saved to: #{token_path}")
        # Set restrictive permissions
        File.chmod!(token_path, 0o600)
        :ok
      {:error, reason} ->
        {:error, "Failed to save tokens: #{reason}"}
    end
  end

  defp display_tokens(tokens) do
    IO.puts("\n🎉 OAuth2 Setup Complete!")
    IO.puts("=" <> String.duplicate("=", 50))
    
    IO.puts("\n🔑 Access Token (valid for #{tokens.expires_in} seconds):")
    IO.puts("   #{String.slice(tokens.access_token, 0..50)}...")
    
    IO.puts("\n🔄 Refresh Token (use to get new access tokens):")
    IO.puts("   #{String.slice(tokens.refresh_token, 0..30)}...")
    
    IO.puts("\n📋 Token Details:")
    IO.puts("   Type: #{tokens.token_type}")
    IO.puts("   Expires in: #{div(tokens.expires_in, 60)} minutes")
    IO.puts("   Scopes: #{tokens.scope}")
    
    IO.puts("\n✅ Next Steps:")
    IO.puts("   1. Run the OAuth2 tests:")
    IO.puts("      mix test test/ex_llm/adapters/gemini/permissions_oauth2_test.exs")
    IO.puts("")
    IO.puts("   2. When the token expires, refresh it:")
    IO.puts("      elixir scripts/refresh_oauth2_token.exs")
    IO.puts("")
    IO.puts("   3. Test the token manually:")
    IO.puts("""
    
    iex> {:ok, tokens} = File.read!(".gemini_tokens") |> Jason.decode!()
    iex> {:ok, perms} = ExLLM.Gemini.Permissions.list_permissions(
    ...>   "tunedModels/test-model",
    ...>   oauth_token: tokens["access_token"]
    ...> )
    """)
    
    IO.puts("\n⚠️  Security Note:")
    IO.puts("   - The .gemini_tokens file contains sensitive data")
    IO.puts("   - It's already added to .gitignore") 
    IO.puts("   - File permissions set to 600 (owner read/write only)")
  end
end

# Run the setup
OAuth2Setup.run()