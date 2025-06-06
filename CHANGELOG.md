# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2025-06-05

### Added
- **Major Code Refactoring** - Reduced code duplication by ~40% through shared modules:
  - `StreamingCoordinator` - Unified streaming implementation for all adapters
    - Standardized SSE parsing and buffering
    - Provider-agnostic chunk handling
    - Integrated error recovery support
    - Simplified adapter streaming implementations
  - `RequestBuilder` - Common request construction patterns
    - Unified parameter handling across providers
    - Provider-specific transformations via callbacks
    - Support for chat, embeddings, and completion endpoints
  - `ModelFetcher` - Standardized model discovery behavior
    - Common API fetching patterns
    - Unified filter/parse/transform pipeline
    - Integration with ModelLoader for caching
  - `VisionFormatter` - Centralized vision/multimodal content handling
    - Provider-specific image formatting (Anthropic, OpenAI, Gemini)
    - Media type detection from file extensions and magic bytes
    - Base64 encoding/decoding utilities
    - Image size validation
- `DebugLogger` module for configurable debug logging
  - Configurable log levels (debug, info, warn, error, none)
  - Component-specific logging control
  - Request/response logging with redaction
  - Structured logging with metadata
  - Performance tracking and timing

### Changed
- Enhanced `HTTPClient` with unified streaming support via `post_stream/3`
- Improved error handling consistency across all shared modules
- Better separation of concerns in adapter implementations

### Technical Improvements
- Reduced code duplication significantly across adapters
- More maintainable and testable codebase structure
- Easier to add new providers using shared behaviors
- Consistent patterns for common operations

## [0.3.0] - 2025-06-05

### Added
- X.AI adapter implementation with complete feature support
  - Full OpenAI-compatible API integration
  - Support for all Grok models (Beta, 2, 3, Vision variants)
  - Streaming, function calling, vision, and structured outputs
  - Web search and reasoning capabilities
  - Complete Instructor integration for structured outputs
- Synced model metadata from LiteLLM (1053 models across 56 providers)
  - New OpenAI models: GPT-4.1 series (gpt-4.1, gpt-4.1-mini, gpt-4.1-nano)
  - New OpenAI O1 reasoning models (o1-pro, o1, o1-mini, o1-preview)
  - New XAI Grok-3 models (grok-3, grok-3-beta, grok-3-fast, grok-3-mini variants)
  - New model capabilities: structured_output, prompt_caching, reasoning, web_search
  - Updated pricing and context windows for all models
- Fetched latest models from provider APIs (606 models from 6 providers)
  - New Anthropic models: Claude 4 Opus/Sonnet/Haiku with 32K output tokens
  - New Groq models: DeepSeek R1 distilled models, QwQ-32B, Mistral Saba
  - New Gemini models: Gemini 2.5 Pro/Flash, Gemini 2.0 Flash with multimodal support
  - New OpenAI models: O3/O4 series, GPT-4.5 preview, search-enabled models
  - Updated context windows and capabilities from live APIs
- Groq support for structured outputs via Instructor integration

### Changed
- Updated default models:
  - OpenAI: Set to gpt-4.1-nano
  - Anthropic: Set to claude-3-5-sonnet-latest
- Enhanced Instructor module to support Groq provider
- Updated example app to include Groq in structured output demos
- Updated README.md with current model information:
  - Anthropic: Added Claude 4 series and Claude 3.7
  - OpenAI: Added GPT-4.1 series and O1 reasoning models
  - Gemini: Added Gemini 2.5 and 2.0 series
  - Groq: Added Llama 4 Scout, DeepSeek R1 Distill, and QwQ-32B
- Task reorganization:
  - Created DROPPED.md for features that don't align with core library mission
  - Reorganized TASKS.md with clearer priorities and focused roadmap
  - Added refactoring tasks to reduce code duplication by ~40%

### Fixed
- Instructor integration now correctly separates params and config for chat_completion
- Advanced features demo uses correct Mock adapter method (set_stream_chunks)
- Module reference errors in Context management demo

