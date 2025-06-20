# ExLLM Test Suite

This directory contains comprehensive tests for the ExLLM library, covering all providers, features, and integration scenarios. The test suite uses intelligent caching for 25x faster integration tests and is organized following the layered architecture pattern.

## Test Structure

The test suite is organized following the ExLLM layered architecture:

### Core Library Tests
- **Location**: `test/ex_llm/core/*_test.exs`
- **Purpose**: Test core ExLLM functionality (sessions, contexts, costs, embeddings, etc.)
- **Run by default**: Always executed in local development
- **Requirements**: No API keys needed

### Provider Tests
- **Location**: `test/ex_llm/providers/`
- **Structure**:
  - `*_unit_test.exs` - Unit tests without API calls
  - `*_integration_test.exs` - Integration tests with real APIs
  - Provider-specific subdirectories (e.g., `gemini/` for Gemini API tests)
- **Requirements**: Integration tests require API keys

### Infrastructure Tests
- **Location**: `test/ex_llm/infrastructure/`
- **Purpose**: Test infrastructure components (circuit breakers, config, streaming, etc.)
- **Run by default**: Always executed

### Testing Framework Tests
- **Location**: `test/ex_llm/testing/`
- **Purpose**: Test the testing infrastructure itself (caching, helpers, etc.)

### Integration Tests
- **Location**: `test/integration/`
- **Purpose**: End-to-end integration tests for complete workflows
- **Tagged with**: `:integration` and excluded by default
- **Requirements**: May require API keys depending on the test

## Running Tests

### Quick Start

```bash
# Run all tests (excludes integration/external by default)
mix test

# Run with coverage
mix test --cover

# Run fast tests only (excludes slow tests)
mix test.fast
```

### Test Categories

#### By Test Type
```bash
# Unit tests only (no API calls)
mix test.unit

# Integration tests (requires API keys)
mix test.integration

# External tests (calls external services)
mix test.external

# Live API tests
mix test.live_api

# Local-only tests (no external calls)
mix test.local_only
```

#### By Provider (24 Mix Aliases)
```bash
# Individual providers
mix test.anthropic      # Anthropic Claude tests
mix test.openai         # OpenAI GPT tests  
mix test.gemini         # Google Gemini tests
mix test.groq           # Groq tests
mix test.mistral        # Mistral AI tests
mix test.openrouter     # OpenRouter tests
mix test.perplexity     # Perplexity tests
mix test.ollama         # Ollama local tests
mix test.lmstudio       # LM Studio tests
mix test.bumblebee      # Bumblebee local tests
```

#### By Capability
```bash
mix test.streaming      # Streaming response tests
mix test.vision         # Vision/image processing tests
mix test.multimodal     # Multimodal input tests
mix test.function_calling # Function/tool calling tests
mix test.embedding      # Embedding generation tests
```

#### By Environment Needs
```bash
mix test.live_api       # Tests calling live APIs
mix test.local_only     # Local-only tests (no API calls)
mix test.fast           # Fast tests (cached/mocked)
mix test.all            # All tests including slow ones
mix test.oauth2         # OAuth2 authentication tests
```

### Test Caching (25x Speed Improvement)

ExLLM includes an advanced test caching system that dramatically speeds up integration tests:

```bash
# Tests with automatic caching
mix test.anthropic --include live_api

# Manage test cache
mix ex_llm.cache stats
mix ex_llm.cache clean --older-than 7d
mix ex_llm.cache clear
mix ex_llm.cache show anthropic

# Enable cache debugging
export EX_LLM_TEST_CACHE_ENABLED=true
export EX_LLM_LOG_LEVEL=debug
```

## Environment Setup

### Using .env Files (Recommended)

ExLLM now supports automatic loading of environment variables from `.env` files. This is the recommended approach for managing API keys:

1. Copy the example file:
   ```bash
   cp .env.example .env
   ```

