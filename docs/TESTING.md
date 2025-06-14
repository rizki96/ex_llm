# Testing Guide

ExLLM includes a comprehensive testing system with intelligent caching, semantic tagging, and 24 specialized Mix aliases for targeted test execution.

## Quick Start

```bash
# Run all tests (fast - uses cache when available)
mix test

# Run provider-specific tests
mix test.anthropic
mix test.openai
mix test.gemini

# Run integration tests with live APIs
mix test.integration --include live_api

# Run tests by capability
mix test.streaming
mix test.vision
mix test.oauth2

# Manage test cache
mix ex_llm.cache stats
mix ex_llm.cache clean --older-than 7d
```

## Test Organization

### Test Tags

ExLLM uses semantic tags to organize tests by requirements, capabilities, and providers:

#### **Requirement Tags**
- `:requires_api_key` - Tests needing API keys with automatic provider detection
- `:requires_oauth` - Tests needing OAuth2 authentication (e.g., Gemini APIs)
- `:requires_service` - Tests needing local services (Ollama, LM Studio)
- `:requires_resource` - Tests needing pre-existing resources (tuned models, corpora)

#### **Test Type Tags**
- `:live_api` - Tests that call live provider APIs
- `:integration` - Integration tests with external services
- `:external` - Tests making external network calls
- `:unit` - Unit tests (isolated, no external dependencies)

#### **Provider Tags**
- `:anthropic`, `:openai`, `:gemini`, `:groq`, `:mistral`
- `:openrouter`, `:perplexity`, `:ollama`, `:lmstudio`, `:bumblebee`

#### **Capability Tags**
- `:streaming` - Tests for streaming responses
- `:vision` - Tests for image/vision capabilities  
- `:multimodal` - Tests for multimodal inputs
- `:function_calling` - Tests for tool/function calling
- `:embedding` - Tests for embedding generation

## Mix Test Aliases

ExLLM provides 24 specialized test aliases for targeted execution:

### Provider-Specific Tests

```bash
# Test individual providers
mix test.anthropic       # Anthropic Claude tests
mix test.openai          # OpenAI GPT tests  
mix test.gemini          # Google Gemini tests
mix test.groq            # Groq tests
mix test.mistral         # Mistral AI tests
mix test.openrouter      # OpenRouter tests
mix test.perplexity      # Perplexity tests
mix test.ollama          # Ollama local tests
mix test.lmstudio        # LM Studio tests
mix test.bumblebee       # Bumblebee local tests
```

### Test Type Aliases

```bash
# By test type
mix test.unit            # Unit tests only
mix test.integration     # Integration tests
mix test.external        # Tests with external calls
mix test.oauth2          # OAuth2 authentication tests
```

### Capability-Based Tests

```bash
# By capability
mix test.streaming       # Streaming response tests
mix test.vision          # Vision/image processing tests
mix test.multimodal      # Multimodal input tests
mix test.function_calling # Function/tool calling tests
mix test.embedding       # Embedding generation tests
```

### Environment-Based Tests

```bash
# By environment needs
mix test.live_api        # Tests calling live APIs
mix test.local_only      # Local-only tests (no API calls)
mix test.fast            # Fast tests (cached/mocked)
mix test.all             # All tests including slow ones
```

## Test Caching System

ExLLM includes an advanced caching system that provides 25x speed improvements for integration tests.

### How It Works

1. **Automatic Detection**: Tests tagged with `:live_api` are automatically cached
2. **Smart Exclusions**: Destructive operations (create, delete, modify) are not cached
3. **TTL Management**: Cached responses expire after 7 days by default
4. **Fallback Strategies**: Multiple matching algorithms for cache hits

### Cache Management

```bash
# View cache statistics
mix ex_llm.cache stats

# Clean old cache entries  
mix ex_llm.cache clean --older-than 7d

# Clear all cache
mix ex_llm.cache clear

# Show cache details for a provider
mix ex_llm.cache show anthropic
```

### Configuration

Configure caching via environment variables:

```bash
# Enable/disable caching
export EX_LLM_TEST_CACHE_ENABLED=true

# Cache directory
export EX_LLM_TEST_CACHE_DIR="test/cache"

# TTL for cached responses (in seconds)
export EX_LLM_TEST_CACHE_TTL=604800  # 7 days

# Cache destructive operations
export EX_LLM_TEST_CACHE_DESTRUCTIVE_OPS=false
```

