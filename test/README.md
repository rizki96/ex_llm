# ExLLM Test Suite

This directory contains comprehensive tests for the ExLLM library, covering all adapters, features, and integration scenarios.

## Test Structure

The test suite is organized into different categories:

### Unit Tests
- **Location**: `test/ex_llm/adapters/*_unit_test.exs`
- **Purpose**: Test adapter logic without requiring API access
- **Run by default**: Always executed in CI/CD and local development
- **Requirements**: No API keys needed

### Integration Tests
- **Location**: `test/ex_llm/adapters/*_integration_test.exs`
- **Purpose**: Test against real APIs and services
- **Tagged with**: `:skip` by default to prevent accidental API usage
- **Requirements**: Valid API keys and/or running services

### Core Library Tests
- **Location**: `test/ex_llm/*_test.exs`
- **Purpose**: Test core ExLLM functionality (sessions, contexts, costs, etc.)
- **Run by default**: Always executed

## Running Tests

### Run All Tests (Default)
```bash
# Run all unit tests and core library tests
mix test

# Run with coverage
mix test --cover
```

### Run Tests for Specific Adapters

#### OpenAI Tests
```bash
# Unit tests only (no API key required)
mix test test/ex_llm/adapters/openai_unit_test.exs

# Integration tests (requires OPENAI_API_KEY)
mix test test/ex_llm/adapters/openai_integration_test.exs --include openai

# Run both with API key loaded
./scripts/run_with_env.sh mix test test/ex_llm/adapters/openai_*_test.exs --include openai
```

#### Anthropic Tests
```bash
# Unit tests only (no API key required)
mix test test/ex_llm/adapters/anthropic_unit_test.exs

# Integration tests (requires ANTHROPIC_API_KEY)
mix test test/ex_llm/adapters/anthropic_integration_test.exs --include anthropic

# Run both with API key loaded
./scripts/run_with_env.sh mix test test/ex_llm/adapters/anthropic_*_test.exs --include anthropic
```

#### OpenRouter Tests
```bash
# Unit tests only (no API key required)
mix test test/ex_llm/adapters/openrouter_unit_test.exs

# Integration tests (requires OPENROUTER_API_KEY)
mix test test/ex_llm/adapters/openrouter_integration_test.exs --include openrouter

# Run both with API key loaded
./scripts/run_with_env.sh mix test test/ex_llm/adapters/openrouter_*_test.exs --include openrouter
```

#### Ollama Tests
```bash
# Unit tests only (no server required)
mix test test/ex_llm/adapters/ollama_unit_test.exs

# Integration tests (requires running Ollama server)
mix test test/ex_llm/adapters/ollama_integration_test.exs --include ollama

# Run both with Ollama server running
mix test test/ex_llm/adapters/ollama_*_test.exs --include ollama
```

### Run Integration Tests by Provider

```bash
# Run all OpenAI integration tests
./scripts/run_with_env.sh mix test --only openai

# Run all Anthropic integration tests
./scripts/run_with_env.sh mix test --only anthropic

# Run all OpenRouter integration tests
./scripts/run_with_env.sh mix test --only openrouter

# Run all Ollama integration tests (requires Ollama server)
mix test --only ollama

# Run all integration tests with API keys
./scripts/run_with_env.sh mix test --only integration
```

### Run Specific Test Categories

```bash
# Run only streaming tests
mix test --only streaming

# Run only function calling tests
mix test --only function_calling

# Run only vision/multimodal tests
mix test --only vision

# Run only cost calculation tests
mix test --only cost
```

## Environment Setup

### API Keys
Set these environment variables for integration tests:

```bash
# OpenAI
export OPENAI_API_KEY="sk-..."

# Anthropic
export ANTHROPIC_API_KEY="sk-ant-..."

# OpenRouter
export OPENROUTER_API_KEY="sk-or-..."
export OPENROUTER_APP_NAME="ExLLM Test"          # Optional
export OPENROUTER_APP_URL="https://example.com"  # Optional

# Other providers (if testing)
export GROQ_API_KEY="gsk_..."
export GEMINI_API_KEY="..."
```

### Using Environment File
Create `~/.env` file with your API keys:

```bash
# ~/.env
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
OPENROUTER_API_KEY=sk-or-...
```

Then use the environment script:
```bash
./scripts/run_with_env.sh mix test --only integration
```