2. Add your API keys to `.env`:
   ```bash
   # Core providers
   OPENAI_API_KEY=sk-...
   ANTHROPIC_API_KEY=sk-ant-...
   GEMINI_API_KEY=...
   GROQ_API_KEY=gsk_...
   MISTRAL_API_KEY=...
   
   # Router providers
   OPENROUTER_API_KEY=sk-or-...
   PERPLEXITY_API_KEY=pplx-...
   
   # OAuth2 credentials (for Gemini OAuth APIs)
   GOOGLE_CLIENT_ID=...
   GOOGLE_CLIENT_SECRET=...
   ```

3. Environment variables are automatically loaded when tests run.

#### Custom .env Location

You can specify a custom .env file location:

```bash
# Via environment variable
EX_LLM_ENV_FILE=.env.test mix test

# Or in config/test.exs
config :ex_llm, :env_file, ".env.test"
```

#### OAuth2 Token Refresh

For tests that require OAuth2 authentication (like Gemini Permissions API), tokens are automatically refreshed when:
- OAuth2 credentials are present in the environment
- A `.gemini_tokens` file exists
- The current token is expired or about to expire

To enable automatic OAuth refresh in your tests:

```elixir
setup do
  # Automatically refreshes OAuth tokens if needed
  ExLLM.Testing.EnvHelper.setup_oauth()
end
```

The OAuth refresh happens transparently during test setup, ensuring your tests always have valid tokens.

#### Using EnvHelper in Tests

For tests that require specific API keys:

```elixir
setup do
  case ExLLM.Testing.EnvHelper.ensure_api_keys(["OPENAI_API_KEY"]) do
    :ok -> 
      :ok
    {:error, missing} ->
      {:skip, "Missing API keys: #{Enum.join(missing, ", ")}"}
  end
end
```

### Legacy Method: Export Variables

Alternatively, you can still export environment variables directly:

```bash
# Core providers
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GEMINI_API_KEY="..."
export GROQ_API_KEY="gsk_..."
export MISTRAL_API_KEY="..."

# Router providers
export OPENROUTER_API_KEY="sk-or-..."
export PERPLEXITY_API_KEY="pplx-..."

# Optional metadata
export OPENROUTER_APP_NAME="ExLLM Test"
export OPENROUTER_APP_URL="https://example.com"
```

### Local Services

#### Ollama Setup
```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Start Ollama service
ollama serve

# Pull test models (optional)
ollama pull llama3.2:1b
ollama pull nomic-embed-text
```

#### LM Studio Setup
```bash
# Start LM Studio with API server enabled
# Default endpoint: http://localhost:1234/v1
```

## Test Tags and Filtering

### Available Tags

**Test Types:**
- `:unit` - Unit tests (no external calls)
- `:integration` - Integration tests
- `:external` - Tests that call external services
- `:live_api` - Tests that require live API access

**Providers:**
- `:provider:anthropic`, `:provider:openai`, `:provider:gemini`, etc.

**Capabilities:**
- `:streaming` - Streaming functionality tests
- `:function_calling` - Function/tool calling tests
- `:vision` - Vision/multimodal tests
- `:embedding` - Embedding generation tests
- `:multimodal` - Multimodal input handling

**Special Categories:**
- `:requires_api_key` - Tests needing API keys
- `:requires_oauth` - Tests needing OAuth setup
- `:requires_service` - Tests needing local services
- `:slow` - Slow-running tests
- `:very_slow` - Very slow tests
- `:quota_sensitive` - Tests that consume significant API quota
- `:flaky` - Tests that may be unreliable
- `:wip` - Work-in-progress tests

### Filtering Examples

```bash
# Include specific tags
mix test --include live_api
mix test --include requires_api_key
mix test --include oauth2

# Run only specific tags
mix test --only provider:anthropic
mix test --only streaming
mix test --only integration

# Exclude problematic tests
mix test --exclude requires_service
mix test --exclude slow
mix test --exclude flaky

# Complex filtering
mix test --only "provider:openai and streaming"
mix test --exclude "integration or external"
```

## Test Development Guidelines

### Adding New Tests