## Writing Tests

### Basic Test Structure

```elixir
defmodule MyProviderTest do
  use ExUnit.Case
  
  # Module-level tags
  @moduletag :integration
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag provider: :anthropic
  
  # Import cache helpers
  import ExLLM.TestCacheHelpers
  
  setup_all do
    enable_cache_debug()
    :ok
  end
  
  setup context do
    setup_test_cache(context)
    on_exit(fn -> ExLLM.TestCacheDetector.clear_test_context() end)
    :ok
  end
  
  test "basic chat completion" do
    {:ok, response} = ExLLM.chat(:anthropic, [
      %{role: "user", content: "Hello!"}
    ])
    
    assert response.content != ""
  end
end
```

### Using ExLLM.Case for Automatic Requirements

```elixir
defmodule MyProviderTest do
  use ExLLM.Case, async: true
  
  @moduletag :requires_api_key
  @moduletag provider: :openai
  
  test "test with automatic API key checking", context do
    # Automatically skips if OPENAI_API_KEY not set
    check_test_requirements!(context)
    
    {:ok, response} = ExLLM.chat(:openai, [
      %{role: "user", content: "Test"}
    ])
    
    assert response.content != ""
  end
end
```

### OAuth2 Tests

```elixir
defmodule GeminiOAuth2Test do
  use ExLLM.Case, async: true
  
  @moduletag :requires_oauth
  @moduletag provider: :gemini
  
  test "OAuth2 API call", context do
    check_test_requirements!(context)
    
    # OAuth token automatically provided if available
    oauth_token = get_oauth_token(context)
    
    {:ok, response} = ExLLM.Gemini.Permissions.list_permissions(
      "tunedModels/test",
      oauth_token: oauth_token
    )
    
    assert is_list(response.permissions)
  end
end
```

## Test Exclusions

### Default Exclusions

By default, these tests are excluded unless explicitly included:

```bash
# In test_helper.exs
ExUnit.configure(exclude: [
  :live_api,           # Exclude live API calls by default
  :requires_api_key,   # Exclude tests needing API keys
  :requires_oauth,     # Exclude OAuth tests
  :requires_service,   # Exclude tests needing local services
  :integration,        # Exclude integration tests
  :external           # Exclude external network tests
])
```

### Running Excluded Tests

```bash
# Include specific tags
mix test --include live_api
mix test --include requires_api_key
mix test --include oauth2

# Include multiple tags
mix test --include live_api --include streaming

# Run only specific tags
mix test --only provider:anthropic
mix test --only streaming
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Tests
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '28'
      
      # Unit tests only (no API keys needed)
      - run: mix test.unit
  
  integration-tests:
    runs-on: ubuntu-latest
    if: github.event_name == 'push'
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      
      # Integration tests with caching
      - run: mix test.integration --include live_api
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
          EX_LLM_TEST_CACHE_ENABLED: true
```

## Performance Tips

1. **Use Caching**: Enable test caching for 25x faster integration tests
2. **Tag Appropriately**: Use semantic tags for precise test selection
3. **Run Targeted Tests**: Use Mix aliases to run only what you need
4. **Cache Management**: Regularly clean old cache entries
5. **Local Services**: Use Ollama/LM Studio for development without API costs

## Troubleshooting

### Common Issues

**Tests skipped with "API key required":**
```bash
# Set the required API key
export ANTHROPIC_API_KEY="your-key"
mix test.anthropic
```

**OAuth2 tests failing:**
```bash
# Setup OAuth2 first
elixir scripts/setup_oauth2.exs
# Then refresh token
elixir scripts/refresh_oauth2_token.exs
```

**Cache not working:**
```bash
# Check cache configuration
mix ex_llm.cache stats
# Enable debug logging
export EX_LLM_LOG_LEVEL=debug
```

**Tests timing out:**
```bash
# Use cached responses
export EX_LLM_TEST_CACHE_ENABLED=true
mix test --include live_api
```

### Debug Logging

Enable debug logging to troubleshoot test issues:

```bash
export EX_LLM_LOG_LEVEL=debug
export EX_LLM_LOG_COMPONENTS=http_client,cache,test_detector
mix test --include live_api
```

This comprehensive testing system ensures reliable, fast, and well-organized tests across all ExLLM functionality.