### Ollama Setup
For Ollama integration tests:

```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Start Ollama service
ollama serve

# Pull a test model (optional, tests will work without)
ollama pull llama3.2:1b
```

## Test Tags and Filtering

### Available Tags
- `:integration` - All integration tests
- `:openai` - OpenAI-specific tests
- `:anthropic` - Anthropic-specific tests
- `:openrouter` - OpenRouter-specific tests
- `:ollama` - Ollama-specific tests
- `:skip` - Tests skipped by default
- `:streaming` - Streaming functionality tests
- `:function_calling` - Function/tool calling tests
- `:vision` - Vision/multimodal tests
- `:cost` - Cost calculation tests

### Filtering Examples
```bash
# Include only specific tags
mix test --only openai
mix test --only streaming

# Exclude specific tags
mix test --exclude integration
mix test --exclude skip

# Multiple tags
mix test --only "openai and streaming"
mix test --exclude "integration or skip"
```

## Test Development Guidelines

### Adding New Tests
1. **Unit Tests**: Add to appropriate `*_unit_test.exs` file
2. **Integration Tests**: Add to appropriate `*_integration_test.exs` file
3. **New Adapters**: Follow the established pattern:
   - Create `adapter_name_unit_test.exs`
   - Create `adapter_name_integration_test.exs`
   - Tag integration tests with `:skip` and `:adapter_name`

### Test Structure Pattern
```elixir
defmodule ExLLM.Adapters.ProviderUnitTest do
  use ExUnit.Case, async: true
  alias ExLLM.Adapters.Provider
  
  describe "configuration" do
    test "configured?/1 returns boolean" do
      # Test configuration logic
    end
  end
  
  describe "core functionality" do
    test "chat handles basic messages" do
      # Test without API calls
    end
  end
end
```

```elixir
defmodule ExLLM.Adapters.ProviderIntegrationTest do
  use ExUnit.Case
  alias ExLLM.Adapters.Provider
  
  @moduletag :integration
  @moduletag :provider_name
  @moduletag :skip
  
  describe "live API tests" do
    @tag :skip
    test "chat works with real API" do
      # Test with real API calls
    end
  end
end
```

## Continuous Integration

### CI Configuration
The test suite is designed to work in CI environments:

```bash
# CI runs unit tests by default (no API keys needed)
mix test

# Optional: Run integration tests in CI with secrets
OPENAI_API_KEY=${{ secrets.OPENAI_API_KEY }} mix test --only openai
```

### GitHub Actions Example
```yaml
- name: Run unit tests
  run: mix test

- name: Run integration tests
  env:
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  run: mix test --only integration
  if: env.OPENAI_API_KEY != ''
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
# Make sure to include the provider tag
mix test --include openai test/ex_llm/adapters/openai_integration_test.exs

# Or remove @skip tags in the test files
```

#### API Rate Limits
```bash
# Run tests sequentially to avoid rate limits
mix test --max-cases 1 --only integration
```

#### Missing Models (Ollama)
```bash
# Pull required models
ollama pull llama3.2:1b
ollama pull nomic-embed-text

# Or run tests that don't require specific models
mix test test/ex_llm/adapters/ollama_unit_test.exs
```

### Debugging Test Failures
```bash
# Run with detailed output
mix test --trace

# Run single test with maximum verbosity
mix test test/path/to/test.exs:line_number --trace

# Check ExLLM logs
ELIXIR_LOG_LEVEL=debug mix test
```

## Performance Testing

### Load Testing
```bash
# Test with multiple concurrent requests
mix test --only "integration and streaming" --max-cases 10
```

### Memory Usage
```bash
# Monitor memory during tests
mix test --cover --export-coverage default.coverdata
```

## Contributing

When adding new tests:

1. **Follow the pattern**: Use the same structure as existing adapter tests
2. **Tag appropriately**: Add relevant tags for filtering
3. **Document requirements**: Note any special setup needed
4. **Test both success and error cases**: Include negative testing
5. **Keep integration tests focused**: Test real API behavior, not edge cases
6. **Use meaningful assertions**: Test actual functionality, not just structure

### Pull Request Checklist
- [ ] Unit tests pass without API keys
- [ ] Integration tests pass with API keys
- [ ] New tests follow established patterns
- [ ] Tests are properly tagged
- [ ] Documentation updated if needed