## [0.2.1] - 2025-06-05

### Added
- Provider Capability Discovery System
  - New `ExLLM.ProviderCapabilities` module for tracking API-level provider capabilities
  - Provider feature discovery independent of specific models
  - Authentication method tracking (API key, OAuth, AWS signature, etc.)
  - Provider endpoint discovery (chat, embeddings, images, audio, etc.)
  - Provider recommendations based on required/preferred features
  - Provider comparison tools for feature analysis
  - Integrated provider capability functions into main ExLLM module
  - Added provider capability explorer to example app demo
- Environment variable wrapper script (`scripts/run_with_env.sh`) for Claude CLI usage
- Groq models API support (https://api.groq.com/openai/v1/models)
- Dynamic model loading from provider APIs
  - All adapters now fetch models dynamically from provider APIs when available
  - Automatic fallback to YAML configuration when API is unavailable
  - Created `ExLLM.ModelLoader` module for centralized model loading with caching
  - Anthropic adapter now uses `/v1/models` API endpoint
  - OpenAI adapter fetches from `/v1/models` and filters chat models
  - Gemini adapter uses Google's models API
  - Ollama adapter fetches from local server's `/api/tags`
  - OpenRouter adapter uses public `/api/v1/models` API
- OpenRouter adapter with access to 300+ models from multiple providers
  - Support for Claude, GPT-4, Llama, PaLM, and many other model families
  - Unified API interface for different model architectures
  - Automatic model discovery and cost-effective access to premium models
- External YAML configuration system for model metadata
  - Model pricing, context windows, and capabilities stored in `config/models/*.yml`
  - Runtime configuration loading with ETS caching for performance
  - Separation of model data from code for easier maintenance
  - Support for easy updates without code changes
- OpenAI-Compatible base adapter for shared implementation
  - Reduces code duplication across providers with OpenAI-compatible APIs
  - Groq adapter as first implementation using the base adapter
- Model configuration sync script from LiteLLM
  - Python script to sync model data from LiteLLM's database
  - Added 1048 models with pricing, context windows, and capabilities
  - Automatic conversion from LiteLLM's JSON to ExLLM's YAML format
- Extracted ALL provider configurations from LiteLLM
  - Created YAML files for 56 unique providers (49 new providers)
  - Includes Azure, Mistral, Perplexity, Together AI, Databricks, and more
  - Ready-to-use configurations for future adapter implementations

### Changed
- **BREAKING:** Model configuration moved from hardcoded maps to external YAML files
  - All providers now use `ExLLM.ModelConfig` for pricing and context window data
  - Default models, pricing, and context windows loaded from YAML configuration
  - Added `yaml_elixir` dependency for YAML parsing
- Updated Bedrock adapter with comprehensive model support:
  - Added all latest Anthropic models (Claude 4, 3.7, 3.5 series)
  - Added Amazon Nova models (Micro, Lite, Pro, Premier)
  - Added AI21 Labs Jamba series (1.5-large, 1.5-mini, instruct)
  - Added Cohere Command R series (R, R+)
  - Added DeepSeek R1 model
  - Added Meta Llama 4 and 3.x series models
  - Added Mistral Pixtral Large 2025-02
  - Added Writer Palmyra X4 and X5 models
  - Changed default model from "claude-3-sonnet" to "nova-lite" for cost efficiency
- Updated pricing data for all Bedrock providers with per-1M token rates
- Updated context window sizes for all new Bedrock models
- Enhanced streaming support for all new providers (Writer, DeepSeek)
- All adapters now use ModelConfig for consistent default model retrieval

### Changed
- **BREAKING:** Refactored `ExLLM.Adapters.OpenAICompatible` base adapter
  - Extracted common helper functions (`format_model_name/1`, `default_model_transformer/2`) as public module functions
  - Simplified adapter implementations by removing duplicate code
  - Added ModelLoader integration to base adapter for consistent dynamic model loading
  - Added `filter_model/1` and `parse_model/1` callbacks for customizing model parsing

### Fixed
- Anthropic models API fetch now correctly parses response structure (uses `data` field instead of `models`)
- Python model fetch script updated to handle Anthropic's API response format
- OpenRouter pricing parser now handles string values correctly
- Groq adapter compilation warnings for undefined callbacks
- DateTime serialization in MessageFormatter for session persistence
- OpenAI adapter streaming termination handling
- JSON double-encoding issue in HTTPClient
- Token field name standardization across adapters (input_tokens/output_tokens)
- Instructor integration API parameter passing
- Context management module reference errors in example app
- Function calling demo error handling with string keys
- Streaming chat demo now shows token usage and cost estimates

### Changed
- Made Instructor a required dependency instead of optional
- OpenAI default model changed to gpt-4.1-nano
- Instructor now uses dynamic default models from YAML configs
- Example app no longer hardcodes model names

### Improved
- Code organization with shared modules to eliminate duplication:
  - Created `ExLLM.Adapters.Shared.Validation` for API key validation
  - All adapters now use `ModelUtils.format_model_name` for consistent formatting
  - All adapters now use `ConfigHelper.ensure_default_model` for default models
  - Test files updated to use `TestHelpers` consistently
- Example app enhancements:
  - Session management shows full conversation history
  - Function calling demo clearly shows available tools
  - Advanced features demo now has real implementations
  - Cost formatting uses decimal notation instead of scientific

### Removed
- Removed hardcoded model names from adapters
- Removed `model_capabilities.ex.bak` backup file
- Removed `DUPLICATE_CODE_ANALYSIS.md` after completing all refactoring

## [0.2.0] - 2025-05-25

### Added
- OpenAI adapter with GPT-4 and GPT-3.5 support
- Ollama adapter for local model inference
- AWS Bedrock adapter with full multi-provider support (Anthropic, Amazon Titan, Meta Llama, Cohere, AI21, Mistral)
  - Complete AWS credential chain support (environment vars, profiles, instance metadata, ECS task roles)
  - Provider-specific request/response formatting
  - Native streaming support
  - Dynamic model listing via AWS Bedrock API
- Google Gemini adapter with Pro, Ultra, and Nano models
- Context management functionality to automatically handle LLM context windows
- `ExLLM.Context` module with the following features:
  - Automatic message truncation to fit within model context windows
  - Multiple truncation strategies (sliding_window, smart)
  - Context window validation
  - Token estimation and statistics
  - Model-specific context window sizes
- Session management functionality for conversation state tracking
- `ExLLM.Session` module with the following features:
  - Conversation state management
  - Message history tracking
  - Token usage tracking
  - Session persistence (save/load)
  - Export to markdown/JSON formats
- Local model support via Bumblebee integration
- `ExLLM.Adapters.Local` with the following features:
  - Support for Phi-2, Llama 2, Mistral, GPT-Neo, and Flan-T5
  - Hardware acceleration (Metal, CUDA, ROCm, CPU)
  - Model lifecycle management with ModelLoader GenServer
  - Zero-cost inference (no API fees)
  - Privacy-preserving local execution
- New public API functions in main ExLLM module:
  - Context management: `prepare_messages/2`, `validate_context/2`, `context_window_size/2`, `context_stats/1`
  - Session management: `new_session/2`, `chat_with_session/2`, `save_session/2`, `load_session/1`, etc.
- Automatic context management in `chat/3` and `stream_chat/3`
- Optional dependencies (Bumblebee, Nx, EXLA) for local model support
- Application supervisor for managing ModelLoader lifecycle
- Comprehensive test coverage for all new features

### Changed
- Updated `chat/3` and `stream_chat/3` to automatically apply context truncation
- Enhanced documentation with context management and session examples
- ExLLM is now a comprehensive all-in-one solution including cost tracking, context management, and session handling

## [0.1.0] - 2025-05-24

### Added
- Initial release with unified LLM interface
- Support for Anthropic Claude models
- Streaming support via Server-Sent Events
- Integrated cost tracking and calculation
- Token estimation functionality
- Configurable provider system
- Comprehensive error handling