# OAuth2 Testing Guide

## Overview

This guide covers OAuth2 testing in ExLLM, specifically for APIs that require OAuth2 authentication rather than API keys. Currently, this applies to Gemini's advanced APIs like Permissions, Corpus Management, and Question Answering.

## Required Pattern: OAuth2TestCase

**MANDATORY**: All OAuth2 tests MUST use `ExLLM.Testing.OAuth2TestCase` to ensure consistent token handling and automatic refresh.

### Basic Usage

```elixir
defmodule MyApp.OAuth2Test do
  use ExLLM.Testing.OAuth2TestCase, timeout: 300_000
  
  @moduletag :my_oauth2_feature
  
  describe "OAuth2 functionality" do
    test "performs OAuth2 operation", %{oauth_token: token} do
      # Your test logic here
      # Token is automatically provided and refreshed if needed
      {:ok, result} = MyProvider.oauth_operation(token: token)
      assert result.success
    end
  end
end
```

### What OAuth2TestCase Provides

**Automatic Token Management:**
- Attempts to refresh expired tokens before running tests
- Provides `oauth_token` in test context if available
- Skips entire test module if OAuth2 is unavailable
- Handles cleanup of OAuth2 resources after tests

**Proper Test Tagging:**
- Automatically tags tests with `:oauth2`
- Sets appropriate timeout (default 300 seconds)
- Enables eventual consistency helpers for OAuth2 APIs

**Helper Functions:**
- `gemini_api_error?(result, status)` - Check for specific API errors
- `resource_not_found?(result)` - Check if resource doesn't exist
- `unique_name(prefix)` - Generate unique resource names

## OAuth2 Setup Requirements

### 1. Google OAuth2 Credentials

You need Google OAuth2 credentials to run OAuth2 tests:

```bash
# Required environment variables
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
```

### 2. Initial OAuth2 Setup

Run the setup script to perform the initial OAuth2 flow:

```bash
# One-time setup to get initial tokens
elixir scripts/setup_oauth2.exs
```

This creates a `.gemini_tokens` file with your access and refresh tokens.

### 3. Automatic Token Refresh

OAuth2TestCase automatically refreshes tokens when:
- OAuth2 credentials are present in environment
- `.gemini_tokens` file exists
- Current token is expired or about to expire

The refresh happens transparently during test setup.

## OAuth2 Test Structure

### File Organization

```
test/ex_llm/providers/gemini/
├── oauth2_apis_test.exs              # Main OAuth2 API tests
├── permissions_oauth2_test.exs       # Permissions API tests
└── oauth2/
    ├── corpus_management_test.exs    # Corpus Management tests
    ├── document_management_test.exs  # Document Management tests
    └── qa_test.exs                   # Question Answering tests
```

### Test Module Template

```elixir
defmodule ExLLM.Providers.Gemini.MyOAuth2Test do
  use ExLLM.Testing.OAuth2TestCase, timeout: 300_000
  
  alias ExLLM.Providers.Gemini.MyAPI
  
  @moduletag :my_oauth2_feature
  @moduletag :gemini_oauth2
  
  describe "My OAuth2 API" do
    test "creates resource", %{oauth_token: token} do
      resource_name = unique_name("test-resource")
      
      # Create resource
      assert {:ok, resource} = MyAPI.create_resource(
        resource_name,
        %{description: "Test resource"},
        oauth_token: token
      )
      
      # Verify resource was created
      assert resource.name == resource_name
      assert resource.description == "Test resource"
      
      # Cleanup is handled automatically by OAuth2TestCase
    end
    
    test "handles resource not found", %{oauth_token: token} do
      result = MyAPI.get_resource("non-existent", oauth_token: token)
      assert resource_not_found?(result)
    end
    
    test "handles API errors", %{oauth_token: token} do
      # Test with invalid parameters
      result = MyAPI.create_resource("", %{}, oauth_token: token)
      assert gemini_api_error?(result, 400)
    end
  end
end
```

## Running OAuth2 Tests

### Local Development

```bash
# Run all OAuth2 tests (requires OAuth2 setup)
mix test.oauth2

# Run specific OAuth2 test file
mix test test/ex_llm/providers/gemini/oauth2_apis_test.exs

# Run with live API calls (includes OAuth2)
mix test --include oauth2 --include live_api

# Debug OAuth2 token refresh
EX_LLM_LOG_LEVEL=debug mix test.oauth2
```

### CI/CD Environment

OAuth2 tests are excluded by default in CI/CD unless OAuth2 credentials are available:

```bash
# CI/CD with OAuth2 credentials
GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... mix test --include oauth2
```

## Troubleshooting

### Common Issues

**1. Tests Skipped - "OAuth2 not available"**
```
Solution: Ensure GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET are set and .gemini_tokens exists
Run: elixir scripts/setup_oauth2.exs
```

**2. Token Refresh Failed**
```
Error: OAuth refresh failed: invalid_grant
Solution: Re-run setup script to get fresh tokens
Run: elixir scripts/setup_oauth2.exs
```

