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
```bash
# Run all tests
mix test

# Run a specific test file
mix test test/ex_llm_test.exs

# Run tests at a specific line
mix test test/ex_llm_test.exs:42

# Run only integration tests
mix test test/*_integration_test.exs

# Run tests with coverage
mix test --cover
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

### Documentation
```bash
# Generate documentation
mix docs

# Open documentation in browser
open doc/index.html
```

## Architecture Overview

ExLLM is a unified Elixir client for Large Language Models that provides a consistent interface across multiple providers. The architecture follows these key principles:

### Core Components

1. **Main Module (`lib/ex_llm.ex`)**: Entry point providing the unified API for all LLM operations. Delegates to appropriate adapters based on provider.

2. **Adapter Pattern (`lib/ex_llm/adapter.ex`)**: Defines the behavior that all provider implementations must follow. Each provider (Anthropic, Local, etc.) implements this behavior.

3. **Session Management (`lib/ex_llm/session.ex`)**: Manages conversation state across multiple interactions, tracking messages and token usage.

4. **Context Management (`lib/ex_llm/context.ex`)**: Handles message truncation and validation to ensure conversations fit within model context windows using different strategies (sliding_window, smart).

5. **Cost Tracking (`lib/ex_llm/cost.ex`)**: Automatically calculates and tracks API costs based on token usage and provider pricing.

6. **Instructor Integration (`lib/ex_llm/instructor.ex`)**: Optional integration for structured outputs with schema validation and retries.

### Provider Adapters

- **Anthropic Adapter (`lib/ex_llm/adapters/anthropic.ex`)**: Implements Claude API integration with streaming support
- **Local Adapter (`lib/ex_llm/adapters/local.ex`)**: Enables running models locally using Bumblebee/EXLA

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
3. **Optional Dependencies**: Features like local models and structured outputs are optional
4. **Automatic Cost Tracking**: Usage and costs are calculated transparently
5. **Context Window Management**: Automatic message truncation based on model limits
6. **Streaming Support**: Real-time responses via Server-Sent Events where supported