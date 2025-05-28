# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- OpenRouter adapter with access to 300+ models from multiple providers
  - Support for Claude, GPT-4, Llama, PaLM, and many other model families
  - Unified API interface for different model architectures
  - Automatic model discovery and cost-effective access to premium models
- External YAML configuration system for model metadata
  - Model pricing, context windows, and capabilities stored in `config/models/*.yml`
  - Runtime configuration loading with ETS caching for performance
  - Separation of model data from code for easier maintenance
  - Support for easy updates without code changes

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