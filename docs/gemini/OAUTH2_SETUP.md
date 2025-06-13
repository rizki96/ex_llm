# Google Authentication for Gemini API

## ⚠️ IMPORTANT: Authentication Policy Change (September 2024)

**As of September 30, 2024, Google changed Gemini API authentication requirements:**

> **"OAuth authentication is no longer required. New projects should use API key authentication instead."**

## 🚨 Do You Need This Guide?

**Most users should NOT follow this guide.** Instead, use the simple API key setup:

1. Visit [Google AI Studio](https://aistudio.google.com/app/apikey)  
2. Create an API key  
3. Set `GEMINI_API_KEY="your-key"` environment variable  
4. Done! ✅

**Only follow this OAuth2 guide if you specifically need:**
- Permissions API (tuned model access control)
- Corpus Management API (user document collections)  
- Question Answering with user corpora

---

## 🔄 Updated Authentication Guide

### ✅ Primary Method: API Key Authentication (Recommended)

**For 95% of Gemini APIs**, use API key authentication:

1. Visit [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Create an API key for your project
3. Set environment variable: `export GEMINI_API_KEY="your-api-key"`
4. Use in requests: `?key=YOUR_API_KEY` or `X-Goog-Api-Key` header

### ⚠️ When OAuth2 is Still Required

OAuth2 is **only needed** for specific APIs that manage user identity and permissions:

- **Permissions API** (tuned model access control)
- **Corpus Management API** (user-specific document collections)
- **Some Question Answering** operations (when using semantic retrieval with user corpora)

## OAuth2 Setup (For Permission Management Only)

**Only follow this section if you need to use permission management APIs.**

## Prerequisites

1. A Google Cloud Project
2. Gemini API enabled in your project
3. OAuth2 credentials configured

## Step 1: Create OAuth2 Credentials

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to "APIs & Services" > "Credentials"
3. Click "Create Credentials" > "OAuth client ID"
4. Choose application type:
   - **Web application** (for server-side apps)
   - **Desktop app** (for CLI tools)
5. Add authorized redirect URIs:
   - For local development: `http://localhost:8080/callback`
   - For web apps: `https://yourdomain.com/auth/callback`
6. Download the client configuration JSON

## Step 2: OAuth2 Scopes

For OAuth2 authentication with Google APIs, use these scopes:

```elixir
# Full access to Google Cloud APIs (including Gemini)
"https://www.googleapis.com/auth/cloud-platform"

# User identification
"openid"
"https://www.googleapis.com/auth/userinfo.email"
```

**Note**: The specific `generative-language` scopes may not be valid for OAuth2 flows. The `cloud-platform` scope provides access to all Google Cloud APIs, including the Gemini API.

If you're using a service account instead of OAuth2:
- Service accounts use different authentication mechanisms
- They don't require user interaction
- They can use API-specific scopes

## Step 3: Authentication Flow

### Option A: Using Google Auth Library (Recommended)

```elixir
# In mix.exs, add:
{:goth, "~> 1.4"}  # Google auth library for Elixir

# Configuration
config :goth,
  json: File.read!("path/to/service-account-key.json")
```

### Option B: Manual OAuth2 Flow

1. **Authorization URL**:
```
https://accounts.google.com/o/oauth2/v2/auth?
  client_id=YOUR_CLIENT_ID&
  redirect_uri=http://localhost:8080/callback&
  response_type=code&
  scope=https://www.googleapis.com/auth/generative-language&
  access_type=offline&
  prompt=consent
```

2. **Exchange code for tokens**:
```
POST https://oauth2.googleapis.com/token
Content-Type: application/x-www-form-urlencoded

code=AUTHORIZATION_CODE&
client_id=YOUR_CLIENT_ID&
client_secret=YOUR_CLIENT_SECRET&
redirect_uri=http://localhost:8080/callback&
grant_type=authorization_code
```

3. **Response**:
```json
{
  "access_token": "ya29.a0AfH6SMBx...",
  "expires_in": 3599,
  "refresh_token": "1//0gLu8Fh...",
  "scope": "https://www.googleapis.com/auth/generative-language",
  "token_type": "Bearer"
}
```

## Step 4: Using Tokens with ExLLM

### Service Account (Recommended for Server Apps)

```elixir
# 1. Create a service account in Google Cloud Console
# 2. Download the JSON key file
# 3. Use with ExLLM:

defmodule MyApp.GeminiAuth do
  def get_oauth_token do
    # Using Goth library
    {:ok, %{token: token}} = Goth.fetch(MyApp.Goth)
    token
  end
end

# Use with Permissions API
{:ok, permissions} = ExLLM.Gemini.Permissions.list_permissions(
  "tunedModels/my-model",
  oauth_token: MyApp.GeminiAuth.get_oauth_token()
)
```

### User Account (For User-Facing Apps)

```elixir
# Store tokens securely after OAuth flow
defmodule MyApp.TokenStore do
  def get_user_token(user_id) do
    # Retrieve from secure storage
    %{
      access_token: "ya29...",
      refresh_token: "1//...",
      expires_at: ~U[2024-01-15 10:00:00Z]
    }
  end
  
  def refresh_if_needed(token_data) do
    if DateTime.compare(DateTime.utc_now(), token_data.expires_at) == :gt do
      # Refresh the token
      refresh_token(token_data.refresh_token)
    else
      token_data.access_token
    end
  end
end
```

## Step 5: Token Refresh

Access tokens expire after 1 hour. Use the refresh token to get new access tokens:

```elixir
defmodule MyApp.OAuth2 do
  def refresh_token(refresh_token) do
    body = %{
      refresh_token: refresh_token,
      client_id: System.get_env("GOOGLE_CLIENT_ID"),
      client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
      grant_type: "refresh_token"
    }
    
    case Req.post("https://oauth2.googleapis.com/token", json: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, %{
          access_token: response["access_token"],
          expires_in: response["expires_in"]
        }}
      error ->
        {:error, error}
    end
  end
end
```

## Quick Start Examples

### 1. Service Account Flow (Simplest for Backend)

```bash
# 1. Create service account and download JSON key
# 2. Set environment variable
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account-key.json"
```

```elixir
# Install goth
{:goth, "~> 1.4"}

# In your application
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Goth, name: MyApp.Goth}
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

# Get token
{:ok, %{token: token}} = Goth.fetch(MyApp.Goth)
```

### 2. OAuth2 Web Flow

```elixir
# Using ueberauth and ueberauth_google
{:ueberauth, "~> 0.10"},
{:ueberauth_google, "~> 0.12"}

# Config
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [
      default_scope: "email https://www.googleapis.com/auth/generative-language"
    ]}
  ]

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
```

### 3. CLI Tool Flow

For CLI tools, you can use a simplified flow:

```elixir
defmodule MyApp.CLI.Auth do
  @auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  
  def authenticate do
    # 1. Generate auth URL
    auth_url = build_auth_url()
    IO.puts("Visit this URL to authorize: #{auth_url}")
    
    # 2. Start local server to receive callback
    {:ok, code} = receive_callback()
    
    # 3. Exchange for tokens
    {:ok, tokens} = exchange_code(code)
    
    # 4. Save tokens
    save_tokens(tokens)
  end
end
```

## Testing with OAuth2

For testing, you can:

1. Use a service account (recommended)
2. Create a test user with limited permissions
3. Mock the OAuth2 flow in tests

```elixir
# In test config
config :ex_llm, :oauth2_token, "test-token-123"

# In test
setup do
  # Mock OAuth2 token
  :ok
end
```

## Security Best Practices

1. **Never commit credentials** to version control
2. **Use environment variables** or secure vaults for secrets
3. **Implement token refresh** before expiration
4. **Limit OAuth2 scopes** to minimum required
5. **Use service accounts** for server applications
6. **Encrypt stored tokens** if saving user tokens
7. **Implement proper token revocation** when users sign out

## Troubleshooting

### Common Errors

1. **"API keys are not supported by this API"**
   - You're using an API key instead of OAuth2 token
   - Solution: Implement OAuth2 flow

2. **"Request had insufficient authentication scopes"**
   - Add required scopes to your OAuth2 request
   - For permissions: `https://www.googleapis.com/auth/generative-language.tuning`

3. **"The access token has expired"**
   - Implement automatic token refresh
   - Tokens expire after 1 hour

4. **"Invalid client"**
   - Check client ID and secret
   - Ensure redirect URI matches configuration

## Resources

- [Google OAuth2 Documentation](https://developers.google.com/identity/protocols/oauth2)
- [Google Auth Library for Elixir (Goth)](https://github.com/peburrows/goth)
- [Ueberauth Google Strategy](https://github.com/ueberauth/ueberauth_google)
- [Google Cloud Console](https://console.cloud.google.com/)