# Environment Variables Reference

This document provides a comprehensive reference for all environment variables used by ExLLM.

## Provider Configuration

### API Keys

| Variable | Provider | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Anthropic | API key for Claude models |
| `OPENAI_API_KEY` | OpenAI | API key for GPT models |
| `GEMINI_API_KEY` or `GOOGLE_API_KEY` | Google | API key for Gemini models |
| `GROQ_API_KEY` | Groq | API key for Groq inference |
| `MISTRAL_API_KEY` | Mistral | API key for Mistral models |
| `OPENROUTER_API_KEY` | OpenRouter | API key for OpenRouter |
| `PERPLEXITY_API_KEY` | Perplexity | API key for Perplexity |
| `XAI_API_KEY` | X.AI | API key for Grok models |

### Base URLs

| Variable | Provider | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_BASE_URL` | Anthropic | `https://api.anthropic.com/v1` | Override API endpoint |
| `OPENAI_BASE_URL` | OpenAI | `https://api.openai.com/v1` | Override API endpoint |
| `GEMINI_BASE_URL` | Google | Provider default | Override API endpoint |
| `GROQ_BASE_URL` | Groq | Provider default | Override API endpoint |
| `MISTRAL_BASE_URL` | Mistral | Provider default | Override API endpoint |
| `OPENROUTER_BASE_URL` | OpenRouter | `https://openrouter.ai/api/v1` | Override API endpoint |
| `PERPLEXITY_BASE_URL` | Perplexity | Provider default | Override API endpoint |
| `XAI_BASE_URL` | X.AI | Provider default | Override API endpoint |
| `OLLAMA_HOST` or `OLLAMA_BASE_URL` | Ollama | `http://localhost:11434` | Ollama server URL |
| `LMSTUDIO_HOST` | LM Studio | `http://localhost:1234` | LM Studio server URL |

### Default Models

| Variable | Provider | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_MODEL` | Anthropic | `claude-sonnet-4-20250514` | Default model |
| `OPENAI_MODEL` | OpenAI | `gpt-4-turbo-preview` | Default model |
| `GEMINI_MODEL` | Google | Provider default | Default model |
| `GROQ_MODEL` | Groq | Provider default | Default model |
| `MISTRAL_MODEL` | Mistral | Provider default | Default model |
| `OPENROUTER_MODEL` | OpenRouter | `openai/gpt-4o-mini` | Default model |
| `PERPLEXITY_MODEL` | Perplexity | Provider default | Default model |
| `XAI_MODEL` | X.AI | Provider default | Default model |
| `OLLAMA_MODEL` | Ollama | Provider default | Default model |

### Provider-Specific

| Variable | Provider | Description |
|----------|----------|-------------|
| `OPENAI_ORGANIZATION` | OpenAI | Organization ID for API requests |
| `OPENROUTER_APP_NAME` | OpenRouter | Application name sent with requests |
| `OPENROUTER_APP_URL` | OpenRouter | Application URL sent with requests |
| `BUMBLEBEE_MODEL_PATH` | Bumblebee | Path to local model files |
| `BUMBLEBEE_DEVICE` | Bumblebee | Device for inference (`:cpu` or `:cuda`) |

## OAuth2 / Authentication

| Variable | Description |
|----------|-------------|
| `GOOGLE_CLIENT_ID` | Google OAuth2 client ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth2 client secret |
| `GOOGLE_REFRESH_TOKEN` | Google OAuth2 refresh token (auto-managed) |

## AWS / Bedrock

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_ACCESS_KEY_ID` | - | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | - | AWS secret key |
| `AWS_SESSION_TOKEN` | - | AWS session token (optional) |
| `AWS_REGION` | `us-east-1` | AWS region |
| `BEDROCK_ACCESS_KEY_ID` | Falls back to AWS | Bedrock-specific access key |
| `BEDROCK_SECRET_ACCESS_KEY` | Falls back to AWS | Bedrock-specific secret key |
| `BEDROCK_REGION` | Falls back to AWS | Bedrock-specific region |

## Testing & Development

