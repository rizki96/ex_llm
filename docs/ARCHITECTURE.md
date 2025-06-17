# ExLLM Architecture

This document describes ExLLM's layered architecture and namespace organization, designed for clarity, maintainability, and scalability.

## Overview

ExLLM follows a **Clean Layered Architecture** pattern that separates concerns into distinct layers with clear dependency rules:

```
┌─────────────────────────────────────────────────────┐
│                    Public API                       │
│                   (lib/ex_llm.ex)                   │
└─────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────┐
│                  Core Layer                         │
│                (lib/ex_llm/core/)                   │
│          • Business Logic                           │
│          • Domain Concepts                          │
│          • Pure Functions                           │
└─────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────┐
│              Infrastructure Layer                   │
│            (lib/ex_llm/infrastructure/)             │
│          • Technical Implementation                 │
│          • Configuration                            │
│          • Caching, Streaming, Telemetry           │
└─────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────┐
│               Providers Layer                       │
│              (lib/ex_llm/providers/)                │
│          • External Service Integrations           │
│          • API Adapters                            │
│          • Protocol Implementations                │
└─────────────────────────────────────────────────────┘
```

## Namespace Organization

### Core Layer (`lib/ex_llm/core/`)

The core layer contains pure business logic and domain concepts. These modules represent the core value propositions of ExLLM.

```elixir
# Business domain modules
ExLLM.Core.Chat             # Primary chat functionality
ExLLM.Session               # Conversation state management
ExLLM.Context               # Message context management
ExLLM.Core.Embeddings       # Text vectorization
ExLLM.Core.FunctionCalling  # Tool/function calling
ExLLM.Core.StructuredOutputs # Schema validation
ExLLM.Core.Vision           # Multimodal support
ExLLM.Core.Capabilities     # Model capability queries
ExLLM.Core.Models           # Model discovery and management

# Cost tracking (core business value)
ExLLM.Core.Cost             # Cost calculation
ExLLM.Core.Cost.Display     # Cost formatting
ExLLM.Core.Cost.Session     # Session-level cost tracking
```

**Design Principles:**
- No dependencies on infrastructure or providers
- Pure functions where possible
- Domain-driven design
- Business logic only

### Infrastructure Layer (`lib/ex_llm/infrastructure/`)

The infrastructure layer provides technical services that support the core business logic.

```elixir
# Configuration management
ExLLM.Infrastructure.Config.ModelConfig         # Model configuration
ExLLM.Infrastructure.Config.ModelCapabilities   # Model capability metadata
ExLLM.Infrastructure.Config.ProviderCapabilities # Provider capability metadata

# Technical services
ExLLM.Infrastructure.Cache               # Response caching
ExLLM.Infrastructure.Logger             # Logging infrastructure
ExLLM.Infrastructure.Retry              # Retry logic
ExLLM.Infrastructure.Error              # Error handling
ExLLM.Infrastructure.ConfigProvider     # Configuration providers

# Advanced infrastructure
ExLLM.Infrastructure.Streaming          # Streaming infrastructure
ExLLM.Infrastructure.CircuitBreaker     # Circuit breaker patterns
ExLLM.Infrastructure.Telemetry          # Observability and metrics
```

**Design Principles:**
- Provides technical services to core layer
- No business logic
- Reusable across different domains
- Infrastructure concerns only

### Providers Layer (`lib/ex_llm/providers/`)

The providers layer handles all external service integrations and API communication.

```elixir
# Provider implementations
ExLLM.Providers.Anthropic     # Claude API integration
ExLLM.Providers.OpenAI        # GPT API integration
ExLLM.Providers.Gemini        # Google Gemini API
ExLLM.Providers.Groq          # Groq API integration
ExLLM.Providers.OpenRouter    # OpenRouter API
# ... and 9 more providers

# Shared provider utilities
ExLLM.Providers.Shared.HTTPClient           # HTTP communication
ExLLM.Providers.Shared.MessageFormatter    # Message formatting
ExLLM.Providers.Shared.StreamingCoordinator # Unified streaming
ExLLM.Providers.Shared.ErrorHandler        # Provider error handling
```

