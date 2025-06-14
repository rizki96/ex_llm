# Automatic Test Response Caching

ExLLM includes a sophisticated automatic test response caching system that dramatically reduces API costs and improves test reliability by caching and replaying API responses during test runs.

## Overview

The test caching system automatically:
- Detects when integration or OAuth2 tests are running
- Intercepts API requests and checks for cached responses
- Saves new API responses with timestamp-based filenames
- Replays cached responses on subsequent test runs
- Falls back to older cached responses when APIs fail
- Tracks performance metrics and cost savings

## Key Features

### 🎯 Zero Configuration Required
The caching system works automatically for any test tagged with `:integration` or `:oauth2`. No code changes needed!

### ⏰ Timestamp-Based Storage
- Responses are saved with ISO8601 timestamps (e.g., `2024-01-22T09-15-33Z.json`)
- New responses never overwrite old ones
- Natural chronological ordering
- Easy debugging and history tracking

### 🔄 Smart Cache Selection
Multiple strategies for selecting the best cached response:
- **`:latest_success`** - Most recent successful response (default)
- **`:latest_any`** - Most recent response, even if it was an error
- **`:best_match`** - Most similar response based on request matching

### 💾 Storage Optimization
- Content deduplication using SHA256 hashes
- Symlinks for identical responses save disk space
- Automatic cleanup of old entries
- Configurable retention policies

### 📊 Comprehensive Monitoring
- Hit/miss ratios and performance metrics
- Cost savings calculations
- Storage usage tracking
- Provider and test suite analytics

## Configuration

### Application Configuration

```elixir
# config/test.exs
config :ex_llm, :test_cache,
  enabled: true,                    # Enable caching (default: true)
  auto_detect: true,                # Auto-detect test environment (default: true)
  cache_dir: "test/cache",          # Cache directory (default: "test/cache")
  replay_by_default: true,          # Use cache by default (default: true)
  save_on_miss: true,               # Save new responses (default: true)
  ttl: :timer.days(7),              # Cache TTL in milliseconds (default: 7 days)
  timestamp_format: :iso8601,       # Timestamp format (default: :iso8601)
  fallback_strategy: :latest_success, # Selection strategy (default: :latest_success)
  max_entries_per_cache: 10,        # Max timestamps per cache key (default: 10)
  cleanup_older_than: :timer.days(30), # Auto-cleanup age (default: 30 days)
  deduplicate_content: true         # Enable deduplication (default: true)
```

### Environment Variables

All configuration options can be overridden via environment variables:

```bash
# Basic settings
export EX_LLM_TEST_CACHE_ENABLED="true"
export EX_LLM_TEST_CACHE_DIR="/tmp/ex_llm_cache"
export EX_LLM_TEST_CACHE_REPLAY_ONLY="true"  # Don't make real requests

# TTL settings (in seconds)
export EX_LLM_TEST_CACHE_TTL="3600"           # 1 hour
export EX_LLM_TEST_CACHE_OAUTH2_TTL="86400"   # 1 day for OAuth2 tests
export EX_LLM_TEST_CACHE_OPENAI_TTL="7200"    # 2 hours for OpenAI

# Fallback strategies
export EX_LLM_TEST_CACHE_FALLBACK_STRATEGY="latest_success"
export EX_LLM_TEST_CACHE_OAUTH2_STRATEGY="latest_any"

# Cleanup settings
export EX_LLM_TEST_CACHE_MAX_ENTRIES="5"
export EX_LLM_TEST_CACHE_CLEANUP_OLDER_THAN="7d"
```

## Usage

### Automatic Usage in Tests

For any integration test, the caching is automatic:

```elixir
defmodule MyIntegrationTest do
  use ExUnit.Case
  
  @moduletag :integration  # This enables automatic caching
  
  test "chat completion" do
    # First run: Makes real API call and saves response
    # Subsequent runs: Uses cached response
    {:ok, response} = ExLLM.chat(:openai, messages, model: "gpt-4")
    assert response.content
  end
end
```

### Using Test Helpers

The `ExLLM.TestCacheHelpers` module provides utilities for cache management:

```elixir
# In your test module
import ExLLM.TestCacheHelpers

setup do
  # Initialize test caching for this test
  setup_test_cache()
end

test "force fresh API call" do
  # Force cache miss for this specific test
  force_cache_miss("openai/chat")
  
  {:ok, response} = ExLLM.chat(:openai, messages)
  assert response.content
end

test "use specific TTL" do
  # Set custom TTL for this test
  set_test_ttl("anthropic/*", :timer.minutes(30))
  
  {:ok, response} = ExLLM.chat(:anthropic, messages)
  assert response.content
end
```

### Cache Management Commands

```elixir
# Print cache statistics
ExLLM.TestCacheHelpers.print_cache_summary()

# Clear all cache
ExLLM.TestCacheHelpers.clear_test_cache(:all)

# Clear specific provider cache
ExLLM.TestCacheHelpers.clear_test_cache("openai")

# List timestamps for a cache key
ExLLM.TestCacheHelpers.list_cache_timestamps("openai/chat_completion")

# Clean up old entries
ExLLM.TestCacheHelpers.cleanup_old_timestamps(:timer.days(7))

# Deduplicate content to save space
ExLLM.TestCacheHelpers.deduplicate_cache_content()
```

