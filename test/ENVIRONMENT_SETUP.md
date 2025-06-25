# Test Environment Setup

This guide helps you configure your environment to run all ExLLM tests successfully.

## Quick Start

1. Copy `.env.example` to `.env` and add your API keys
2. Run `source ~/.env && mix test.live` to run all tests with live APIs
3. Or run `mix test` to run only cached/mocked tests

## Provider-Specific Setup

### API Key Tests
Most provider tests require API keys. Add these to your `.env` file:

```bash
# Required for provider tests
ANTHROPIC_API_KEY=your_key_here
OPENAI_API_KEY=your_key_here
GEMINI_API_KEY=your_key_here
GROQ_API_KEY=your_key_here
MISTRAL_API_KEY=your_key_here
OPENROUTER_API_KEY=your_key_here
PERPLEXITY_API_KEY=your_key_here
XAI_API_KEY=your_key_here
```

### Bumblebee Tests (Local Models)
Bumblebee tests require local models to be downloaded:

```bash
# Option 1: Download models (requires several GB of disk space)
mix bumblebee.download

# Option 2: Skip Bumblebee tests
export BUMBLEBEE_SKIP_TESTS=true
```

### OAuth2 Tests (Google/Gemini)
OAuth2 tests require additional setup:

```bash
# 1. Set environment variables
export GOOGLE_CLIENT_ID=your_client_id
export GOOGLE_CLIENT_SECRET=your_client_secret

# 2. Run setup script
elixir scripts/setup_oauth2.exs

# 3. Follow the prompts to authenticate
# This creates .gemini_tokens file
```

### Test Cache
The test cache helps avoid rate limits and speeds up tests:

```bash
# Check cache status
mix ex_llm.cache stats

# Refresh cache (runs live API tests)
mix test.live

# Clear cache
mix ex_llm.cache clear

# Enable caching for all test runs
export EX_LLM_TEST_CACHE_ENABLED=true
```

## Common Test Failures

### "Nx.Serving not available"
- **Cause**: Bumblebee/Nx dependencies not installed
- **Fix**: Add `{:bumblebee, "~> 0.5"}` to deps or set `BUMBLEBEE_SKIP_TESTS=true`

### "API key not found"
- **Cause**: Provider API key not configured
- **Fix**: Add the required API key to `.env` file

### "OAuth2 token expired"
- **Cause**: Google OAuth2 tokens need refresh
- **Fix**: Run `elixir scripts/setup_oauth2.exs` again

### "Test cache is stale"
- **Cause**: Cache is older than 24 hours
- **Fix**: Run `mix test.live` to refresh

## Running Specific Test Categories

```bash
# Run only unit tests
mix test --exclude integration --exclude external

# Run specific provider tests
mix test.anthropic
mix test.openai
mix test.gemini

# Run with specific tags
mix test --only provider:openai
mix test --only streaming
mix test --exclude oauth2
```

## Debugging Test Failures

```bash
# Run with debug logging
export EX_LLM_LOG_LEVEL=debug
mix test

# Run a single test with details
mix test path/to/test.exs:line_number --trace

# Check which tests are excluded
mix test --exclude integration --exclude external --trace
```

## CI/CD Considerations

For CI environments:

1. Use environment variables for API keys
2. Enable test caching to reduce API calls
3. Consider using mock provider for most tests
4. Run live API tests only on main branch or releases

```yaml
# Example GitHub Actions setup
env:
  EX_LLM_TEST_CACHE_ENABLED: true
  BUMBLEBEE_SKIP_TESTS: true
  # Add API keys as secrets
```