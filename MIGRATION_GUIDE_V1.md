# ExLLM v1.0.0 Migration Guide

This guide helps you upgrade from ExLLM v0.x to v1.0.0.

## Overview

ExLLM v1.0.0 is a major release that introduces significant architectural improvements while maintaining full backward compatibility. The main changes focus on modularization, improved provider support, and enhanced developer experience.

## What's New in v1.0.0

### 🏗️ Modular Architecture

The monolithic ExLLM module has been split into focused, single-responsibility modules:

- **`ExLLM.Embeddings`** - Vector operations and similarity search
- **`ExLLM.Assistants`** - OpenAI Assistants API support
- **`ExLLM.KnowledgeBase`** - Semantic search and document management
- **`ExLLM.Builder`** - Fluent chat interface for building requests
- **`ExLLM.Session`** - Conversation state management

### 🚀 Provider Delegation System

A new centralized provider delegation system improves consistency and reduces code duplication:

- **`ExLLM.API.Delegator`** - Central routing for all provider calls
- **`ExLLM.API.Capabilities`** - Provider feature registry
- **`ExLLM.API.Transformers`** - Argument normalization

### 📊 Enhanced Features

- **Unified API** - Consistent interface across all providers
- **Improved Error Handling** - Standardized error responses
- **Better Type Safety** - Enhanced typespecs and Dialyzer support
- **Test Infrastructure** - Comprehensive test coverage with smart caching

## Breaking Changes

**Good news!** There are **NO breaking changes** in v1.0.0. All existing code will continue to work without modification.

## Migration Steps

### 1. Update Your Dependencies

```elixir
# In mix.exs
def deps do
  [
    {:ex_llm, "~> 1.0.0-rc1"}
  ]
end
```

### 2. Run Dependency Update

```bash
mix deps.update ex_llm
mix deps.compile
```

### 3. Optional: Adopt New Module Structure

While not required, you can take advantage of the new modular structure for cleaner code:

#### Before (v0.x)
```elixir
# All functions through main module
{:ok, response} = ExLLM.embeddings(:openai, "Hello world")
results = ExLLM.find_similar(query_embedding, items)
{:ok, assistant} = ExLLM.create_assistant(:openai, name: "Helper")
```

#### After (v1.0) - Optional
```elixir
# Use specialized modules for clearer intent
{:ok, response} = ExLLM.Embeddings.generate(:openai, "Hello world")
results = ExLLM.Embeddings.find_similar(query_embedding, items)
{:ok, assistant} = ExLLM.Assistants.create_assistant(:openai, name: "Helper")
```

Both styles work - choose based on your preference!

## New Features to Explore

### 1. Embeddings Module

Enhanced vector operations with dedicated module:

```elixir
# Generate embeddings
{:ok, response} = ExLLM.Embeddings.generate(:openai, "Hello world")

# Find similar items with multiple metrics
results = ExLLM.Embeddings.find_similar(query_embedding, items,
  top_k: 5,
  metric: :cosine,
  threshold: 0.8
)

# Create searchable index
{:ok, index} = ExLLM.Embeddings.create_index(:openai, documents)
{:ok, results} = ExLLM.Embeddings.search_index(index, "query")
```

### 2. Knowledge Base Management

New Gemini-powered semantic search capabilities:

```elixir
# Create a knowledge base
{:ok, kb} = ExLLM.KnowledgeBase.create_knowledge_base(:gemini, "my_kb",
  display_name: "Product Documentation"
)

# Add documents
{:ok, doc} = ExLLM.KnowledgeBase.add_document(:gemini, "my_kb", %{
  display_name: "User Guide",
  text: "Content here..."
})

# Semantic search
{:ok, results} = ExLLM.KnowledgeBase.semantic_search(:gemini, "my_kb",
  "How do I reset my password?"
)
```

### 3. Fluent Builder Interface

Chain configuration calls for readable code:

```elixir
{:ok, response} = 
  ExLLM.Builder.build(:openai, messages)
  |> ExLLM.Builder.with_model("gpt-4")
  |> ExLLM.Builder.with_temperature(0.7)
  |> ExLLM.Builder.with_max_tokens(1000)
  |> ExLLM.Builder.execute()
```

### 4. Enhanced Session Management

Improved conversation tracking:

```elixir
# Create and manage sessions
session = ExLLM.Session.new_session(:openai, model: "gpt-4")

# Chat with automatic context management
{:ok, response, updated_session} = 
  ExLLM.Session.chat_session(session, "Tell me a joke")

# Persist sessions
ExLLM.Session.save_session(updated_session, "conversation.json")
restored = ExLLM.Session.load_session("conversation.json")
```

## Configuration Changes

### Environment Variables

No changes required. All existing environment variables continue to work:

- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`
- etc.

### Application Configuration

No changes required. Existing configuration continues to work:

```elixir
# This still works
config :ex_llm,
  default_provider: :openai,
  openai: [
    api_key: System.get_env("OPENAI_API_KEY"),
    model: "gpt-4"
  ]
```

## Performance Improvements

- **42% reduction** in main module size for faster compilation
- **Lazy loading** of provider-specific code
- **Improved error handling** with standardized patterns
- **Smart test caching** for 25x faster test runs

## Deprecations

No functions are deprecated in v1.0.0. All existing APIs continue to work.

## Testing Your Upgrade

After upgrading, run your test suite to ensure everything works:

```bash
# Run all tests
mix test

# Run specific provider tests
mix test --only provider:openai
mix test --only provider:anthropic

# Run with live API calls (if needed)
mix test --include live_api
```

## Getting Help

If you encounter any issues:

1. Check the [CHANGELOG](CHANGELOG.md) for detailed changes
2. Review the [README](README.md) for updated examples
3. Open an issue on GitHub with:
   - Your ExLLM version (`mix deps | grep ex_llm`)
   - Error messages or unexpected behavior
   - Minimal code example reproducing the issue

## Future Considerations

While v1.0.0 maintains full backward compatibility, consider gradually adopting the new modular structure for:

- Better code organization
- Clearer intent in your code
- Easier testing of specific functionality
- Improved compile-time optimizations

## Summary

ExLLM v1.0.0 is a seamless upgrade that brings architectural improvements without breaking existing code. The new modular structure and enhanced features provide a solid foundation for building LLM-powered applications while maintaining the simplicity that makes ExLLM easy to use.

Happy coding! 🚀