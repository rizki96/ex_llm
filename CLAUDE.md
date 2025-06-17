# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Version Management

### When to Bump Versions
- **Patch version (0.x.Y)**: Bug fixes, documentation updates, minor improvements
- **Minor version (0.X.0)**: New features, non-breaking API changes, new provider adapters
- **Major version (X.0.0)**: Breaking API changes (after 1.0.0 release)

### Version Update Checklist
1. Update version in `mix.exs`
2. Update CHANGELOG.md with:
   - Version number and date
   - Added/Changed/Fixed/Removed sections
   - **BREAKING:** prefix for any breaking changes
3. Commit with message: `chore: bump version to X.Y.Z`

### CHANGELOG Format
```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features or providers

### Changed
- Changes in existing functionality
- **BREAKING:** API changes that break compatibility

### Fixed
- Bug fixes

### Removed
- Removed features
- **BREAKING:** Removed APIs
```

## Commands

### Development
```bash
# Run the application
iex -S mix

# Install dependencies
mix deps.get
mix deps.compile
```

### Testing

ExLLM includes a comprehensive testing system with intelligent caching and 24 specialized Mix aliases.

#### Basic Testing
```bash
# Run all tests (fast - uses cache when available)
mix test

# Run a specific test file
mix test test/ex_llm_test.exs

# Run tests at a specific line
mix test test/ex_llm_test.exs:42

# Run tests with coverage
mix test --cover
```

#### Provider-Specific Testing (24 Mix Aliases)
```bash
# Test individual providers
mix test.anthropic      # Anthropic Claude tests
mix test.openai         # OpenAI GPT tests  
mix test.gemini         # Google Gemini tests
mix test.groq           # Groq tests
mix test.mistral        # Mistral AI tests
mix test.openrouter     # OpenRouter tests
mix test.perplexity     # Perplexity tests
mix test.ollama         # Ollama local tests
mix test.lmstudio       # LM Studio tests
mix test.bumblebee      # Bumblebee local tests

# By test type
mix test.unit           # Unit tests only
mix test.integration    # Integration tests
mix test.external       # Tests with external calls
mix test.oauth2         # OAuth2 authentication tests

# By capability
mix test.streaming      # Streaming response tests
mix test.vision         # Vision/image processing tests
mix test.multimodal     # Multimodal input tests
mix test.function_calling # Function/tool calling tests
mix test.embedding      # Embedding generation tests

# By environment needs
mix test.live_api       # Tests calling live APIs
mix test.local_only     # Local-only tests (no API calls)
mix test.fast           # Fast tests (cached/mocked)
mix test.all            # All tests including slow ones
```

#### Test Caching (25x Speed Improvement)
```bash
# Tests with automatic caching
mix test.anthropic --include live_api

# Manage test cache
mix ex_llm.cache stats
mix ex_llm.cache clean --older-than 7d
mix ex_llm.cache clear
mix ex_llm.cache show anthropic

# Enable cache debugging
export EX_LLM_TEST_CACHE_ENABLED=true
export EX_LLM_LOG_LEVEL=debug
```

#### Running Tests with Tags
```bash
# Include specific test types
mix test --include live_api
mix test --include requires_api_key
mix test --include oauth2

# Run only specific tags
mix test --only provider:anthropic
mix test --only streaming
mix test --only integration

# Exclude problematic tests
mix test --exclude requires_service
mix test --exclude slow
```

### Code Quality
```bash
# Format code
mix format

# Run linter
mix credo

# Run type checker
mix dialyzer
```

### Debug Logging

ExLLM includes a comprehensive debug logging system that can be configured per environment:

```bash
# Test debug logging example
elixir examples/debug_logging_example.exs
```

**Configuration Options:**
- `log_level`: `:debug`, `:info`, `:warn`, `:error`, or `:none`
- `log_components`: Enable/disable logging for specific components
- `log_redaction`: Control redaction of sensitive data

**Development Environment:** Enhanced logging with all components enabled
**Test Environment:** Minimal logging to reduce noise  
**Production Environment:** Configurable logging with security redaction

### Documentation
```bash
# Generate documentation
mix docs

# Open documentation in browser
open doc/index.html
```

## Model Updates

### Updating Model Metadata

The project uses two methods to keep model configurations up-to-date:

1. **Sync from LiteLLM** (comprehensive metadata for all providers):
   ```bash
   # The wrapper script handles virtual environment automatically
   ./scripts/update_models.sh --litellm
   
   # Or manually with venv
   source .venv/bin/activate
   python scripts/sync_from_litellm.py
   ```
   - Updates configurations for all 56 providers (not just implemented ones)
   - Includes pricing, context windows, and capabilities
   - Requires LiteLLM repository to be cloned alongside this project

