# Test Setup Guide for ExLLM

This guide provides comprehensive instructions for setting up and running the ExLLM test suite.

## Quick Start

### Minimal Setup (1-2 Providers)

1. **Copy the test environment template:**
   ```bash
   cp .env.test.example .env.test
   ```

2. **Add at least one API key to `.env.test`:**
   ```bash
   # Recommended for core functionality testing
   OPENAI_API_KEY=your-openai-key-here
   ANTHROPIC_API_KEY=your-anthropic-key-here
   ```

3. **Run tests:**
   ```bash
   source .env.test && mix test --include integration
   ```

## Complete Test Environment Setup

### API Keys

The test suite supports testing with multiple LLM providers. Each provider requires its own API key:

| Provider | Environment Variable | How to Get API Key |
|----------|---------------------|-------------------|
| OpenAI | `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| Anthropic | `ANTHROPIC_API_KEY` | https://console.anthropic.com/settings/keys |
| Google Gemini | `GEMINI_API_KEY` | https://aistudio.google.com/app/apikey |
| Groq | `GROQ_API_KEY` | https://console.groq.com/keys |
| Mistral | `MISTRAL_API_KEY` | https://console.mistral.ai/api-keys |
| OpenRouter | `OPENROUTER_API_KEY` | https://openrouter.ai/settings/keys |
| Perplexity | `PERPLEXITY_API_KEY` | https://www.perplexity.ai/settings/api |
| X.AI | `XAI_API_KEY` | https://console.x.ai/team |

### Local Services

Some providers run locally and don't require API keys:

#### Ollama
```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Start Ollama service
ollama serve

# Pull a model for testing
ollama pull llama3.2

# Set environment variable (if not using default port)
export OLLAMA_HOST=http://localhost:11434
```

#### LM Studio
1. Download from https://lmstudio.ai
2. Start the local server (usually on port 1234)
3. Load a model in the UI
4. Set environment variable if needed:
   ```bash
   export LMSTUDIO_HOST=http://localhost:1234
   ```

### OAuth2 Setup (Gemini Advanced APIs)

For Gemini's tuned models and corpus APIs:

1. **Set OAuth2 credentials:**
   ```bash
   export GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
   export GOOGLE_CLIENT_SECRET=your-client-secret
   ```

2. **Run OAuth2 setup:**
   ```bash
   elixir scripts/setup_oauth2.exs
   ```

## Running Tests

### All Tests
```bash
mix test
```

### Integration Tests Only
```bash
mix test --include integration
```

### Specific Provider Tests
```bash
# Test a single provider
mix test.openai
mix test.anthropic
mix test.gemini

# Test local providers
mix test.local
```

### Fast Development Tests
```bash
# Excludes slow and integration tests
mix test.fast
```

### With Test Caching
```bash
# Enable caching for faster repeated test runs
export EX_LLM_TEST_CACHE_ENABLED=true
mix test --include integration

# Force live API calls (bypass cache)
MIX_RUN_LIVE=true mix test --include integration
```

## Troubleshooting

### Common Issues

#### 1. Authentication Failures
- **Symptom**: 401/403 errors in tests
- **Solution**: Verify API keys are correctly set in `.env.test`
- **Debug**: 
  ```bash
  # Check if environment variables are loaded
  echo $OPENAI_API_KEY
  ```

#### 2. Service Not Available
- **Symptom**: "Service ollama is not available" skip messages
- **Solution**: Start the required service (Ollama/LM Studio)
- **Note**: Tests will skip gracefully if services aren't running

#### 3. Missing ModelLoader for Bumblebee
- **Symptom**: Bumblebee tests fail with ModelLoader errors
- **Solution**: This is expected in test environment; tests handle it gracefully
- **Note**: ModelLoader is not started in test mode by design

#### 4. Configuration Mismatches
- **Symptom**: Tests expecting different default models
- **Solution**: Pull latest changes; configuration has been updated

### Debug Mode

Enable detailed logging:
```bash
export EX_LLM_LOG_LEVEL=debug
mix test
```

### CI/CD Configuration

For GitHub Actions or other CI systems:

1. **Add secrets for each provider:**
   - `OPENAI_API_KEY`
   - `ANTHROPIC_API_KEY`
   - etc.

2. **Use restricted API keys** with low quotas for testing

3. **Enable test caching** in CI for faster builds:
   ```yaml
   env:
     EX_LLM_TEST_CACHE_ENABLED: true
   ```

## Test Categories

Tests are organized with tags:

- `:unit` - Pure unit tests (no external dependencies)
- `:integration` - Tests requiring API calls
- `:streaming` - Streaming functionality tests
- `:vision` - Multimodal/vision tests
- `:oauth2` - OAuth2-required tests
- `:requires_service` - Local service tests
- `:slow` - Tests taking >5 seconds
- `:quota_sensitive` - Tests consuming significant API quota

## Best Practices

1. **Start with minimal providers** - You don't need all API keys to contribute
2. **Use test caching** during development to save API costs
3. **Run `mix test.fast`** for quick feedback during development
4. **Check for skipped tests** in output to understand coverage
5. **Local services are optional** - tests skip gracefully if not available

## Getting Help

- Check test output for specific error messages
- Enable debug logging for detailed information
- Review [ENVIRONMENT.md](ENVIRONMENT.md) for all configuration options
- Open an issue if you encounter persistent problems