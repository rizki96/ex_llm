# Public API Testing Guide

This document explains the public API testing approach for ExLLM, ensuring tests are resilient to internal implementation changes.

## Core Principle

All integration tests MUST use the public ExLLM module API, not provider-specific modules directly.

## API Usage Examples

### ❌ Wrong - Direct Provider Access
```elixir
# Don't do this in integration tests!
Anthropic.chat(messages, max_tokens: 10)
OpenAI.stream_chat(messages)
Gemini.list_models()
```

### ✅ Correct - Public API
```elixir
# Always use the ExLLM module
ExLLM.chat(:anthropic, messages, max_tokens: 10)
ExLLM.stream(:openai, messages)
ExLLM.list_models(:gemini)
```

## Test Organization

### 1. Shared Integration Tests
Location: `test/shared/provider_integration_test.exs`

This module contains common tests that should pass for ALL providers:
- Basic chat completion
- System message handling
- Temperature settings
- Streaming responses
- Error handling
- Cost calculation
- Model listing

Usage:
```elixir
defmodule ExLLM.Providers.MyProviderPublicAPITest do
  use ExLLM.Shared.ProviderIntegrationTest, provider: :my_provider
  
  # Provider-specific tests go here
end
```

### 2. Provider-Specific Tests
Location: `test/ex_llm/providers/{provider}_public_api_test.exs`

Only include tests for features unique to that provider:
- Special model capabilities
- Provider-specific parameters
- Unique error handling
- Custom features

### 3. Unit Tests
Location: `test/ex_llm/providers/{provider}_unit_test.exs`

Unit tests CAN use internal APIs since they test the adapter implementation:
- Configuration validation
- Message formatting
- Response parsing
- No external API calls

## Test Tagging Strategy

All tests must be properly tagged:

```elixir
@moduletag :integration
@moduletag :external
@moduletag :live_api
@moduletag :requires_api_key
@moduletag provider: :provider_name

# Capability-specific tags
@tag :streaming      # For streaming tests
@tag :vision         # For vision/multimodal tests
@tag :function_calling # For function/tool calling
@tag :embedding      # For embedding generation
```

## Running Tests

### By Provider
```bash
# Run all tests for a provider
mix test.anthropic

# Run only public API tests
mix test test/ex_llm/providers/anthropic_public_api_test.exs
```

### By Capability
```bash
# Run all streaming tests
mix test --only streaming

# Run all vision tests
mix test --only vision
```

### Shared Tests Only
```bash
# Test common functionality across all providers
mix test test/shared/provider_integration_test.exs
```

## Benefits

1. **Resilience**: Tests won't break when internal implementations change
2. **Consistency**: Same test patterns across all providers
3. **Maintainability**: Common logic in one place
4. **Documentation**: Tests serve as API usage examples
5. **Coverage**: Ensures public API is fully tested

## Migration Checklist

When adding a new provider:
1. Create unit tests for internal logic
2. Create public API test file using shared module
3. Add provider-specific tests only
4. Ensure all tests use ExLLM module
5. Add proper tags
6. Verify tests pass
7. Update this documentation

## Example: Adding a New Provider

```elixir
# test/ex_llm/providers/newprovider_public_api_test.exs
defmodule ExLLM.Providers.NewProviderPublicAPITest do
  use ExLLM.Shared.ProviderIntegrationTest, provider: :newprovider
  
  describe "newprovider-specific features via public API" do
    test "unique feature X" do
      messages = [%{role: "user", content: "Test"}]
      
      case ExLLM.chat(:newprovider, messages, special_param: true) do
        {:ok, response} ->
          assert response.provider == :newprovider
          # Test unique behavior
          
        {:error, _} ->
          :ok
      end
    end
  end
end
```

This approach ensures all providers are tested consistently while allowing for provider-specific features.