2. **Fetch from Provider APIs** (latest models from provider APIs):
   ```bash
   # Activate virtual environment first
   source .venv/bin/activate
   
   # Update all providers with APIs
   source ~/.env && uv run python scripts/fetch_provider_models.py
   
   # Or use the wrapper script (handles venv automatically)
   ./scripts/update_models.sh
   ```
   - Fetches latest models directly from provider APIs
   - Requires API keys in environment variables for some providers
   - Updates: Anthropic, OpenAI, Groq, Gemini, OpenRouter, Ollama

### Important Notes
- **Virtual Environment**: Always activate `.venv` before running Python scripts directly
- **Dependencies**: Python scripts require `pyyaml` and `requests` (installed in `.venv`)
- Always preserve custom default models (e.g., `gpt-4.1-nano` for OpenAI)
- The fetch script may reset defaults, so check and fix them after running
- Both scripts update YAML files in `config/models/`
- Commit changes with descriptive messages about what was updated
- **Use Python Virtual Environment and uv to interact with Python**

## Architecture Overview

ExLLM is a unified Elixir client for Large Language Models that provides a consistent interface across multiple providers. The architecture follows these key principles:

### Core Components

1. **Main Module (`lib/ex_llm.ex`)**: Entry point providing the unified API for all LLM operations. Delegates to appropriate adapters based on provider.

2. **Adapter Pattern (`lib/ex_llm/adapter.ex`)**: Defines the behavior that all provider implementations must follow. Each provider (Anthropic, OpenAI, Gemini, etc.) implements this behavior.

3. **Session Management (`lib/ex_llm/session.ex`)**: Manages conversation state across multiple interactions, tracking messages and token usage.

4. **Context Management (`lib/ex_llm/context.ex`)**: Handles message truncation and validation to ensure conversations fit within model context windows using different strategies (sliding_window, smart).

5. **Cost Tracking (`lib/ex_llm/cost.ex`)**: Automatically calculates and tracks API costs based on token usage and provider pricing.

6. **Test Caching System**: Advanced caching infrastructure for 25x faster integration tests
   - **Cache Storage (`lib/ex_llm/cache/storage/test_cache.ex`)**: JSON-based persistent storage
   - **Cache Detection (`lib/ex_llm/test_cache_detector.ex`)**: Smart detection of cacheable tests
   - **Response Interception (`lib/ex_llm/test_response_interceptor.ex`)**: Transparent HTTP caching
   - **Cache Management (`lib/mix/tasks/ex_llm.cache.ex`)**: Mix task for cache operations

7. **Instructor Integration (`lib/ex_llm/instructor.ex`)**: Optional integration for structured outputs with schema validation and retries.

### Provider Adapters

- **Anthropic Adapter (`lib/ex_llm/adapters/anthropic.ex`)**: Claude API integration with streaming support
- **OpenAI Adapter (`lib/ex_llm/adapters/openai.ex`)**: GPT and o1 models with function calling
- **Gemini Adapter (`lib/ex_llm/adapters/gemini.ex`)**: Complete Gemini API suite (15 APIs) with OAuth2
- **Groq Adapter (`lib/ex_llm/adapters/groq.ex`)**: Ultra-fast inference with Llama and DeepSeek
- **OpenRouter Adapter (`lib/ex_llm/adapters/openrouter.ex`)**: Access to 300+ models
- **Local Adapters**: Ollama, LM Studio, and Bumblebee for local model inference

### Configuration System

The library uses a pluggable configuration provider system (`lib/ex_llm/config_provider.ex`) that allows different configuration sources (environment variables, static config, custom providers).

### Type System

All data structures are defined in `lib/ex_llm/types.ex` with comprehensive typespecs for:
- `LLMResponse`: Standard response structure with content, usage, and cost data
- `StreamChunk`: Streaming response chunks
- `Model`: Model metadata including context windows and capabilities
- `Session`: Conversation state tracking

### Application Lifecycle

The `ExLLM.Application` module starts the supervision tree, including the optional `ModelLoader` GenServer for local model management.

## Key Design Patterns

1. **Unified Interface**: All providers expose the same API through the main `ExLLM` module
2. **Adapter Pattern**: Each provider implements the `ExLLM.Adapter` behavior
3. **Intelligent Test Caching**: Automatic response caching with smart cache invalidation
4. **Semantic Test Organization**: Tag-based test categorization with automatic requirement checking
5. **Optional Dependencies**: Features like local models and structured outputs are optional
6. **Automatic Cost Tracking**: Usage and costs are calculated transparently
7. **Context Window Management**: Automatic message truncation based on model limits
8. **Streaming Support**: Real-time responses with advanced coordinator and error recovery

## Provider Testing and API Keys

- Anytime you run live API tests, use the `scripts/run_with_env.sh` script to set the api keys