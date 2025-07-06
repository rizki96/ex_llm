# ExLLM Comprehensive Testing Strategy

This document describes the comprehensive testing strategy implemented for ExLLM, providing a unified framework for testing across multiple LLM providers while maintaining fast development cycles.

## Overview

ExLLM's testing strategy consists of five integrated components designed to provide comprehensive test coverage while enabling fast development iterations:

1. **Test Tagging System** - Semantic categorization of tests
2. **Directory Structure** - Organized test hierarchy
3. **Provider Capability Matrix** - Visual representation of provider support
4. **Selective Test Execution** - Mix aliases for targeted testing
5. **Response Capture System** - API response debugging and analysis

## 1. Test Tagging System

All tests in ExLLM are tagged to enable selective execution based on various criteria.

### Tag Categories

#### Test Type Tags
- `:unit` - Pure logic tests with no external dependencies
- `:integration` - Tests requiring API calls or external services  
- `:comprehensive` - Full end-to-end tests of complex features
- `:performance` - Performance benchmarks and stress tests
- `:mock` - Tests using the mock provider

#### Provider Tags
- `provider:openai` - OpenAI-specific tests
- `provider:anthropic` - Anthropic Claude tests
- `provider:gemini` - Google Gemini tests
- `provider:groq` - Groq tests
- `provider:ollama` - Ollama local model tests
- `provider:mistral` - Mistral AI tests
- `provider:xai` - X.AI Grok tests
- `provider:perplexity` - Perplexity tests
- `provider:openrouter` - OpenRouter tests
- `provider:lmstudio` - LM Studio tests
- `provider:bumblebee` - Bumblebee (Elixir ML) tests
- `provider:mock` - Mock provider tests

#### Capability Tags
- `capability:chat` - Basic chat completion
- `capability:streaming` - Streaming responses
- `capability:list_models` - Model enumeration
- `capability:function_calling` - Tool use / function calling
- `capability:vision` - Image understanding
- `capability:embeddings` - Text embeddings
- `capability:cost_tracking` - Usage and cost tracking
- `capability:json_mode` - Structured outputs
- `capability:system_prompt` - System message support
- `capability:temperature` - Temperature control

#### Requirement Tags
- `:requires_api_key` - Needs provider API key
- `:requires_service` - Needs running service (e.g., Ollama)
- `:requires_oauth` - OAuth2 authentication required
- `:live_api` - Makes actual API calls
- `:external` - Requires external resources

#### CI/CD Tags
- `:wip` - Work in progress, skip in CI
- `:flaky` - Known flaky tests
- `:quota_sensitive` - May hit rate limits
- `:slow` - Takes >5 seconds
- `:very_slow` - Takes >30 seconds

### Example Test Tagging

```elixir
defmodule ExLLM.VisionTest do
  use ExUnit.Case, async: false
  
  @moduletag :capability:vision
  @moduletag :integration
  
  describe "image understanding" do
    @tag provider: :openai
    @tag :requires_api_key
    test "analyzes image content" do
      # Test implementation
    end
  end
end
```

## 2. Directory Structure

```
test/
├── ex_llm/                      # Core functionality tests
│   ├── core/                    # Core modules (session, context, etc.)
│   ├── providers/               # Provider-specific tests
│   │   ├── anthropic/
│   │   ├── openai/
│   │   └── ...
│   ├── chat_test.exs           # Main chat API tests
│   ├── embedding_test.exs      # Embedding tests
│   └── function_calling_test.exs
├── integration/                 # Integration tests
│   ├── comprehensive/          # Full feature tests
│   └── cross_provider/         # Cross-provider compatibility
├── performance/                # Performance benchmarks
└── support/                    # Test helpers and utilities
```

## 3. Provider Capability Matrix

The capability matrix provides a visual overview of which providers support which features.

### Viewing the Matrix

```bash
# Display in console
mix ex_llm.capability_matrix

# Show extended capabilities
mix ex_llm.capability_matrix --extended

# Filter by providers
mix ex_llm.capability_matrix --providers openai,anthropic,gemini

# Filter by capabilities  
mix ex_llm.capability_matrix --capabilities vision,streaming

# Export to markdown
mix ex_llm.capability_matrix --export markdown --output matrix.md

# Export to HTML
mix ex_llm.capability_matrix --export html --output matrix.html

# Include test results
mix ex_llm.capability_matrix --with-tests
```

### Matrix Legend
- ✅ Pass - Verified by tests
- ✓ Configured - Available per configuration
- ❌ Fail - Test failed
- ⏭️ Skip - Test skipped
- ○ Not configured - Provider not set up
- - Not supported - Feature not available
- ❓ Unknown - Status unclear

## 4. Selective Test Execution

ExLLM provides numerous Mix aliases for running specific subsets of tests.

### Core Testing Aliases

```bash
# Fast development tests (no API calls)
mix test.fast

# Unit tests only
mix test.unit

# Integration tests
mix test.integration

# All tests including slow ones
mix test.all

# Mock tests only (offline)
mix test.mock

# Quick smoke tests
mix test.smoke

# All live API tests
mix test.live.all

# Force live API calls (refresh cache)
mix test.live
```

### Provider-Specific Testing

```bash
# Test specific providers
mix test.openai
mix test.anthropic
mix test.gemini
mix test.groq
mix test.mistral
mix test.xai
mix test.perplexity
mix test.openrouter

# Test local providers
mix test.local        # Ollama + LM Studio
mix test.ollama
mix test.lmstudio
mix test.bumblebee   # Requires model download
```