## Cache Organization

The cache is organized hierarchically:

```
test/cache/
├── integration/                     # Integration tests
│   ├── anthropic/
│   │   ├── messages/
│   │   │   ├── 4a3b2c1d/          # Request signature
│   │   │   │   ├── 2024-01-22T09-15-33Z.json
│   │   │   │   ├── 2024-01-23T14-22-10Z.json
│   │   │   │   └── index.json     # Cache metadata
│   │   │   └── 5e6f7g8h/
│   │   └── embeddings/
│   ├── openai/
│   └── gemini/
└── oauth2/                         # OAuth2 tests
    └── gemini/
        ├── corpus_operations/
        └── document_operations/
```

## Advanced Features

### Fallback Strategies

When a fresh API call fails, the system can fall back to older cached responses:

```elixir
# Configure fallback behavior
config :ex_llm, :test_cache,
  fallback_strategy: :latest_success,  # Use last successful response
  allow_expired: true,                 # Allow expired cache as fallback
  max_age_fallback: :timer.days(30)    # Maximum age for fallback
```

### Content Deduplication

The system automatically detects identical responses and creates symlinks:

```
cache/openai/chat/abc123/
├── 2024-01-22T09-00-00Z.json    # Original file (1KB)
├── 2024-01-22T10-00-00Z.json -> 2024-01-22T09-00-00Z.json  # Symlink
└── 2024-01-22T11-00-00Z.json -> 2024-01-22T09-00-00Z.json  # Symlink
```

### Performance Monitoring

Track cache performance and cost savings:

```elixir
stats = ExLLM.TestCacheStats.get_global_stats()

# Example output:
%{
  total_requests: 1500,
  cache_hits: 1350,
  hit_rate: 0.9,
  estimated_cost_savings: 24.50,
  time_savings_ms: 450_000,
  storage_used: 15_728_640,  # 15MB
  deduplication_savings: 7_864_320  # 7.5MB saved
}
```

## CI/CD Integration

### GitHub Actions Example

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      # Use cache, don't make real API calls in CI
      EX_LLM_TEST_CACHE_ENABLED: "true"
      EX_LLM_TEST_CACHE_REPLAY_ONLY: "true"
      EX_LLM_TEST_CACHE_TTL: "0"  # Accept any age in CI
    
    steps:
      - uses: actions/checkout@v3
      
      # Cache the test responses between runs
      - uses: actions/cache@v3
        with:
          path: test/cache
          key: test-cache-${{ runner.os }}-${{ hashFiles('**/mix.lock') }}
          restore-keys: |
            test-cache-${{ runner.os }}-
      
      - run: mix test
```

### Local Development

For local development, you might want fresh responses:

```bash
# Force cache refresh for development
export EX_LLM_TEST_CACHE_TTL="3600"  # 1 hour TTL

# Or disable caching temporarily
export EX_LLM_TEST_CACHE_ENABLED="false"

# Run tests
mix test
```

## Troubleshooting

### Debug Logging

Enable debug logging to see cache operations:

```elixir
# In your test
ExLLM.TestCacheHelpers.enable_cache_debug()

# Or via environment
export EX_LLM_TEST_CACHE_DEBUG="true"
```

### Verify Cache Integrity

Check for cache issues:

```elixir
ExLLM.TestCacheHelpers.verify_cache_integrity()
# Output:
# ✅ Cache integrity check passed!
# or
# ❌ Cache integrity issues found:
#   - openai/chat: 2 missing files
```

### Force Specific Timestamp

Use a specific cached response for debugging:

```elixir
ExLLM.TestCacheHelpers.restore_cache_timestamp(
  "openai/chat/abc123",
  "2024-01-22T09-15-33Z.json"
)
```

## Best Practices

1. **Regular Cleanup**: Run cleanup periodically to remove old entries
   ```elixir
   ExLLM.TestCacheHelpers.cleanup_old_timestamps(:timer.days(30))
   ```

2. **Monitor Cache Size**: Check cache statistics regularly
   ```elixir
   ExLLM.TestCacheHelpers.print_cache_summary()
   ```

3. **Test Cache Warming**: Warm cache before test runs
   ```elixir
   ExLLM.TestCacheHelpers.warm_test_cache(MyIntegrationTest)
   ```

4. **Provider-Specific TTLs**: Set appropriate TTLs for different providers
   ```bash
   export EX_LLM_TEST_CACHE_OPENAI_TTL="7200"     # 2 hours
   export EX_LLM_TEST_CACHE_ANTHROPIC_TTL="3600"  # 1 hour
   ```

5. **Deduplicate Regularly**: Save disk space
   ```elixir
   ExLLM.TestCacheHelpers.deduplicate_cache_content()
   ```

## Security Considerations

The caching system automatically:
- Redacts API keys and auth tokens from cached data
- Sanitizes sensitive headers before storage
- Excludes sensitive request fields from cache keys
- Stores cache files with appropriate permissions

Never commit the `test/cache` directory to version control!