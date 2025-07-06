# ExLLM Test Tagging System Analysis

## Current Test Tagging System

### Current Tags in Use

Based on analysis of the codebase, ExLLM currently uses the following tags:

#### 1. Test Type Tags
- **`:integration`** - Tests requiring external services or API calls
- **`:external`** - Tests calling external APIs (subset of integration)
- **`:live_api`** - Tests requiring live API calls (not cached)
- **`:unit`** - Pure unit tests (no external dependencies)

#### 2. Stability/Performance Tags
- **`:slow`** - Tests that take >5 seconds
- **`:very_slow`** - Tests that take >30 seconds
- **`:flaky`** - Tests with intermittent failures
- **`:wip`** - Work-in-progress tests
- **`:quota_sensitive`** - Tests consuming significant API quota
- **`:performance`** - Performance benchmarking tests

#### 3. Capability Tags (Current)
- **`:streaming`** - Streaming response tests
- **`:vision`** - Vision/image processing tests
- **`:multimodal`** - Multimodal content tests
- **`:model_loading`** - Model loading tests (Bumblebee)

#### 4. Provider Tags (Current Format)
- **`provider: :anthropic`** - Anthropic Claude tests
- **`provider: :openai`** - OpenAI GPT tests
- **`provider: :gemini`** - Google Gemini tests
- **`provider: :groq`** - Groq tests
- **`provider: :ollama`** - Ollama tests
- **`provider: :lmstudio`** - LM Studio tests
- **`provider: :bumblebee`** - Bumblebee tests
- **`provider: :mistral`** - Mistral tests
- **`provider: :xai`** - XAI tests
- **`provider: :perplexity`** - Perplexity tests
- **`provider: :openrouter`** - OpenRouter tests

#### 5. Requirement Tags
- **`:requires_api_key`** - Tests needing API authentication
- **`:requires_oauth`** / **`:oauth2`** - Tests needing OAuth2 authentication
- **`:requires_service`** - Tests needing local services
- **`:requires_resource`** - Tests needing specific resources
- **`:requires_deps`** - Tests requiring optional dependencies (Bumblebee)
- **`:local_only`** - Tests that can only run with local models

### Current Mix Aliases

```elixir
# Core testing strategy
"test.live"         # Live API tests (forces live mode)
"test.fast"         # Excludes API calls and slow tests
"test.unit"         # Unit tests only
"test.integration"  # Integration tests
"test.all"          # All tests including slow

# Provider-specific
"test.anthropic"    # Anthropic tests only
"test.openai"       # OpenAI tests only
"test.gemini"       # Gemini tests only
"test.local"        # Ollama + LM Studio tests
"test.bumblebee"    # Bumblebee tests

# Specialized
"test.oauth2"       # OAuth2 tests
"test.ci"           # CI pipeline tests
```

## Comparison with Proposed Strategy

### Tag Structure Comparison

| Category | Current System | Proposed System | Gap Analysis |
|----------|----------------|-----------------|--------------|
| **Test Types** | `:unit`, `:integration`, `:external`, `:live_api` | `:unit`, `:integration`, `:live`, `:mock` | Need to add `:mock` tag, rename `:live_api` to `:live` |
| **Capabilities** | `:streaming`, `:vision`, `:multimodal`, `:model_loading` | `capability: :chat`, `:streaming`, `:models`, `:functions`, `:vision`, `:tools` | Need standardized `capability:` prefix and add missing capabilities |
| **Providers** | `provider: :name` format ✓ | `provider: :name` format ✓ | Already aligned ✓ |
| **Stability** | Comprehensive set ✓ | Not specified | Current system is more complete |
| **Requirements** | Comprehensive set ✓ | Not specified | Current system is more complete |

### Key Differences and Gaps

#### 1. Missing Tags in Current System
- **`:mock`** - No explicit tag for mocked integration tests
- **`capability: :chat`** - Basic chat not tagged as capability
- **`capability: :functions`** - Function calling not tagged
- **`capability: :tools`** - Tool use not tagged
- **`capability: :models`** - Model listing not tagged

#### 2. Naming Inconsistencies
- Current: `:live_api` vs Proposed: `:live`
- Current: Individual capability tags vs Proposed: `capability:` prefix

#### 3. Missing Mix Aliases (from proposed)
- `test.mock` - Test mocked integrations
- `test.capability` - Test specific capabilities
- `test.smoke` - Quick smoke tests
- `test.matrix` - Full matrix report
- Provider-specific live tests (e.g., `test.live.openai`)

#### 4. Directory Structure
Current structure doesn't match proposed organization:
- No separation of `unit/`, `integration/live/`, `integration/mock/`
- Tests organized by module rather than test type

## Recommendations for Mapping

### 1. Tag Migration Strategy

```elixir
# Phase 1: Add missing tags without breaking existing
@tag :mock           # Add to mocked integration tests
@tag capability: :chat       # Add to basic chat tests
@tag capability: :functions  # Add to function calling tests
@tag capability: :tools      # Add to tool use tests
@tag capability: :models     # Add to model listing tests

# Phase 2: Create aliases for compatibility
# In test_helper.exs
if tags[:live_api], do: tags[:live] = true
```

### 2. Mix Alias Additions

```elixir
# Add to mix.exs aliases
"test.mock": ["test --only mock"],
"test.smoke": ["test --only unit --only mock --exclude slow"],
"test.capability": &test_capability/1,
"test.matrix": ["test.live", "run -e ExLLM.Testing.MatrixReporter.generate()"],

# Provider-specific live tests
"test.live.openai": ["test --only live --only provider:openai"],
"test.live.anthropic": ["test --only live --only provider:anthropic"],
# ... etc for other providers
```

### 3. Gradual Migration Path

#### Week 1: Tag Enhancement
1. Add `capability:` prefix to existing capability tags
2. Add `:mock` tag to appropriate tests
3. Add missing capability tags (`:chat`, `:functions`, `:tools`, `:models`)

#### Week 2: Mix Aliases
1. Add new mix aliases for proposed functionality
2. Keep existing aliases for backward compatibility
3. Update documentation

#### Week 3: Directory Reorganization (Optional)
1. Consider reorganizing test directory structure
2. Move tests to appropriate subdirectories
3. Update import paths

### 4. Backward Compatibility

Maintain both tag systems during transition:
```elixir
# Support both formats
@tag :streaming
@tag capability: :streaming

# Or use a macro
use ExLLM.Testing.Tags, capabilities: [:streaming, :chat]
```

## Summary

The current ExLLM test tagging system is already quite sophisticated and covers many of the proposed concepts. The main gaps are:

1. **Capability tagging standardization** - Need consistent `capability:` prefix
2. **Mock test identification** - Need explicit `:mock` tag
3. **Additional mix aliases** - For capability and matrix testing
4. **Minor naming alignment** - `:live_api` → `:live`

The current system's strength is its comprehensive requirement and stability tags, which go beyond the proposed strategy. The transition can be done gradually without breaking existing tests.