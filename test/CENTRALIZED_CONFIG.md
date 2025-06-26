# Centralized Test Configuration

ExLLM uses a centralized test configuration system to ensure consistent behavior across all test environments. This documentation explains the structure and benefits of the centralized approach.

## Overview

Test configuration is centralized in `ExLLM.Testing.Config` module, which provides:

- **Single source of truth** for all test-related settings
- **Consistent behavior** across different test environments
- **Easy maintenance** - changes in one place affect all tests
- **Clear documentation** of test categories and requirements

## Configuration Components

### 1. Test Categories & Tags

Tests are organized using semantic ExUnit tags:

```elixir
# Core categories
@tag :unit              # Pure unit tests (no external dependencies)
@tag :integration       # Tests requiring external services
@tag :external          # Tests calling external APIs
@tag :live_api          # Tests requiring live API calls (not cached)

# Stability categories  
@tag :slow              # Tests taking >5 seconds
@tag :very_slow         # Tests taking >30 seconds
@tag :flaky             # Tests with intermittent failures
@tag :wip               # Work-in-progress tests
@tag :quota_sensitive   # Tests consuming significant API quota

# Provider categories
@tag provider: :anthropic
@tag provider: :openai
# etc.

# Requirement categories
@tag :requires_api_key
@tag :requires_oauth
@tag :requires_service
```

### 2. Test Exclusion Strategies

The system provides different exclusion strategies based on context:

#### Default Strategy (Hybrid)
- **Cache Fresh**: Includes integration tests using cached responses
- **Cache Stale**: Excludes all external/integration tests
- **Live Mode**: Forces live API calls when `MIX_RUN_LIVE=true`

#### CI Strategy
- Excludes: `wip`, `flaky`, `quota_sensitive`, `very_slow`
- Used by GitHub Actions CI workflow

#### Fast Strategy  
- Excludes: `live_api`, `external`, `integration`, `slow`
- For rapid local development

### 3. Configuration Sources

Settings are applied in this order (later overrides earlier):

1. **config/config.exs** - Base application config
2. **config/test.exs** - Test environment config  
3. **ExLLM.Testing.Config** - Centralized test config
4. **test_helper.exs** - Runtime application of centralized config
5. **Environment variables** - Runtime overrides

## Usage

### In Test Files

```elixir
defmodule MyTest do
  use ExLLM.Testing.Case, async: true
  
  @tag :requires_api_key
  @tag provider: :openai
  test "calls OpenAI API" do
    # Test automatically skips if OPENAI_API_KEY not set
  end
end
```

### In Mix Aliases

```elixir
# mix.exs
"test.ci": ["test --exclude wip --exclude flaky --exclude quota_sensitive --exclude very_slow"]
```

The aliases use the exclusion strategies from `ExLLM.Testing.Config`.

### Environment Variables

```bash
# Enable test caching
export EX_LLM_TEST_CACHE_ENABLED=true

# Force live API calls
export MIX_RUN_LIVE=true

# Enable debug logging in tests
export EX_LLM_LOG_LEVEL=debug

# Custom .env file location
export EX_LLM_ENV_FILE=.env.test
```

## Benefits

### 1. Maintainability
- Single place to update test configuration
- No duplication across multiple files
- Clear separation of concerns

### 2. Consistency
- All test environments use the same logic
- Mix aliases and ExUnit configuration stay in sync
- Predictable behavior across development/CI

### 3. Flexibility
- Easy to add new test categories
- Environment-based overrides supported
- Different strategies for different contexts

### 4. Developer Experience
- Clear documentation of test requirements
- Automatic skipping with meaningful messages
- Easy to run specific test subsets

## Migration Benefits

Before centralization:
- Test configuration scattered across 5+ files
- Duplicated exclusion logic in mix.exs and test_helper.exs
- Inconsistent behavior between local and CI testing
- Hard to maintain and extend

After centralization:
- ✅ Single source of truth in `ExLLM.Testing.Config`
- ✅ Mix aliases automatically use centralized exclusions
- ✅ Consistent behavior across all environments  
- ✅ Easy to add new test categories and strategies
- ✅ Clear documentation and examples

## File Structure

```
lib/ex_llm/testing/
├── config.ex                  # Centralized configuration
└── ...

test/
├── test_helper.exs            # Applies centralized config
├── support/
│   ├── testing_case.ex        # Uses centralized provider mappings
│   ├── env_helper.ex          # Uses centralized API key list
│   └── ...
└── CENTRALIZED_CONFIG.md      # This documentation

config/
├── config.exs                 # Minimal test config
└── test.exs                   # Delegates to centralized config
```

## Future Enhancements

The centralized system makes it easy to add:

- **Custom test strategies** for different team workflows
- **Dynamic configuration** based on available services
- **Performance monitoring** integration
- **Test result analytics** and reporting
- **Parallel test execution** optimization