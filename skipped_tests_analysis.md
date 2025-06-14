# Analysis of Skipped Tests in ExLLM

## Summary

I found 43 tests marked with `@tag :skip` across 17 test files. These tests are grouped by reason below.

## Tests Skipped by Category

### 1. **API Key or Authentication Required** (19 tests)
These tests require valid API keys or OAuth tokens that may not be available in CI/test environments.

**Files affected:**
- `test/ex_llm/adapters/anthropic_integration_test.exs` (15 tests)
- `test/ex_llm/adapters/openrouter_integration_test.exs` (8 tests)
- `test/ex_llm/adapters/ollama_integration_test.exs` (4 tests)
- `test/ex_llm/adapters/perplexity_integration_test.exs` (7 tests)
- `test/ex_llm/adapters/mistral_integration_test.exs` (6 tests)

**Examples:**
- "sends chat completion request"
- "handles system messages"
- "respects temperature setting"
- "handles multimodal content with images"
- "streams chat responses"
- "handles streaming errors gracefully"
- "fetches available models from API"
- "handles rate limit errors"
- "handles invalid API key"
- "handles context length exceeded"
- "supports JSON mode output"
- "calculates costs accurately"

### 2. **Requires External Resources** (10 tests)
These tests need specific external resources like tuned models, corpora, or documents to exist.

**Files affected:**
- `test/ex_llm/adapters/gemini/tuning_test.exs` (8 tests)
- `test/ex_llm/adapters/gemini/chunk_integration_test.exs` (2 tests)
- `test/ex_llm/adapters/gemini/permissions_oauth2_test.exs` (1 test)

**Examples:**
- "creates a tuned model with basic configuration"
- "creates a tuned model with custom hyperparameters"
- "creates a tuned model with custom ID"
- "gets tuned model details"
- "updates tuned model metadata"
- "deletes a tuned model"
- "generates content using a tuned model"
- "streams content using a tuned model"
- "waits for tuning operation to complete"
- "creates and manages a chunk with API key"
- "batch operations work correctly"
- "creates and manages permissions"

### 3. **Beta or Experimental Features** (4 tests)
These tests are for beta features that may not be generally available.

**Files affected:**
- `test/ex_llm/adapters/anthropic_integration_test.exs` (2 tests)
- `test/ex_llm/adapters/gemini/content_test.exs` (1 test)

**Examples:**
- "message batches API" (Anthropic beta)
- "files API" (Anthropic beta)
- "generates content with thinking enabled" (Gemini experimental)

### 4. **Network/HTTP Mocking Required** (3 tests)
These tests require mocking the HTTP client for proper unit testing.

**Files affected:**
- `test/ex_llm/adapters/gemini/models_test.exs` (1 test)
- `test/ex_llm/adapters/lmstudio_unit_test.exs` (2 tests)

**Examples:**
- "returns error for network issues"
- "returns streaming response"
- "includes finish_reason in final chunk"

### 5. **Environment Setup Required** (4 tests)
These tests require specific environment setup or conditions.

**Files affected:**
- `test/ex_llm/adapters/bumblebee_integration_test.exs` (3 tests)
- `test/ex_llm/adapters/gemini/integration_test.exs` (1 test)

**Examples:**
- "generates response with specific model" (Bumblebee)
- "streaming respects max_tokens" (Bumblebee)
- "returns loaded models info when verbose" (Bumblebee)
- "returns true when Bumblebee and ModelLoader are available"
- "API modules use consistent authentication" (Gemini)

### 6. **Test Configuration Issues** (3 tests)
These tests have issues with test configuration or environment variables.

**Files affected:**
- `test/ex_llm/adapters/gemini/tokens_test.exs` (1 test)

**Examples:**
- "returns error for invalid API key" (get_api_key falls back to env vars)

## Recommendations

1. **For API Key Tests**: Consider using mock responses or VCR-style recording/playback for integration tests to avoid requiring real API keys in CI.

2. **For External Resource Tests**: Create test fixtures or mock responses for resources like tuned models and corpora.

3. **For Beta Features**: Keep these skipped until features are generally available, or create a separate test suite for beta features.

4. **For Network Mocking**: Implement proper HTTP client mocking in the test helper to enable these unit tests.

5. **For Environment Setup**: Document the required setup clearly and consider creating setup scripts for developers who want to run these tests locally.