**3. API Quota Exceeded**
```
Error: 429 Too Many Requests
Solution: OAuth2 tests include aggressive cleanup and rate limiting
Wait a few minutes and retry
```

**4. Resource Already Exists**
```
Error: 409 Conflict - resource already exists
Solution: OAuth2TestCase uses unique_name() to avoid conflicts
Check for leftover test resources and clean up manually if needed
```

### Debug Mode

Enable debug logging to see OAuth2 token refresh details:

```bash
export EX_LLM_LOG_LEVEL=debug
mix test.oauth2
```

This shows:
- Token refresh attempts
- API request/response details
- Resource cleanup operations

### Manual Token Refresh

If automatic refresh fails, manually refresh tokens:

```bash
# Manual token refresh
elixir scripts/refresh_oauth2_token.exs

# Check token status
elixir -e "
tokens = File.read!('.gemini_tokens') |> Jason.decode!()
IO.inspect(tokens, label: 'Current tokens')
"
```

## Migration from Old Patterns

### Before (Incorrect Pattern)

```elixir
# DON'T DO THIS - Old pattern without automatic refresh
defmodule MyOAuth2Test do
  use ExUnit.Case, async: false
  
  setup do
    case GeminiOAuth2Helper.get_valid_token() do
      {:ok, token} -> {:ok, oauth_token: token}
      _ -> {:ok, oauth_token: nil}
    end
  end
  
  test "oauth test", %{oauth_token: token} do
    # Test logic
  end
end
```

### After (Correct Pattern)

```elixir
# DO THIS - New pattern with automatic refresh
defmodule MyOAuth2Test do
  use ExLLM.Testing.OAuth2TestCase
  
  test "oauth test", %{oauth_token: token} do
    # Test logic - token is automatically refreshed if needed
  end
end
```

### Migration Steps

1. **Replace test case usage:**
   ```elixir
   # Change this:
   use ExUnit.Case, async: false
   
   # To this:
   use ExLLM.Testing.OAuth2TestCase
   ```

2. **Remove manual setup:**
   ```elixir
   # Remove manual OAuth2 setup code:
   setup do
     case GeminiOAuth2Helper.get_valid_token() do
       {:ok, token} -> {:ok, oauth_token: token}
       _ -> {:ok, oauth_token: nil}
     end
   end
   ```

3. **Remove manual skip logic:**
   ```elixir
   # Remove manual skip conditions:
   if GeminiOAuth2Helper.oauth_available?() do
     @moduletag :oauth2
   else
     @moduletag :skip
   end
   ```

4. **Use provided helper functions:**
   ```elixir
   # Use OAuth2TestCase helpers:
   assert gemini_api_error?(result, 404)
   assert resource_not_found?(result)
   resource_name = unique_name("test-resource")
   ```

## Best Practices

### Resource Management

```elixir
test "resource lifecycle", %{oauth_token: token} do
  # Use unique names to avoid conflicts
  resource_name = unique_name("test-resource")
  
  # Create resource
  {:ok, resource} = MyAPI.create_resource(resource_name, %{}, oauth_token: token)
  
  # Test operations
  {:ok, updated} = MyAPI.update_resource(resource.name, %{new_field: "value"}, oauth_token: token)
  
  # Cleanup is handled automatically by OAuth2TestCase
  # But you can also clean up explicitly if needed:
  MyAPI.delete_resource(resource.name, oauth_token: token)
end
```

### Error Handling

```elixir
test "handles various error conditions", %{oauth_token: token} do
  # Test 404 Not Found
  result = MyAPI.get_resource("non-existent", oauth_token: token)
  assert resource_not_found?(result)
  
  # Test 400 Bad Request
  result = MyAPI.create_resource("", %{}, oauth_token: token)
  assert gemini_api_error?(result, 400)
  
  # Test 403 Forbidden (if applicable)
  result = MyAPI.restricted_operation(oauth_token: "invalid-token")
  assert gemini_api_error?(result, 403)
end
```

### Eventual Consistency

OAuth2 APIs often have eventual consistency. Use the provided helpers:

```elixir
test "handles eventual consistency", %{oauth_token: token} do
  # Create resource
  {:ok, resource} = MyAPI.create_resource(unique_name("test"), %{}, oauth_token: token)
  
  # Wait for resource to be available
  assert_eventually(fn ->
    case MyAPI.get_resource(resource.name, oauth_token: token) do
      {:ok, found_resource} -> found_resource.status == "active"
      _ -> false
    end
  end, eventual_consistency_timeout())
end
```

## Future Enhancements

The OAuth2 testing infrastructure is designed to support multiple providers:

- **Google/Gemini**: Currently supported
- **Microsoft Azure**: Planned support
- **GitHub**: Planned support
- **Generic OAuth2**: Configurable endpoints

When additional providers are added, the same OAuth2TestCase pattern will work with provider-specific configuration.