### Test Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `EX_LLM_ENV_FILE` | `.env` | Custom .env file path |
| `EX_LLM_TEST_CACHE_ENABLED` | `false` | Enable test response caching |
| `EX_LLM_LOG_LEVEL` | `none` | Log level (debug/info/warn/error/none) |
| `MIX_RUN_LIVE` | `false` | Force live API calls in tests |

### Test Resources

| Variable | Description |
|----------|-------------|
| `TEST_TUNED_MODEL` | Tuned model ID for testing |
| `TEST_CORPUS_NAME` | Pre-existing corpus for testing |
| `TEST_DOCUMENT_NAME` | Pre-existing document for testing |

### Cache Configuration

| Variable | Description |
|----------|-------------|
| `EX_LLM_CACHE_ENABLED` | Enable/disable global cache |
| `EX_LLM_CACHE_TTL` | Cache time-to-live in seconds |
| `EX_LLM_CACHE_MAX_SIZE` | Maximum cache size |
| `EX_LLM_CACHE_STRATEGY` | Cache strategy (memory/disk/hybrid) |

### Development

| Variable | Description |
|----------|-------------|
| `HEX_API_KEY` | Hex.pm API key for publishing |
| `MOCK_RESPONSE_MODE` | Mock response mode for testing |

## Usage Examples

### Basic Setup

```bash
# Required for most providers
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GEMINI_API_KEY="AIza..."

# Optional: Custom endpoints for OpenAI-compatible providers
export OPENAI_BASE_URL="https://api.example.com/v1"
export OPENAI_MODEL="custom-model-name"
```

### Local Development

```bash
# Local model servers
export OLLAMA_HOST="http://localhost:11434"
export LMSTUDIO_HOST="http://localhost:1234"

# Enable debug logging
export EX_LLM_LOG_LEVEL="debug"

# Custom .env file
export EX_LLM_ENV_FILE=".env.local"
```

### Testing

```bash
# Enable test caching for faster tests
export EX_LLM_TEST_CACHE_ENABLED="true"

# Force live API calls
export MIX_RUN_LIVE="true"

# Test with specific resources
export TEST_TUNED_MODEL="tunedModels/my-model"
export TEST_CORPUS_NAME="corpora/test-corpus"
```

### Test Suite Setup

For running the complete test suite with all providers:

```bash
# 1. Copy the test environment template
cp .env.test.example .env.test

# 2. Edit .env.test and add your API keys
# Note: You don't need ALL keys - tests will skip providers without keys

# 3. Source the environment and run tests
source .env.test && mix test --include integration

# Or use the helper script (if available)
./scripts/run_with_env.sh mix test --include integration
```

**Quick Start for Testing**:
- Minimum requirement: At least one provider API key
- Recommended: OpenAI + Anthropic for core functionality testing
- Optional: Local services (Ollama/LM Studio) for offline testing

### OAuth2 Setup

```bash
# Required for Gemini OAuth2 APIs
export GOOGLE_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="your-client-secret"

# Run OAuth2 setup
elixir scripts/setup_oauth2.exs
```

## Best Practices

1. **Use `.env` files** for local development instead of exporting variables
2. **Never commit** API keys or secrets to version control
3. **Use provider-specific keys** when available (e.g., `BEDROCK_ACCESS_KEY_ID` instead of `AWS_ACCESS_KEY_ID`)
4. **Set reasonable defaults** in your application config
5. **Document required variables** in your project README
6. **Use the centralized `ExLLM.Environment` module** for accessing environment variables in code

## Centralized Access

All environment variables are documented and accessible through the `ExLLM.Environment` module:

```elixir
# Get API key for a provider
ExLLM.Environment.api_key_var(:openai)
# => "OPENAI_API_KEY"

# Get provider configuration
ExLLM.Environment.provider_config(:anthropic)
# => %{api_key: "sk-ant-...", base_url: "https://...", model: "claude-..."}

# Check available providers
ExLLM.Environment.available_providers()
# => [:openai, :anthropic, :gemini]
```

This ensures consistent naming and usage throughout the codebase.