1. **Core Library Tests**: Add to `test/ex_llm/core/`
2. **Provider Tests**: Add to `test/ex_llm/providers/provider_name/`
3. **Infrastructure Tests**: Add to `test/ex_llm/infrastructure/`
4. **Integration Tests**: Add to `test/integration/`

### Test Tagging Pattern

```elixir
defmodule ExLLM.Providers.ProviderIntegrationTest do
  use ExUnit.Case
  
  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :provider:provider_name
  
  # Test implementation...
end
```

### Unit Test Pattern

```elixir
defmodule ExLLM.Providers.ProviderUnitTest do
  use ExUnit.Case, async: true
  
  @moduletag :unit
  @moduletag :provider:provider_name
  
  describe "configuration" do
    test "configured?/1 returns boolean" do
      # Test without API calls
    end
  end
end
```

### Using Test Cache

```elixir
defmodule ExLLM.Providers.ProviderIntegrationTest do
  use ExUnit.Case
  import ExLLM.Testing.TestCacheHelpers
  
  test "cached API call" do
    # Automatically cached based on request parameters
    {:ok, response} = ExLLM.chat(:provider, [%{role: "user", content: "test"}])
    assert response.content != ""
  end
end
```

## Continuous Integration

### CI Configuration

The test suite is designed for CI environments:

```bash
# CI runs fast tests by default (no API keys needed)
mix test.ci

# Full CI with API keys (if available)
mix test.ci.full

# Specific provider tests in CI
OPENAI_API_KEY=${{ secrets.OPENAI_API_KEY }} mix test.openai
```

### GitHub Actions Example

```yaml
- name: Run unit tests
  run: mix test.ci

- name: Run integration tests
  env:
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  run: mix test.integration
  if: env.OPENAI_API_KEY != ''
```

## Performance Testing

### Load Testing
```bash
# Test with multiple concurrent requests
mix test --only "integration and streaming" --max-cases 10
```

### Memory Usage Monitoring
```bash
# Monitor memory during tests
mix test --cover --export-coverage default.coverdata
```

## Troubleshooting

### Common Issues

#### Tests Hang or Timeout
```bash
# Increase timeout for slow connections
mix test --timeout 30000
```

#### Integration Tests Skipped
```bash
# Make sure to include the required tags
mix test --include live_api test/ex_llm/providers/anthropic_integration_test.exs

# Check for required environment variables
echo $ANTHROPIC_API_KEY
```

#### Cache Issues
```bash
# Clear test cache if responses seem stale
mix ex_llm.cache clear

# Disable cache for debugging
export EX_LLM_TEST_CACHE_ENABLED=false
```

#### API Rate Limits
```bash
# Run tests sequentially to avoid rate limits
mix test --max-cases 1 --only integration

# Use cached responses
export EX_LLM_TEST_CACHE_ENABLED=true
```

### Debugging Test Failures

```bash
# Run with detailed output
mix test --trace

# Run single test with maximum verbosity
mix test test/path/to/test.exs:line_number --trace

# Enable debug logging
export EX_LLM_LOG_LEVEL=debug
mix test
```

## Architecture Notes

The test suite follows ExLLM's layered architecture:

- **Core Layer**: Business logic tests (`test/ex_llm/core/`)
- **Infrastructure Layer**: Technical concerns (`test/ex_llm/infrastructure/`)
- **Providers Layer**: External integrations (`test/ex_llm/providers/`)
- **Testing Layer**: Test framework itself (`test/ex_llm/testing/`)

This organization ensures:
- Clear separation of concerns
- Easy navigation and maintenance
- Consistent test patterns across the codebase
- Efficient test caching and execution

## Contributing

### Pull Request Checklist
- [ ] Unit tests pass without API keys
- [ ] Integration tests pass with API keys (when available)
- [ ] New tests follow established patterns and directory structure
- [ ] Tests are properly tagged for filtering
- [ ] Test cache works correctly for integration tests
- [ ] Documentation updated if needed
- [ ] Tests follow the layered architecture organization