**Design Principles:**
- External service communication only
- Implements common adapter interface
- Uses infrastructure services
- No direct business logic

### Testing Layer (`lib/ex_llm/testing/`)

Specialized testing utilities and infrastructure.

```elixir
ExLLM.Testing.Cache         # Test response caching
ExLLM.Testing.Helpers       # Test utilities
ExLLM.Testing.Interceptor   # Request interception
```

## Dependency Rules

The architecture enforces strict dependency rules to maintain clean separation:

### ✅ **Allowed Dependencies:**

```
Core → Infrastructure → Providers
  ↓         ↓              ↓
Testing ←───┴──────────────┘
```

- **Core** may depend on **Infrastructure**
- **Infrastructure** may depend on **Providers** (for shared utilities)
- **Providers** may depend on **Infrastructure** and **Core**
- **Testing** may depend on any layer

### ❌ **Forbidden Dependencies:**

- **Infrastructure** → **Core** (would create circular dependencies)
- **Core** → **Providers** (would couple business logic to external services)
- **Core** → **Testing** (business logic should not depend on test utilities)

## Module Import Patterns

The new architecture enables clear, intuitive imports:

```elixir
# Business logic imports
alias ExLLM.Core.{Chat, Session, Cost, Context}

# Infrastructure imports  
alias ExLLM.Infrastructure.{Config, Cache, Logger}
alias ExLLM.Infrastructure.Config.{ModelConfig, ProviderCapabilities}

# Provider imports
alias ExLLM.Providers.{Anthropic, OpenAI, Gemini}
alias ExLLM.Providers.Shared.{HTTPClient, MessageFormatter}

# Testing imports
alias ExLLM.Testing.{Helpers, Cache}
```

## Benefits

### 1. **Developer Experience**
- **Intuitive Organization**: Easy to find related functionality
- **Clear Mental Model**: Layers have distinct purposes
- **Reduced Cognitive Load**: Know where to look for specific concerns

### 2. **Maintainability**
- **Separation of Concerns**: Each layer has a single responsibility
- **Loose Coupling**: Changes in one layer don't cascade to others
- **Testability**: Each layer can be tested independently

### 3. **Scalability**
- **Easy Extension**: Add new features in the appropriate layer
- **Team Collaboration**: Teams can work on different layers independently
- **Refactoring**: Layer boundaries make refactoring safer

### 4. **Code Quality**
- **Dependency Direction**: Enforced dependency rules prevent architectural decay
- **Interface Clarity**: Layer boundaries define clear interfaces
- **Single Responsibility**: Each module has a focused purpose

## Migration from Previous Structure

The reorganization moved modules to their logical homes:

```elixir
# Before: Flat organization
ExLLM.Cost.* → ExLLM.Core.Cost.*           # Cost is core business logic
ExLLM.Config.* → ExLLM.Infrastructure.Config.* # Config is infrastructure

# Result: Clear layered architecture
Core/          # Business domain
Infrastructure/ # Technical services  
Providers/     # External integrations
Testing/       # Test utilities
```

## Future Architecture Considerations

As ExLLM grows, consider these architectural patterns:

### 1. **Domain-Driven Design**
- Group related core modules into subdomains
- Consider bounded contexts for large features

### 2. **Hexagonal Architecture**
- Core as the hexagon center
- Providers as external adapters
- Infrastructure as ports

### 3. **Microkernel Architecture**
- Core as the microkernel
- Providers as plugins
- Infrastructure as shared services

## Conclusion

ExLLM's layered architecture provides a solid foundation for growth while maintaining clarity and simplicity. The clear separation of concerns, enforced dependency rules, and intuitive namespace organization make the codebase easier to understand, maintain, and extend.

This architecture positions ExLLM to scale from a unified LLM client to a comprehensive AI development platform while maintaining architectural integrity.