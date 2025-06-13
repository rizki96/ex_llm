defmodule ExLLM.Gemini.Auth do
  @moduledoc """
  OAuth2 authentication helper for Google Gemini APIs that require user authentication.
  
  This module provides utilities for obtaining and managing OAuth2 tokens for APIs
  like the Permissions API that don't support API key authentication.
  
  ## Usage
  
      # Option 1: Service Account (recommended for servers)
      {:ok, token} = ExLLM.Gemini.Auth.get_service_account_token()
      
      # Option 2: User OAuth2 flow
      {:ok, auth_url} = ExLLM.Gemini.Auth.get_authorization_url()
      # ... user authorizes ...
      {:ok, tokens} = ExLLM.Gemini.Auth.exchange_code(auth_code)
      
      # Use with Permissions API
      ExLLM.Gemini.Permissions.list_permissions("tunedModels/my-model",
        oauth_token: token
      )
  """

  @auth_endpoint "https://accounts.google.com/o/oauth2/v2/auth"
  @token_endpoint "https://oauth2.googleapis.com/token"
  @revoke_endpoint "https://oauth2.googleapis.com/revoke"
  
  # OAuth2 scopes for Gemini API
  # Note: The specific generative-language scopes may not be valid for OAuth2
  # Using cloud-platform scope provides access to all Google Cloud APIs including Gemini
  @cloud_platform_scope "https://www.googleapis.com/auth/cloud-platform"
  @userinfo_email_scope "https://www.googleapis.com/auth/userinfo.email"
  @openid_scope "openid"
  
  # Legacy scopes (may not work with OAuth2)
  @generative_language_scope "https://www.googleapis.com/auth/generative-language"
  @tuning_scope "https://www.googleapis.com/auth/generative-language.tuning"
  @retrieval_scope "https://www.googleapis.com/auth/generative-language.retrieval"

  @type token_response :: %{
    access_token: String.t(),
    token_type: String.t(),
    expires_in: integer(),
    refresh_token: String.t() | nil,
    scope: String.t()
  }

  @type oauth_config :: %{
    client_id: String.t(),
    client_secret: String.t(),
    redirect_uri: String.t()
  }

  @doc """
  Gets the authorization URL for the OAuth2 flow.
  
  ## Options
  
  * `:client_id` - Google OAuth2 client ID (required)
  * `:redirect_uri` - Callback URL (default: "http://localhost:8080/callback")
  * `:scopes` - List of OAuth2 scopes (default: generative language scope)
  * `:access_type` - "online" or "offline" (default: "offline" for refresh tokens)
  * `:prompt` - "none", "consent", or "select_account" (default: "consent")
  * `:state` - Optional state parameter for CSRF protection
  
  ## Examples
  
      {:ok, url} = ExLLM.Gemini.Auth.get_authorization_url(
        client_id: "your-client-id",
        scopes: [:generative_language, :tuning]
      )
  """
  @spec get_authorization_url(Keyword.t()) :: {:ok, String.t()} | {:error, term()}
  def get_authorization_url(opts \\ []) do
    client_id = opts[:client_id] || System.get_env("GOOGLE_CLIENT_ID")
    
    if is_nil(client_id) do
      {:error, "client_id is required"}
    else
      params = %{
        "client_id" => client_id,
        "redirect_uri" => opts[:redirect_uri] || "http://localhost:8080/callback",
        "response_type" => "code",
        "scope" => build_scope_string(opts[:scopes] || [:generative_language]),
        "access_type" => opts[:access_type] || "offline",
        "prompt" => opts[:prompt] || "consent"
      }
      
      params = if opts[:state], do: Map.put(params, "state", opts[:state]), else: params
      
      query_string = URI.encode_query(params)
      {:ok, "#{@auth_endpoint}?#{query_string}"}
    end
  end

  @doc """
  Exchanges an authorization code for access and refresh tokens.
  
  ## Parameters
  
  * `code` - The authorization code from the OAuth2 callback
  * `opts` - Options including client credentials and redirect URI
  
  ## Examples
  
      {:ok, tokens} = ExLLM.Gemini.Auth.exchange_code(auth_code,
        client_id: "your-client-id",
        client_secret: "your-client-secret",
        redirect_uri: "http://localhost:8080/callback"
      )
  """
  @spec exchange_code(String.t(), Keyword.t()) :: {:ok, token_response()} | {:error, term()}
  def exchange_code(code, opts \\ []) do
    config = get_oauth_config(opts)
    
    body = %{
      "code" => code,
      "client_id" => config.client_id,
      "client_secret" => config.client_secret,
      "redirect_uri" => config.redirect_uri,
      "grant_type" => "authorization_code"
    }
    
    case Req.post(@token_endpoint, form: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, %{
          access_token: response["access_token"],
          token_type: response["token_type"],
          expires_in: response["expires_in"],
          refresh_token: response["refresh_token"],
          scope: response["scope"]
        }}
        
      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, message: body["error_description"] || body["error"]}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refreshes an access token using a refresh token.
  
  ## Parameters
  
  * `refresh_token` - The refresh token
  * `opts` - Options including client credentials
  
  ## Examples
  
      {:ok, new_token} = ExLLM.Gemini.Auth.refresh_token(stored_refresh_token)
  """
  @spec refresh_token(String.t(), Keyword.t()) :: {:ok, token_response()} | {:error, term()}
  def refresh_token(refresh_token, opts \\ []) do
    config = get_oauth_config(opts)
    
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
          token_type: response["token_type"],
          expires_in: response["expires_in"],
          scope: response["scope"]
        }}
        
      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, message: body["error_description"] || body["error"]}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Revokes a token (access token or refresh token).
  
  ## Parameters
  
  * `token` - The token to revoke
  * `opts` - Options (currently unused)
  
  ## Examples
  
      :ok = ExLLM.Gemini.Auth.revoke_token(access_token)
  """
  @spec revoke_token(String.t(), Keyword.t()) :: :ok | {:error, term()}
  def revoke_token(token, _opts \\ []) do
    case Req.post(@revoke_endpoint, form: %{"token" => token}) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, "Failed to revoke token: HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets a service account token using Application Default Credentials.
  
  This requires either:
  1. GOOGLE_APPLICATION_CREDENTIALS environment variable pointing to a service account JSON file
  2. Running on Google Cloud with appropriate service account attached
  3. Using gcloud auth application-default login
  
  ## Options
  
  * `:scopes` - List of OAuth2 scopes (default: generative language scope)
  
  ## Examples
  
      # Requires Goth library to be added to your project
      {:ok, token} = ExLLM.Gemini.Auth.get_service_account_token()
  """
  @spec get_service_account_token(Keyword.t()) :: {:ok, String.t()} | {:error, term()}
  def get_service_account_token(opts \\ []) do
    # This is a simplified example - in production, use the Goth library
    {:error, """
    Service account authentication requires the Goth library.
    
    Add to your mix.exs:
        {:goth, "~> 1.4"}
    
    Then configure:
        config :goth,
          json: File.read!("path/to/service-account-key.json")
    
    Or set GOOGLE_APPLICATION_CREDENTIALS environment variable.
    """}
  end

  @doc """
  Validates if a token is still valid by checking with Google's tokeninfo endpoint.
  
  ## Parameters
  
  * `access_token` - The access token to validate
  
  ## Returns
  
  * `{:ok, token_info}` - Token is valid, returns info including expiry
  * `{:error, reason}` - Token is invalid or expired
  """
  @spec validate_token(String.t()) :: {:ok, map()} | {:error, term()}
  def validate_token(access_token) do
    url = "https://oauth2.googleapis.com/tokeninfo?access_token=#{URI.encode(access_token)}"
    
    case Req.get(url) do
      {:ok, %{status: 200, body: info}} ->
        {:ok, %{
          scope: info["scope"],
          expires_in: info["expires_in"],
          access_type: info["access_type"]
        }}
        
      {:ok, %{status: _status, body: body}} ->
        {:error, body["error_description"] || body["error"] || "Invalid token"}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Simple CLI flow for obtaining OAuth2 tokens.
  
  This starts a local web server to receive the OAuth2 callback.
  Useful for CLI tools and development.
  
  ## Options
  
  * `:port` - Local server port (default: 8080)
  * `:client_id` - Google OAuth2 client ID
  * `:client_secret` - Google OAuth2 client secret
  * `:scopes` - List of OAuth2 scopes
  
  ## Examples
  
      {:ok, tokens} = ExLLM.Gemini.Auth.cli_flow(
        client_id: "your-client-id",
        client_secret: "your-client-secret"
      )
  """
  @spec cli_flow(Keyword.t()) :: {:ok, token_response()} | {:error, term()}
  def cli_flow(opts \\ []) do
    port = opts[:port] || 8080
    redirect_uri = "http://localhost:#{port}/callback"
    
    with {:ok, auth_url} <- get_authorization_url(Keyword.put(opts, :redirect_uri, redirect_uri)) do
      IO.puts("\nPlease visit this URL to authorize the application:")
      IO.puts(auth_url)
      IO.puts("\nWaiting for authorization...")
      
      # In a real implementation, you would:
      # 1. Start a local web server on the specified port
      # 2. Wait for the callback with the authorization code
      # 3. Exchange the code for tokens
      # 4. Shut down the local server
      
      {:error, "CLI flow not fully implemented. See documentation for manual steps."}
    end
  end

  # Private functions

  defp get_oauth_config(opts) do
    %{
      client_id: opts[:client_id] || System.get_env("GOOGLE_CLIENT_ID"),
      client_secret: opts[:client_secret] || System.get_env("GOOGLE_CLIENT_SECRET"),
      redirect_uri: opts[:redirect_uri] || "http://localhost:8080/callback"
    }
  end

  defp build_scope_string(scopes) when is_list(scopes) do
    scopes
    |> Enum.map(&scope_to_url/1)
    |> Enum.join(" ")
  end

  defp scope_to_url(:cloud_platform), do: @cloud_platform_scope
  defp scope_to_url(:userinfo_email), do: @userinfo_email_scope
  defp scope_to_url(:openid), do: @openid_scope
  # Legacy scopes (may not work)
  defp scope_to_url(:generative_language), do: @generative_language_scope
  defp scope_to_url(:tuning), do: @tuning_scope
  defp scope_to_url(:retrieval), do: @retrieval_scope
  defp scope_to_url(url) when is_binary(url), do: url
end