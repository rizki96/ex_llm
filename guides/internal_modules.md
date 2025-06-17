# Internal Modules Guide

This document lists all internal modules in ExLLM that should NOT be used directly. These are implementation details subject to change without notice.

## ⚠️ WARNING

All modules listed here are internal to ExLLM. Always use the public API through the main `ExLLM` module instead.

## Core Internal Modules

### Infrastructure Layer
- `ExLLM.Infrastructure.Cache.*` - Internal caching implementation
- `ExLLM.Infrastructure.CircuitBreaker.*` - Fault tolerance internals
- `ExLLM.Infrastructure.Config.*` - Configuration management
- `ExLLM.Infrastructure.Logger` - Internal logging
- `ExLLM.Infrastructure.Retry` - Retry logic implementation
- `ExLLM.Infrastructure.Streaming.*` - Streaming implementation details
- `ExLLM.Infrastructure.Error` - Error structure definitions

### Provider Shared Utilities
- `ExLLM.Providers.Shared.ConfigHelper` - Provider config utilities
- `ExLLM.Providers.Shared.ErrorHandler` - Error handling
- `ExLLM.Providers.Shared.HTTPClient` - HTTP implementation
- `ExLLM.Providers.Shared.MessageFormatter` - Message formatting
- `ExLLM.Providers.Shared.ModelFetcher` - Model fetching logic
- `ExLLM.Providers.Shared.ModelUtils` - Model utilities
- `ExLLM.Providers.Shared.ResponseBuilder` - Response construction
- `ExLLM.Providers.Shared.StreamingBehavior` - Streaming behavior
- `ExLLM.Providers.Shared.StreamingCoordinator` - Stream coordination
- `ExLLM.Providers.Shared.Validation` - Input validation
- `ExLLM.Providers.Shared.VisionFormatter` - Vision formatting

### Provider Internals
- `ExLLM.Providers.Gemini.*` - Gemini-specific internals
- `ExLLM.Providers.Bumblebee.*` - Bumblebee internals
- `ExLLM.Providers.OpenAICompatible` - Base module for providers

### Testing Infrastructure
- `ExLLM.Testing.Cache.*` - Test caching system
- `ExLLM.Testing.ResponseCache` - Response caching for tests
- All modules in `test/support/*` - Test helpers

## Why These Are Internal

1. **Implementation Details**: These modules contain implementation-specific logic that may change between versions
2. **No Stability Guarantees**: Internal APIs can change without deprecation notices
3. **Complex Dependencies**: Many internal modules have complex interdependencies
4. **Provider-Specific**: Provider internals are tailored to specific API requirements

## Migration Guide

If you're currently using any internal modules, here's how to migrate:

### Cache Access
```elixir
# ❌ Don't use internal cache modules
ExLLM.Infrastructure.Cache.get(key)

# ✅ Use the public API
# Caching is handled automatically by ExLLM
{:ok, response} = ExLLM.chat(:openai, "Hello")
```

### Error Handling
```elixir
# ❌ Don't create internal error types
ExLLM.Infrastructure.Error.api_error(500, "Error")

# ✅ Use pattern matching on public API returns
case ExLLM.chat(:openai, "Hello") do
  {:error, {:api_error, status, message}} -> 
    # Handle error
end
```

### Configuration
```elixir
# ❌ Don't access internal config modules
ExLLM.Infrastructure.Config.ModelConfig.get_model(:openai, "gpt-4")

# ✅ Use public configuration API
{:ok, info} = ExLLM.get_model_info(:openai, "gpt-4")
```

### HTTP Requests
```elixir
# ❌ Don't use internal HTTP client
ExLLM.Providers.Shared.HTTPClient.post_json(url, body, headers)

# ✅ Use the public API which handles HTTP internally
{:ok, response} = ExLLM.chat(:openai, "Hello")
```

### Provider Implementation
```elixir
# ❌ Don't use provider internals directly
ExLLM.Providers.Anthropic.chat(messages, options)

# ✅ Use the unified public API
{:ok, response} = ExLLM.chat(:anthropic, messages, options)
```

## For Library Contributors

If you're contributing to ExLLM:

1. Keep internal modules marked with `@moduledoc false`
2. Don't expose internal functions in the public API
3. Add new public functionality to the main `ExLLM` module
4. Document any new internal modules in this guide
5. Ensure internal modules are properly namespaced

## Questions?

If you need functionality that's only available in internal modules, please:
1. Check if the public API already provides it
2. Open an issue requesting the feature
3. Consider contributing a PR that exposes it properly through the public API