### Capability-Specific Testing

```bash
# Test specific capabilities
mix test.capability.chat
mix test.capability.streaming
mix test.capability.list_models
mix test.capability.function_calling
mix test.capability.vision
mix test.capability.embeddings
mix test.capability.cost_tracking
mix test.capability.json_mode
mix test.capability.system_prompt
mix test.capability.temperature
```

### Cross-Provider Test Matrix

```bash
# Run tests across all configured providers
mix test.matrix

# Test major providers only
mix test.matrix.major

# Test specific capability across providers
mix test.matrix.vision
mix test.matrix.streaming
mix test.matrix.function_calling

# Run integration tests across providers
mix test.matrix.integration

# Run in parallel with summary
mix test.matrix --parallel --summary

# Stop on first failure
mix test.matrix --stop-on-failure
```

### Special Testing Modes

```bash
# OAuth2 tests
mix test.oauth2

# CI pipeline tests (excludes problematic tests)
mix test.ci

# Cache management
mix cache.clear
mix cache.status
```

## 5. Response Capture System

The response capture system helps debug API interactions by capturing and displaying responses.

### Enabling Response Capture

```bash
# Enable capture
export EX_LLM_CAPTURE_RESPONSES=true

# Enable display
export EX_LLM_SHOW_CAPTURED=true

# Run with capture
EX_LLM_CAPTURE_RESPONSES=true mix test
```

### Managing Captures

```bash
# List captured responses
mix captures.list
mix ex_llm.captures list --provider openai --limit 10

# Show specific capture
mix captures.show <capture_id>
mix ex_llm.captures show <capture_id> --format json

# View capture statistics
mix captures.stats
mix ex_llm.captures stats --provider anthropic

# Clear captures
mix captures.clear
mix ex_llm.captures clear --older-than 7d
mix ex_llm.captures clear --provider gemini
```

### Capture Output Format

When display is enabled, captures show:
- Provider and endpoint
- Timestamp and duration
- Token usage (input/output/total)
- Cost calculation
- Full response content

## Test Caching System

ExLLM includes an intelligent test caching system that provides 25x faster integration tests.

### Cache Behavior

**Default**: Integration tests hit live APIs
```bash
mix test --include integration    # Calls live APIs
```

**With Caching**: Uses cached responses when available
```bash
export EX_LLM_TEST_CACHE_ENABLED=true
mix test --include integration    # Uses cache if fresh
```

**Force Live**: Always use live APIs
```bash
MIX_RUN_LIVE=true mix test --include integration
```

### Cache Management

```bash
# View cache statistics
mix ex_llm.cache stats

# Clean old cache entries
mix ex_llm.cache clean --older-than 7d

# Clear entire cache
mix ex_llm.cache clear

# Show cache for specific provider
mix ex_llm.cache show anthropic
```

## Best Practices

### 1. Tag Your Tests Appropriately

Always add relevant tags to new tests:
```elixir
@moduletag :unit
@moduletag provider: :openai
@moduletag capability: :streaming
```

### 2. Use Fast Tests During Development

```bash
# Quick iteration
mix test.fast

# Specific provider
mix test.anthropic

# Specific capability
mix test.capability.vision
```

### 3. Run Comprehensive Tests Before Commits

```bash
# Run full test suite
mix test.all

# Check cross-provider compatibility
mix test.matrix --providers openai,anthropic,gemini
```

### 4. Debug with Response Capture

```bash
# Enable capture for debugging
export EX_LLM_CAPTURE_RESPONSES=true
export EX_LLM_SHOW_CAPTURED=true
mix test failing_test.exs
```

### 5. Monitor Test Performance

```bash
# Run with timing
mix test --trace

# Check slow tests
mix test --slowest 10
```

## CI/CD Integration

### GitHub Actions Configuration

```yaml
# Fast CI tests (no API calls)
- run: mix test.ci

# Release validation (with cache)
- run: |
    export EX_LLM_TEST_CACHE_ENABLED=true
    mix test.integration
```

### Pre-commit Hooks

```bash
# Add to .git/hooks/pre-commit
mix test.fast
mix format --check-formatted
mix credo
```

## Troubleshooting

### Common Issues

1. **Tests failing due to missing API keys**
   ```bash
   export OPENAI_API_KEY=your_key
   # Or use mock tests
   mix test.mock
   ```

2. **Rate limit errors**
   ```bash
   # Use cached tests
   export EX_LLM_TEST_CACHE_ENABLED=true
   mix test
   ```

3. **Slow test execution**
   ```bash
   # Run fast tests only
   mix test.fast
   
   # Run specific provider
   mix test.gemini
   ```

4. **Finding specific tests**
   ```bash
   # By capability
   mix test.capability.vision
   
   # By provider
   mix test.anthropic
   
   # By file pattern
   mix test test/ex_llm/chat_test.exs
   ```

### Debug Mode

Enable detailed logging:
```bash
export EX_LLM_LOG_LEVEL=debug
mix test
```

## Summary

ExLLM's comprehensive testing strategy provides:

- **Fast Development** - Run only relevant tests during development
- **Comprehensive Coverage** - 72% capability coverage across 12 providers
- **Selective Execution** - Target specific providers, capabilities, or test types
- **Cross-Provider Validation** - Ensure consistency across providers
- **Debugging Support** - Capture and analyze API responses
- **CI/CD Integration** - Optimized for continuous integration

This strategy enables confident development while maintaining compatibility across the diverse landscape of LLM providers.