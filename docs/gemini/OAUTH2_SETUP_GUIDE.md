# Setting Up Real Google OAuth2 Credentials for Gemini API

This guide will walk you through obtaining real OAuth2 credentials for testing the Gemini Permissions API and other OAuth2-only features.

## Prerequisites

1. A Google Account
2. A Google Cloud Project (or create a new one)
3. Gemini API enabled in your project

## Step 1: Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click on the project dropdown at the top
3. Click "New Project"
4. Enter a project name (e.g., "ExLLM Testing")
5. Click "Create"

## Step 2: Enable the Gemini API

1. In your project, go to "APIs & Services" > "Library"
2. Search for "Generative Language API" or "Gemini API"
3. Click on it and press "Enable"

## Step 3: Create OAuth2 Credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "+ CREATE CREDENTIALS" > "OAuth client ID"
3. If prompted, configure the OAuth consent screen first:
   - Choose "External" user type (for testing)
   - Fill in required fields:
     - App name: "ExLLM OAuth Test"
     - User support email: your email
     - Developer contact: your email
   - Add scopes:
     - Click "Add or Remove Scopes"
     - Add these scopes:
       - `https://www.googleapis.com/auth/cloud-platform`
       - `openid`
       - `https://www.googleapis.com/auth/userinfo.email`
   - Add your email as a test user
   - Save and continue

4. Now create the OAuth client ID:
   - Application type: "Desktop app" (easiest for CLI testing)
   - Name: "ExLLM CLI"
   - Click "Create"

5. Download the credentials JSON file
   - Click the download button next to your new OAuth client
   - Save it as `client_secret.json` in a secure location

## Step 4: Set Up Environment Variables

```bash
# Extract from the downloaded JSON file:
export GOOGLE_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="your-client-secret"

# Or for permanent setup, add to your shell profile:
echo 'export GOOGLE_CLIENT_ID="your-client-id.apps.googleusercontent.com"' >> ~/.bashrc
echo 'export GOOGLE_CLIENT_SECRET="your-client-secret"' >> ~/.bashrc
```

## Step 5: Run the OAuth2 Setup Script

```bash
# From the ex_llm directory
elixir scripts/setup_oauth2.exs
```

The script will:
1. Start a local web server on port 8080
2. Open your browser to Google's authorization page
3. After you authorize, capture the authorization code
4. Exchange it for access and refresh tokens
5. Save the tokens to `.gemini_tokens`

## Step 6: Test the OAuth2 Integration

```bash
# Run the OAuth2 permission tests
mix test test/ex_llm/adapters/gemini/permissions_oauth2_test.exs

# Or test manually in IEx:
iex -S mix

# In IEx:
{:ok, tokens} = File.read!(".gemini_tokens") |> Jason.decode!()
{:ok, result} = ExLLM.Gemini.Permissions.list_permissions(
  "tunedModels/test-model",
  oauth_token: tokens["access_token"]
)
```

## Troubleshooting

### "redirect_uri_mismatch" Error
- Make sure you're using "Desktop app" type for the OAuth client
- The redirect URI should be `http://localhost:8080/callback`

### "invalid_client" Error
- Double-check your CLIENT_ID and CLIENT_SECRET
- Make sure you're using the correct credentials from the downloaded JSON

### "access_denied" Error
- Make sure your Google account is added as a test user in the OAuth consent screen
- Try clearing browser cookies for accounts.google.com

### Token Expired
- Run `elixir scripts/refresh_oauth2_token.exs` to refresh
- Tokens expire after 1 hour

## Security Notes

1. **Never commit credentials**: The `.gemini_tokens` file is already in `.gitignore`
2. **Keep client_secret.json secure**: Don't commit this file
3. **Use environment variables**: Don't hardcode credentials
4. **Rotate credentials regularly**: Revoke and recreate if compromised

## Next Steps

Once you have OAuth2 working:
1. Test the Permissions API for managing tuned model access
2. Test the Corpus API for document management
3. Implement automatic token refresh in your application