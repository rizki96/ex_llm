# ExLLM Test Tagging Guide

## Overview

This guide standardizes test tagging across the ExLLM test suite to improve test organization, execution efficiency, and maintainability.

## Tag Categories

### 1. Execution Tags

**Purpose**: Control test execution based on requirements and performance characteristics.

```elixir
@moduletag :integration     # Integration tests requiring external services
@moduletag :external        # Tests that make external API calls
@moduletag :live_api        # Tests requiring live API access
@moduletag :requires_api_key # Tests requiring API key configuration
@moduletag :slow            # Tests taking 5-30 seconds
@moduletag :very_slow       # Tests taking 30+ seconds
@moduletag :quota_sensitive # Tests that consume significant API quota
@moduletag :flaky           # Tests with known intermittent failures
@moduletag :skip            # Tests to skip (with reason in test name)
```

### 2. Provider Tags

**Purpose**: Organize tests by LLM provider for targeted execution.

```elixir
@moduletag provider: :anthropic
@moduletag provider: :openai
@moduletag provider: :gemini
@moduletag provider: :groq
@moduletag provider: :mistral
@moduletag provider: :xai
@moduletag provider: :perplexity
@moduletag provider: :ollama
@moduletag provider: :lmstudio
@moduletag provider: :bumblebee
@moduletag provider: :mock
```

### 3. Capability Tags

**Purpose**: Group tests by functionality for feature-specific testing.

```elixir
# Core Capabilities
@moduletag :chat              # Basic chat completion
@moduletag :streaming         # Streaming responses
@moduletag :function_calling  # Tool/function calling
@moduletag :vision           # Image/visual processing
@moduletag :embedding        # Text embeddings
@moduletag :multimodal       # Multi-modal content

# Unified API Capabilities
@moduletag :unified_api      # All unified API tests
@moduletag :file_management  # File upload/management
@moduletag :context_caching  # Context caching features
@moduletag :knowledge_bases  # Knowledge base management
@moduletag :fine_tuning      # Model fine-tuning
@moduletag :assistants       # Assistants API
@moduletag :batch_processing # Batch processing
@moduletag :token_counting   # Token counting utilities

# Specialized Features
@moduletag :oauth2           # OAuth2 authentication tests
@moduletag :permissions      # Permission management
@moduletag :model_loading    # Local model loading
@moduletag :circuit_breaker  # Circuit breaker functionality
@moduletag :retry_logic      # Retry mechanisms
```

### 4. Test Type Tags

**Purpose**: Distinguish between different types of tests.

```elixir
@moduletag :unit             # Unit tests (fast, isolated)
@moduletag :integration_test # Integration tests
@moduletag :performance      # Performance benchmarks
@moduletag :security         # Security-focused tests
@moduletag :regression       # Regression tests
```

### 5. Infrastructure Tags

**Purpose**: Tag tests related to infrastructure and tooling.

```elixir
@moduletag :cache_test       # Test caching functionality
@moduletag :telemetry        # Telemetry and monitoring
@moduletag :config           # Configuration management
@moduletag :pipeline         # Pipeline processing
```

## Tag Usage Examples

### Basic Provider Test
```elixir
defmodule ExLLM.Providers.OpenAITest do
  use ExUnit.Case
  
  @moduletag :unit
  @moduletag provider: :openai
  @moduletag :chat
  
  # Tests here...
end
```

### Integration Test with Multiple Tags
```elixir
defmodule ExLLM.API.FileManagementTest do
  use ExUnit.Case, async: false
  
  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :unified_api
  @moduletag :file_management
  
  # Tests here...
end
```

### OAuth2 Test with Specialized Tags
```elixir
defmodule ExLLM.Providers.Gemini.OAuth2.CorpusTest do
  use ExLLM.Testing.OAuth2TestCase
  
  @moduletag provider: :gemini
  @moduletag :oauth2
  @moduletag :knowledge_bases
  @moduletag :slow
  @moduletag :quota_sensitive
  
  # Tests here...
end
```

## Test Execution Commands

### By Provider
```bash
# Run all Gemini tests
mix test --include provider:gemini

# Run all OpenAI tests  
mix test --include provider:openai
```

### By Capability
```bash
# Run all streaming tests
mix test --include streaming

# Run all unified API tests
mix test --include unified_api

# Run file management tests
mix test --include file_management
```

### By Execution Type
```bash
# Run only unit tests (fast)
mix test --include unit --exclude integration

# Run integration tests with API keys
mix test --include integration --include live_api

# Run slow tests
mix test --include slow --include very_slow
```

### Combined Filtering
```bash
# Run Gemini OAuth2 tests
mix test --include provider:gemini --include oauth2

# Run all unified API tests except slow ones
mix test --include unified_api --exclude slow

# Run streaming tests for specific providers
mix test --include streaming --include provider:openai --include provider:anthropic
```

## Migration Guidelines

### Updating Existing Tests

1. **Add Missing Provider Tags**: Ensure all provider-specific tests have provider tags
2. **Add Capability Tags**: Add appropriate capability tags to all tests
3. **Standardize Execution Tags**: Use consistent execution tags (`:slow` vs `:very_slow`)
4. **Update OAuth2 Tags**: Migrate from `:oauth2` to `:requires_oauth` where appropriate

### Example Migration

**Before:**
```elixir
@moduletag :integration
@moduletag :oauth2
```

**After:**
```elixir
@moduletag :integration
@moduletag :external
@moduletag :live_api
@moduletag :requires_api_key
@moduletag provider: :gemini
@moduletag :oauth2
@moduletag :knowledge_bases
@moduletag :slow
```

## Benefits

1. **Improved Test Organization**: Clear categorization of all tests
2. **Efficient Test Execution**: Run only relevant tests for specific features
3. **Better CI/CD Integration**: Separate fast and slow test suites
4. **Enhanced Developer Experience**: Easy to find and run specific test types
5. **Consistent Patterns**: Standardized approach across all test files

## Enforcement

- Add tag validation to CI/CD pipeline
- Use mix tasks to verify tag consistency
- Include tag requirements in PR review checklist
- Update documentation when adding new tag categories
