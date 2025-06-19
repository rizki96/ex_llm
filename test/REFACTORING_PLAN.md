# Test Suite Refactoring Plan

## Overview

This document outlines the refactoring needed to ensure all tests use the public ExLLM API and follow proper tagging conventions.

## Key Issues Identified

### 1. Direct Provider Module Usage

Many tests directly call provider modules instead of using the public API:

**Current (incorrect):**
```elixir
Anthropic.chat(messages, max_tokens: 10)
OpenAI.stream_chat(messages)
Gemini.list_models()
```

**Should be:**
```elixir
ExLLM.chat(:anthropic, messages, max_tokens: 10)
ExLLM.stream(:openai, messages)
ExLLM.list_models(:gemini)
```

### 2. Duplicate Tests Across Providers

The following test cases are duplicated across multiple provider test files:
- Basic chat completion
- System message handling
- Temperature settings
- Streaming responses
- Error handling (invalid API key, rate limits, context length)
- Cost calculation

### 3. Missing Test Tags

Tests are missing capability-specific tags:
- Vision/multimodal tests need `@tag :vision`
- Streaming tests need `@tag :streaming`
- Function calling tests need `@tag :function_calling`
- Embedding tests need `@tag :embedding`

## Refactoring Steps

### Step 1: Create Shared Test Module ✅

Created `test/shared/provider_integration_test.exs` that:
- Uses only the public ExLLM API
- Provides common test cases for all providers
- Properly tags tests
- Can be used by any provider with `use ExLLM.Shared.ProviderIntegrationTest, provider: :provider_name`

### Step 2: Refactor Provider Tests

For each provider, create a new test file that:
1. Uses the shared test module for common tests
2. Only includes provider-specific tests
3. Uses the public ExLLM API exclusively

Example files created:
- `test/ex_llm/providers/anthropic_public_api_test.exs` ✅
- `test/ex_llm/providers/openai_public_api_test.exs` ✅

### Step 3: Update Test Tags

Created `scripts/fix_test_tags.exs` to automatically add missing tags based on test content.

### Step 4: Remove Old Tests

Once new tests are verified, remove old provider test files that use internal APIs:
- `anthropic_integration_test.exs`
- `openai_integration_test.exs`
- etc.

## Benefits

1. **API Stability**: Tests won't break when internal implementations change
2. **Reduced Duplication**: Common tests are shared across providers
3. **Better Organization**: Clear separation between common and provider-specific tests
4. **Proper Tagging**: Easy to run specific test categories
5. **Maintainability**: Changes to test patterns only need to be made in one place

## Implementation Checklist

- [x] Create shared test module
- [x] Create refactored Anthropic tests
- [x] Create refactored OpenAI tests
- [x] Create refactored Gemini tests
- [x] Create refactored Groq tests
- [x] Create refactored Mistral tests
- [x] Create refactored OpenRouter tests
- [x] Create refactored Perplexity tests
- [x] Create refactored Ollama tests
- [x] Create refactored LMStudio tests
- [x] Create refactored Bumblebee tests
- [x] Run tag fixing script
- [ ] Verify all tests pass
- [ ] Remove old test files
- [ ] Update test documentation

## Testing the Refactoring

```bash
# Run all tests with new structure
mix test

# Run specific provider tests
mix test test/ex_llm/providers/anthropic_public_api_test.exs

# Run by tags
mix test --only streaming
mix test --only vision
mix test --only provider:anthropic
```