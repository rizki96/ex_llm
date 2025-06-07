# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Response Caching System** - Cache real provider responses for offline testing and development
  - **Automatic Response Collection**: All provider responses automatically cached when enabled
  - **Mock Integration**: Configure Mock adapter to replay cached responses from any provider
  - **Cache Management**: Full CRUD operations for cached responses with provider organization
  - **Fuzzy Matching**: Robust request matching handles real-world usage variations
  - **Environment Configuration**: Simple enable/disable via `EX_LLM_CACHE_RESPONSES` environment variable
  - **Cost Reduction**: Reduce API costs during development by replaying cached responses
  - **Realistic Testing**: Use authentic provider responses in tests without API calls
  - **Streaming Support**: Cache and replay streaming responses with exact chunk reproduction
  - **Cross-Provider Testing**: Test application compatibility across different provider response formats

## [0.4.0] - 2025-06-06

### Added
- **Complete OpenAI API Implementation** - Full support for modern OpenAI API features
  - **Audio Features**: Support for audio input in messages and audio output configuration
  - **Web Search Integration**: Support for web search options in chat completions
  - **O-Series Model Features**: Reasoning effort parameter and developer role support
  - **Predicted Outputs**: Support for faster regeneration with prediction hints
  - **Additional APIs**: Six new OpenAI API endpoints
    - `moderate_content/2` - Content moderation using OpenAI's moderation API
    - `generate_image/2` - DALL-E image generation with configurable parameters
    - `transcribe_audio/2` - Whisper audio transcription (basic implementation)
    - `upload_file/3` - File upload for assistants and other endpoints (basic implementation)
    - `create_assistant/2` - Create assistants with custom instructions and tools
    - `create_batch/2` - Batch processing for multiple requests
  - **Enhanced Message Support**: Multiple content parts per message (text + audio/image)
  - **Modern Request Parameters**: Support for all modern OpenAI API parameters
    - `max_completion_tokens`, `top_p`, `frequency_penalty`, `presence_penalty`
    - `seed`, `stop`, `service_tier`, `logprobs`, `top_logprobs`
  - **JSON Response Formats**: JSON mode and JSON Schema structured outputs
  - **Modern Tools API**: Full support for tools API replacing deprecated functions
  - **Enhanced Streaming**: Tool calls and usage information in streaming responses
  - **Enhanced Usage Tracking**: Detailed token usage with cached/reasoning/audio tokens

### Changed
- **MessageFormatter**: Added support for "developer" role for O1+ models
- **OpenAI Adapter**: Comprehensive test coverage with 46 tests following TDD methodology
- **Response Types**: Enhanced LLMResponse struct with new fields (refusal, logprobs, tool_calls)

### Technical
- Implemented using Test-Driven Development (TDD) methodology
- Maintains full backward compatibility with existing API
- All features validated with comprehensive test suite
- Proper error handling and API key validation for all new endpoints

- **Ollama Configuration Management** - Generate and update local model configurations
  - New `generate_config/1` function to create YAML config for all installed models
  - New `update_model_config/2` function to update specific model configurations
  - Automatic capability detection using `/api/show` endpoint
  - Real context window sizes from model metadata
  - Preserves existing configuration when merging
  - Example: `ExLLM.Adapters.Ollama.generate_config(save: true)`

## [0.3.2] - 2025-06-06

### Added
- **Capability Normalization** - Automatic normalization of provider-specific capability names
  - New `ExLLM.Capabilities` module providing unified capability interface
  - Normalizes different provider terminologies (e.g., `tool_use` → `function_calling`)
  - Works transparently with all capability query functions
  - Comprehensive mappings for common capability variations
  - Example: `find_providers_with_features([:tool_use])` works across all providers
- Enhanced provider capability tracking with real-time API discovery
  - New `fetch_provider_capabilities.py` script for API-based capability detection
  - Updated `fetch_provider_models.py` with better context window detection
  - Fixed incorrect context windows (e.g., GPT-4o now correctly shows 128,000)
  - Automatic capability detection from model IDs
- New capability normalization demo in example app (option 6 in Provider Capabilities Explorer)
- **Comprehensive Documentation**
  - New Quick Start Guide (`docs/QUICKSTART.md`) - Get up and running in 5 minutes
  - New User Guide (`docs/USER_GUIDE.md`) - Complete documentation of all features
  - Reorganized documentation into `docs/` directory
  - Added prominent documentation links to README

### Changed
- Updated `provider_supports?/2`, `model_supports?/3`, `find_providers_with_features/1`, and `find_models_with_features/1` to use normalized capabilities

### Fixed
- Mock provider now properly supports Instructor integration for structured outputs
- Cost formatting now consistently uses dollars with appropriate decimal places (e.g., "$0.000324" instead of "$0.032¢")
- Anthropic provider now includes required `max_tokens` parameter when using Instructor
- Mock provider now generates semantically meaningful embeddings for realistic similarity search
- Fixed KeyError when using providers without pricing data (e.g., Ollama)
- Cost tracking now properly adds cost information to chat responses
- Ollama now properly supports function calling for compatible models
- Made request timeouts configurable via `:timeout` option (defaults: Ollama 2min, others use client defaults)
- Fixed MatchError in example app when displaying providers without capabilities info
- Provider and model capability queries now accept any provider's terminology
- Moved `LOGGER.md`, `PROVIDER_CAPABILITIES.md`, and `DROPPED.md` to `docs/` directory
- Enhanced provider capabilities with data from API discovery scripts

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
- Unified `ExLLM.Logger` module replacing multiple logging approaches
  - Single consistent API for all logging needs
  - Simple Logger-like interface: `Logger.info("message")`
  - Automatic context tracking with `with_context/2`
  - Structured logging for LLM-specific events (requests, retries, streaming)
  - Configurable log levels and component filtering
  - Security features: API key and content redaction
  - Performance tracking with automatic duration measurement

### Changed
- **BREAKING:** Replaced all `Logger` and `DebugLogger` usage with unified `ExLLM.Logger`
  - All modules now use `alias ExLLM.Logger` instead of `require Logger`
  - Consistent logging interface across the entire codebase
  - Simplified developer experience with one logging API
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
  - Created docs/DROPPED.md for features that don't align with core library mission
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