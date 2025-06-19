# Test Migration Guide

This guide documents the migration from provider-specific internal API tests to public API tests.

## Migration Status

### Completed Migrations

| Old Test File | New Test File | Status |
|--------------|---------------|---------|
| `anthropic_integration_test.exs` | `anthropic_public_api_test.exs` | ✅ Completed |
| `openai_integration_test.exs` | `openai_public_api_test.exs` | ✅ Completed |
| `gemini/integration_test.exs` | `gemini_public_api_test.exs` | ✅ Completed |
| `groq_integration_test.exs` | `groq_public_api_test.exs` | ✅ Completed |
| `mistral_integration_test.exs` | `mistral_public_api_test.exs` | ✅ Completed |
| `openrouter_integration_test.exs` | `openrouter_public_api_test.exs` | ✅ Completed |
| `perplexity_integration_test.exs` | `perplexity_public_api_test.exs` | ✅ Completed |
| `ollama_integration_test.exs` | `ollama_public_api_test.exs` | ✅ Completed |
| `lmstudio_integration_test.exs` | `lmstudio_public_api_test.exs` | ✅ Completed |
| `bumblebee_integration_test.exs` | `bumblebee_public_api_test.exs` | ✅ Completed |

### Key Changes

#### 1. API Usage
**Before:**
```elixir
Anthropic.chat(messages, max_tokens: 10)
OpenAI.stream_chat(messages)
Gemini.list_models()
```

**After:**
```elixir
ExLLM.chat(:anthropic, messages, max_tokens: 10)
ExLLM.stream(:openai, messages)
ExLLM.list_models(:gemini)
```

#### 2. Test Structure
**Before:** Each provider had all tests duplicated
**After:** 
- Common tests in `shared/provider_integration_test.exs`
- Provider-specific tests only in individual files
- Use `use ExLLM.Shared.ProviderIntegrationTest, provider: :provider_name`

#### 3. Tagging
All tests now have proper capability tags:
- `@tag :streaming` - For streaming tests
- `@tag :vision` - For vision/multimodal tests
- `@tag :function_calling` - For function/tool calling tests
- `@tag :embedding` - For embedding tests

## Running Tests

### Run all new tests
```bash
mix test test/ex_llm/providers/*_public_api_test.exs
```

### Run by provider
```bash
mix test test/ex_llm/providers/anthropic_public_api_test.exs
```

### Run by capability
```bash
mix test --only streaming
mix test --only vision
mix test --only function_calling
```

### Run shared tests only
```bash
mix test test/shared/provider_integration_test.exs
```

## Benefits of Migration

1. **API Stability**: Tests won't break when internal implementations change
2. **Reduced Duplication**: Common tests are shared across all providers
3. **Better Organization**: Clear separation between common and provider-specific tests
4. **Proper Tagging**: Easy to run specific test categories
5. **Maintainability**: Changes to test patterns only need to be made in one place

## Next Steps

1. Run all tests to ensure they pass
2. Remove old test files once verified
3. Update CI configuration to use new test structure
4. Update documentation to reflect new test organization