# Test Migration Spreadsheet

This document tracks the migration of tests from `@tag :skip` to meaningful tags.

## Summary
- Total tests with `@tag :skip`: 138
- CSV file generated: `test_migration_data.csv`
- Target: Migrate all tests to use descriptive tags

## Migration Progress

### By Provider
- Anthropic: 17 tests
- Gemini: 17 tests
- Ollama: 15 tests
- OpenRouter: 20 tests
- Perplexity: 14 tests
- Mistral: 14 tests
- LMStudio: 2 tests
- Unknown/Bumblebee: 39 tests

### By Pattern (from analysis)
- General/Other: 136 tests (need closer inspection)
- Quota sensitive: 2 tests
- Requires mock: 7 tests (inferred from comments)
- Requires API key: 16 tests (inferred from comments)
- Requires OAuth: 13 tests (inferred from comments)
- Requires service: 7 tests (inferred from comments)
- Requires resource: 66 tests (inferred from comments)

## Sample Migration Cases

| File | Test Description | Current Tag | Proposed Tags | Status |
|------|-----------------|-------------|---------------|--------|
| `test/ex_llm/adapters/gemini/models_test.exs:69` | returns error for network issues | `@tag :skip` | `@tag :unit`<br/>`@tag :requires_mock`<br/>`@tag provider: :gemini` | Pending |
| `test/ex_llm/adapters/lmstudio_unit_test.exs:416` | returns streaming response | `@tag :skip` | `@tag :unit`<br/>`@tag :requires_service`<br/>`@tag requires_service: :lmstudio`<br/>`@tag provider: :lmstudio` | Pending |
| `test/ex_llm/adapters/anthropic_integration_test.exs:43` | sends chat completion request | `@tag :skip` | `@tag :integration`<br/>`@tag :external`<br/>`@tag :live_api`<br/>`@tag :requires_api_key`<br/>`@tag provider: :anthropic` | Pending |
| `test/ex_llm/adapters/gemini/chunk_integration_test.exs:10` | creates and manages a chunk with API key | `@tag :skip` | `@tag :integration`<br/>`@tag :external`<br/>`@tag :requires_api_key`<br/>`@tag :requires_resource`<br/>`@tag requires_resource: :corpus`<br/>`@tag provider: :gemini` | Pending |
| `test/ex_llm/adapters/bumblebee_unit_test.exs:12` | returns true when Bumblebee is available and ModelLoader is running | `@tag :skip` | `@tag :unit`<br/>`@tag :requires_service`<br/>`@tag requires_service: :model_loader` | Pending |

## Migration Guidelines

### For Each Test:
1. Identify the reason for skipping
2. Determine appropriate tags:
   - Test type: `:unit`, `:integration`, `:e2e`
   - Requirements: `:requires_api_key`, `:requires_oauth`, `:requires_service`, `:requires_resource`
   - Provider: `provider: :gemini`, `provider: :anthropic`, etc.
   - Performance: `:slow`, `:very_slow`
   - Stability: `:flaky`, `:experimental`
   - External dependencies: `:external`, `:live_api`

### Migration Process:
1. Update the test with new tags
2. If using `ExLLM.Case`, requirement checks will be automatic
3. Test with appropriate mix aliases to ensure proper exclusion/inclusion

## Migration Batches (Recommended Order)

### Batch 1: Integration Tests (High Priority)
All tests in `*_integration_test.exs` files that require API keys:
- Update test module to `use ExLLM.Case` instead of `use ExUnit.Case`
- Add appropriate tags: `:integration`, `:external`, `:live_api`, `:requires_api_key`
- Add provider tag

### Batch 2: Service-Dependent Tests
Tests that require local services (Ollama, LMStudio):
- Add `:requires_service` tag with specific service
- These will auto-skip when service is not running

### Batch 3: Resource-Dependent Tests
Tests requiring pre-existing resources (corpus, documents, tuned models):
- Add `:requires_resource` tag with specific resource type
- Document required setup in test comments

### Batch 4: Mock/Unit Tests
Tests that need mocking infrastructure:
- Add `:unit` and `:requires_mock` tags
- Consider implementing mock helpers

### Batch 5: Bumblebee Tests
Local model tests that need special setup:
- Add appropriate service requirements
- Consider `:slow` tag for model loading

## Verification Commands

After migrating each batch:
```bash
# Run only unit tests (should exclude all integration)
mix test.fast

# Run specific provider tests with API key
ANTHROPIC_API_KEY=sk-xxx mix test.anthropic

# Run all tests including slow ones
mix test.all

# Check that skipped tests now use proper tags
grep -r "@tag :skip" test/ | wc -l  # Should decrease after each batch
```

## Next Steps
1. ✅ Analysis script created and run
2. ✅ CSV data generated for tracking
3. Start with Batch 1: Migrate integration tests
4. Create PR with migration changes
5. Update CONTRIBUTING.md with new test guidelines