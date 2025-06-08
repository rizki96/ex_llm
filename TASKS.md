# ExLLM Tasks

## Recent Major Achievements ✨

### Code Quality Milestone (December 2024)
- 🎯 **Credo Strict Mode Enabled**: 91 source files analyzed with **0 issues**
- 🧹 **Clean Codebase**: Fixed all nesting issues (14 functions), complexity issues (6 functions), and TODO comments (5 items)
- 📈 **Enhanced Type System**: Added metadata support to LLMResponse and StreamChunk for timing and context data
- 🔧 **Improved Functionality**: Better token usage tracking, cost filtering, and context statistics

This represents a significant maturity milestone for the ExLLM codebase, ensuring high code quality standards and maintainability for future development.

## Completed

### Core Infrastructure
- [x] Unified adapter interface for multiple providers
- [x] Streaming support with SSE parsing
- [x] Model listing and management
- [x] Standardized response format (via ExLLM.Types)
- [x] Configuration injection pattern
- [x] Comprehensive error handling (via ExLLM.Error)
- [x] Application supervisor for lifecycle management

### Provider Adapters
- [x] Anthropic adapter (Claude 3, Claude 4 models)
- [x] Local adapter via Bumblebee/Nx
- [x] OpenAI adapter (GPT-4, GPT-3.5)
- [x] Ollama adapter (local model support)
- [x] AWS Bedrock adapter (complete - supports Anthropic, Amazon Titan, Meta Llama, Cohere, AI21, Mistral with full credential chain, streaming, provider-specific formatting)
- [x] Google Gemini adapter (Pro, Ultra variants)
- [x] OpenRouter adapter (300+ models from multiple providers)

### Features
- [x] Integrated cost tracking and calculation
- [x] Token estimation functionality
- [x] Context window management
  - [x] Automatic message truncation
  - [x] Multiple truncation strategies (sliding_window, smart)
  - [x] Model-specific context window sizes
  - [x] Context validation and statistics
- [x] Session management (via ExLLM.Session)
  - [x] Message history
  - [x] Token usage tracking
  - [x] JSON persistence
  - [x] Metadata handling
- [x] Instructor support for structured outputs
  - [x] Ecto schema integration
  - [x] Simple type specs
  - [x] Validation and retry logic
  - [x] JSON extraction from markdown

### Local Model Support
- [x] Model loading/unloading (via ExLLM.Local.ModelLoader)
- [x] EXLA/EMLX configuration (via ExLLM.Local.EXLAConfig)
- [x] Token counting with model tokenizers (via ExLLM.Local.TokenCounter)
- [x] Hardware acceleration detection (Metal, CUDA, ROCm)
- [x] Optimized inference settings
- [x] Mixed precision support

### Configuration System
- [x] ConfigProvider behaviour for dependency injection
- [x] Default provider using Application config
- [x] Static configuration provider
- [x] Environment-based configuration
- [x] External YAML configuration system for model metadata
  - [x] Model pricing, context windows, and capabilities in config/models/*.yml
  - [x] Runtime configuration loading with ETS caching
  - [x] ExLLM.ModelConfig module for centralized access
  - [x] Separation of model data from code for easier maintenance
  - [x] Model sync script from LiteLLM
    - [x] Python script to fetch model data from LiteLLM
    - [x] Automatic conversion from JSON to YAML format
    - [x] Synced 1048 models with pricing and capabilities

## In Progress

(Currently no tasks in progress)

## Recently Completed

### Provider Adapter Implementations ✅
- [x] **Mistral AI Adapter**
  - [x] OpenAI-compatible API implementation
  - [x] Chat, streaming, and embeddings support
  - [x] Function calling with tools format
  - [x] Model listing from API and config fallback
  - [x] Parameter validation with Mistral-specific restrictions
  - [x] Safe prompt parameter support
  - [x] Comprehensive test suite (14 unit tests, integration tests)

- [x] **Perplexity Adapter**
  - [x] Search-augmented language model support
  - [x] OpenAI-compatible base with Perplexity extensions
  - [x] Search modes: news, academic, general
  - [x] Reasoning effort levels: low, medium, high
  - [x] URL return and recency filters
  - [x] Search domain inclusion/exclusion
  - [x] Comprehensive test suite (33 tests)

- [x] **Bumblebee Adapter (Renamed from Local)**
  - [x] Complete refactoring from Local to Bumblebee naming
  - [x] Split tests into unit and integration for consistency
  - [x] Updated all references throughout codebase
  - [x] Maintained backward compatibility with :local alias
  - [x] Added model configuration in config/models/bumblebee.yml
  - [x] Fixed ModelLoader references

### Ollama Adapter Full API Implementation ✅
- [x] Fixed critical bugs
  - [x] Embeddings endpoint corrected to `/api/embed`
  - [x] Embeddings request format using `input` parameter
  - [x] Batch embeddings support
- [x] Added all missing endpoints
  - [x] `/api/generate` for non-chat completions with streaming
  - [x] `/api/show` for model information
  - [x] `/api/copy`, `/api/delete` for model management
  - [x] `/api/pull`, `/api/push` for model distribution
  - [x] `/api/ps` for running models, `/api/version` for version info
- [x] Added comprehensive parameter support
  - [x] `options` object with all model-specific settings
  - [x] GPU settings, memory settings, sampling parameters
  - [x] `context` parameter for stateful conversations
  - [x] `keep_alive` for model memory management
- [x] Multimodal support with proper image handling
- [x] Enhanced response format with timing metadata
- [x] Structured output support with format parameter

### Enhanced Streaming Error Recovery ✅
- [x] Core streaming recovery infrastructure (via ExLLM.StreamRecovery)
  - [x] Save partial responses during streaming
    - [x] Store response chunks with timestamps
    - [x] Track token count of partial response
    - [x] Save request context (messages, model, parameters)
  - [x] Detect interruptions
    - [x] Network errors vs timeouts vs user cancellation
    - [x] Distinguish recoverable vs non-recoverable errors
    - [x] Handle streaming errors gracefully
  - [x] Resume mechanisms
    - [x] `resume_stream/2` function to continue from saved state
    - [x] Adjust token count for already-received content
    - [x] Support different resumption strategies:
      - [x] `:exact` - Continue from exact cutoff
      - [x] `:paragraph` - Regenerate last paragraph for coherence
      - [x] `:summarize` - Summarize received content and continue
  - [x] Storage backend
    - [x] In-memory storage for current session
    - [x] Automatic cleanup of old partial responses
    - [x] Handle multiple interrupted responses per session
  - [x] Integration with existing streaming
    - [x] Modified `stream_chat/3` to support recovery
    - [x] Added recovery options to streaming config
    - [x] Recovery ID tracking for resumable streams

### Request Retry Logic with Exponential Backoff ✅
- [x] Core retry infrastructure (via ExLLM.Retry)
  - [x] Exponential backoff with configurable parameters
  - [x] Jitter support to prevent thundering herd
  - [x] Provider-specific retry policies
  - [x] Configurable retry conditions
  - [x] Circuit breaker pattern (structure defined)
- [x] Provider-specific implementations
  - [x] OpenAI retry with Retry-After header support
  - [x] Anthropic retry for 529 (overloaded) errors
  - [x] Bedrock retry for AWS throttling exceptions
- [x] Integration with main API
  - [x] Automatic retry for chat/3 (opt-out available)
  - [x] Configurable retry options per request
  - [x] Logging of retry attempts and outcomes

### Function Calling Support ✅
- [x] Unified function calling interface (via ExLLM.FunctionCalling)
  - [x] Provider-agnostic function definitions
  - [x] Automatic format conversion for each provider
  - [x] Function call parsing from responses
  - [x] Parameter validation against schemas
  - [x] Safe function execution with error handling
- [x] Provider implementations
  - [x] OpenAI function calling format
  - [x] Anthropic tools API format
  - [x] Bedrock tools format
  - [x] Gemini function calling format
- [x] Integration with main API
  - [x] Functions option in chat/3
  - [x] Automatic provider format conversion
  - [x] Public API for parsing and execution
- [x] Example implementation (examples/function_calling_example.exs)

### Mock Adapter for Testing ✅
- [x] Full mock adapter implementation (ExLLM.Adapters.Mock)
  - [x] Static response configuration
  - [x] Dynamic response handlers
  - [x] Error simulation
  - [x] Request capture and analysis
  - [x] Streaming support
  - [x] Function calling support
- [x] Testing utilities
  - [x] set_response/1 for static responses
  - [x] set_response_handler/1 for dynamic responses
  - [x] set_error/1 for error simulation
  - [x] get_requests/0 for request analysis
  - [x] reset/0 for test cleanup
- [x] Integration with retry and recovery
  - [x] Works with retry logic
  - [x] Compatible with stream recovery
- [x] Documentation and examples
  - [x] Comprehensive test file (ex_llm_mock_test.exs)
  - [x] Testing guide (examples/testing_with_mock.exs)

### Model Capability Discovery ✅
- [x] Comprehensive capability tracking (via ExLLM.ModelCapabilities)
  - [x] Feature support detection for all models
  - [x] Context window and output token limits
  - [x] Provider-specific capability details
  - [x] Release and deprecation date tracking
- [x] Model database
  - [x] OpenAI models (GPT-4, GPT-3.5 variants)
  - [x] Anthropic models (Claude 3/3.5 family)
  - [x] Google Gemini models
  - [x] Local models via Bumblebee
  - [x] Mock model for testing
- [x] Discovery features
  - [x] Query individual model capabilities
  - [x] Find models by required features
  - [x] Compare models side-by-side
  - [x] Get recommendations based on requirements
  - [x] Group models by capability
- [x] Public API integration
  - [x] get_model_info/2
  - [x] model_supports?/3
  - [x] find_models_with_features/1
  - [x] compare_models/1
  - [x] recommend_models/1
  - [x] models_by_capability/1
  - [x] list_model_features/0
- [x] Documentation and testing
  - [x] Comprehensive example (model_capabilities_example.exs)
  - [x] Full test coverage (model_capabilities_test.exs)

### Response Caching with TTL ✅
- [x] Core caching infrastructure (via ExLLM.Cache)
  - [x] TTL-based cache expiration
  - [x] Configurable storage backends via behaviour
  - [x] ETS storage backend implementation
  - [x] Cache key generation based on request parameters
  - [x] Selective caching (skip for streaming, functions, etc.)
  - [x] Cache statistics tracking
- [x] Integration with main API
  - [x] Automatic caching in chat/3 with cache option
  - [x] with_cache/3 wrapper for cache-aware execution
  - [x] Configurable TTL per request
  - [x] Global cache enable/disable
- [x] Cache management
  - [x] Clear cache functionality
  - [x] Delete specific entries
  - [x] Automatic cleanup of expired entries
  - [x] Cache hit/miss statistics
- [x] Documentation and testing
  - [x] Comprehensive example (caching_example.exs)
  - [x] Full test coverage (cache_test.exs)
  - [x] Cost savings calculations in examples

### Code Quality & Maintainability ✅
- [x] **Credo Strict Mode Implementation**
  - [x] Fixed all nesting issues (14 functions across multiple modules)
    - [x] Reduced nesting from 5+ levels to max 3 levels
    - [x] Strategic function extraction and pattern matching
    - [x] Improved readability and maintainability
  - [x] Resolved all cyclomatic complexity issues (6 high-complexity functions)
    - [x] ExLLM.Instructor.do_structured_chat (complexity 34 → reduced)
    - [x] ExLLM.Instructor.get_provider_config (complexity 19 → reduced)
    - [x] ExLLM.Adapters.Bedrock.parse_response (complexity 15 → reduced)
    - [x] ExLLM.Adapters.Mock.normalize_response (complexity 14 → reduced)
    - [x] ExLLM.Adapters.Shared.ModelUtils.generate_description (complexity 13 → reduced)
    - [x] ExLLM.Adapters.Mock.embeddings (complexity 13 → reduced)
  - [x] Fixed all TODO comments in codebase (5 items)
    - [x] Enhanced Types module with metadata fields for LLMResponse and StreamChunk
    - [x] Improved context_stats function with character counting and statistics
    - [x] Implemented token usage extraction in Local adapter with estimates
    - [x] Added cost filtering to model recommendations in ModelCapabilities
    - [x] Fixed syntax errors and compilation issues
  - [x] **Enabled Credo strict mode successfully**
    - [x] 91 source files analyzed with 0 issues found
    - [x] Comprehensive quality checks enabled
    - [x] Automated code quality enforcement

### Embeddings API ✅
- [x] Core embeddings infrastructure
  - [x] New types: EmbeddingResponse and EmbeddingModel
  - [x] Adapter behaviour extensions for embeddings
  - [x] Unified embeddings interface in main module
- [x] Provider implementations
  - [x] OpenAI embeddings adapter (text-embedding-3-small/large, ada-002)
  - [x] Mock adapter embeddings support
  - [x] Cost tracking for embedding models
- [x] Utility functions
  - [x] cosine_similarity/2 for comparing embeddings
  - [x] find_similar/3 for semantic search
  - [x] Batch embedding support
- [x] Integration features
  - [x] Automatic caching support for embeddings
  - [x] list_embedding_models/1 for discovery
  - [x] Dimension configuration support
- [x] Documentation and examples
  - [x] Comprehensive example (embeddings_example.exs)
  - [x] Semantic search demonstration
  - [x] Clustering and similarity examples
  - [x] Cost comparison across models

### Vision/Multimodal Support ✅
- [x] Core vision infrastructure (via ExLLM.Vision)
  - [x] Extended message types to support image content
  - [x] Image format validation and detection
  - [x] Base64 encoding/decoding utilities
  - [x] Provider-specific formatting
- [x] Image handling
  - [x] Load images from local files
  - [x] Support for image URLs
  - [x] Multiple image formats (JPEG, PNG, GIF, WebP)
  - [x] Image size validation
- [x] Provider implementations
  - [x] Anthropic vision support (base64 format)
  - [x] OpenAI vision support (URL and base64)
  - [x] Vision capability detection per model
- [x] API functions
  - [x] vision_message/3 for easy message creation
  - [x] load_image/2 for file loading
  - [x] supports_vision?/2 for capability checking
  - [x] extract_text_from_image/3 for OCR tasks
  - [x] analyze_images/4 for image analysis
- [x] Integration features
  - [x] Automatic provider formatting in chat/3
  - [x] Vision content detection
  - [x] Detail level configuration
- [x] Documentation and examples
  - [x] Comprehensive example (vision_example.exs)
  - [x] Multiple use cases demonstrated
  - [x] Error handling examples

## Todo

### Priority Overview

**Priority 0 - Immediate (Next 2 weeks)**
- Code refactoring for shared behaviors (reduce duplication by ~40%)
- Debug logging levels
- Complete any remaining core implementations

**Priority 1 - Short Term (Next month)**
- High-demand provider adapters (Mistral AI, Together AI, Cohere, Perplexity)

**Priority 2 - Medium Term (Next quarter)**
- Advanced router with cost-based routing and fallbacks
- Batch processing API
- Extensible callback system

**Priority 3+ - Long Term**
- Additional providers based on demand
- Advanced features and optimizations

### Example App Development (Priority 0)
- [x] Create comprehensive example_app that demonstrates all library features
- [x] Migrate existing examples into the unified app:
  - [x] Advanced features (retries, context management, etc.)
  - [x] Caching functionality
  - [x] Embeddings
  - [x] Function calling
  - [x] Local model usage
  - [x] Model capabilities exploration
  - [x] Structured outputs with Instructor
  - [x] Testing with mock adapter
  - [x] Vision/multimodal features
- [x] Add configuration system for provider selection
- [x] Use Ollama with Qwen3 8B (IQ4_XS) as default (fast local model)
- [x] Create interactive CLI menu for feature selection
- [x] Add comprehensive error handling and user feedback
- [x] Document setup and usage instructions
- [x] Remove deprecated individual example files

### Missing Core Implementations (Priority 0)
- [x] Session persistence (save_to_file/load_from_file in ExLLM.Session)
- [x] Function calling argument parsing (parse_arguments in ExLLM.FunctionCalling)
- [x] Model info retrieval (get_model_info in ExLLM.ModelCapabilities)
- [x] Provider capability tracking system
  - [x] Create ExLLM.ProviderCapabilities module
  - [x] Track provider-level features:
    - [x] Available endpoints (chat, embeddings, images, audio, etc.)
    - [x] Authentication methods (api_key, oauth, aws_signature, etc.)
    - [x] Streaming support at provider level
    - [x] Cost tracking availability
    - [x] Dynamic model listing support
    - [x] Batch operations support
    - [x] File upload capabilities
    - [x] Rate limiting information
    - [x] Provider metadata (description, docs, status URLs)
  - [x] Provider capability discovery API
  - [x] Integration with ModelCapabilities
  - [ ] Capability versioning for API versions (future enhancement)


### Core Features - Low Priority Items
- [x] Context statistics implementation
  - [x] Implement `context_stats/1` function in ExLLM module
  - [x] Calculate token distribution across messages
  - [x] Provide truncation impact analysis
  - [x] Return statistics about context usage
- [x] Token usage extraction for local models
  - [x] Extract token usage from Bumblebee/Local adapter responses
  - [x] Add token counting support to Local adapter
  - [x] Integrate with existing usage tracking
- [x] Cost filtering for model recommendations
  - [x] Implement cost-based filtering in ModelCapabilities.recommend_models/1
  - [x] Add max_cost option to recommendation queries
  - [x] Filter models based on pricing data when available

### Ollama Adapter - Remaining Low Priority Items
- [ ] `/api/blobs/:digest` endpoints for blob management
  - [ ] GET /api/blobs/:digest - Check if a blob exists
  - [ ] HEAD /api/blobs/:digest - Check blob existence (headers only)
  - [ ] POST /api/blobs/:digest - Create a blob
  - [ ] Used internally by Ollama for model layer management
- [x] Parse and expose created_at timestamps in responses
  - [x] Add metadata field to LLMResponse and StreamChunk types
  - [x] Include timing information (total_duration, load_duration, etc.)
  - [x] Preserve model context for stateful conversations

### Code Refactoring - Shared Behaviors & Modules (Priority 0)
- [x] Extract streaming into StreamingCoordinator module
  - [x] Standardize Task/Stream.resource pattern
  - [x] Common SSE parsing and buffering
  - [x] Provider-agnostic chunk handling
  - [x] Error recovery integration
- [x] Create RequestBuilder shared module
  - [x] Common request body construction
  - [x] Optional parameter handling
  - [x] Provider-specific extensions
- [x] Implement ModelFetcher behavior
  - [x] Standardize model API fetching
  - [x] Common parse/filter/transform pipeline
  - [x] Integration with ModelLoader
- [x] Extract VisionFormatter module
  - [x] Provider-specific image formatting
  - [x] Content type detection
  - [x] Base64 encoding utilities
- [ ] Enhance existing shared modules
  - [ ] Extend ResponseBuilder for more formats
  - [ ] Add provider-specific headers to HTTPClient
  - [ ] Unify error response parsing

### Advanced Router & Infrastructure (Priority 2)
- [x] OpenAI-Compatible base adapter for shared implementation
- [x] Provider detection pattern (provider/model-name syntax)
- [ ] Advanced router with strategies
  - [ ] Cost-based routing
  - [ ] Automatic fallback chains
  - [ ] Model group aliases
  - [ ] Least-latency routing
  - [ ] Usage-based routing
- [ ] Batch processing API
- [ ] Health checks and circuit breakers

### New Provider Adapters (Priority 1)
#### High Priority Providers
- [x] Groq adapter (fast inference)
- [x] XAI adapter (Grok models)
- [x] Mistral AI adapter (European models)
- [ ] Together AI adapter (cost-effective)
- [ ] Cohere adapter (enterprise, rerank API)
- [x] Perplexity adapter (search-augmented)

#### Medium Priority Providers
- [ ] Replicate adapter (marketplace)
- [ ] Databricks adapter
- [ ] Vertex AI adapter (Google Cloud)
- [ ] Azure AI adapter (beyond OpenAI)
- [ ] Fireworks AI adapter
- [ ] DeepInfra adapter

#### Lower Priority Providers
- [ ] Watsonx adapter (IBM)
- [ ] Sagemaker adapter (AWS)
- [ ] Anyscale adapter
- [ ] vLLM adapter
- [ ] Hugging Face Inference API adapter
- [ ] Baseten adapter
- [ ] DeepSeek adapter

### Provider Feature Enhancements (Priority 3)
- [ ] Anthropic cache control headers
- [ ] Vertex AI context caching
- [ ] Bedrock Converse API support
- [ ] Provider-specific error mapping
- [ ] Provider capability detection

### Observability & Monitoring (Priority 4)
- [ ] Extensible callback system
- [ ] Telemetry integration for metrics
- [ ] Custom metrics collection
- [ ] Request/response logging with redaction


### OpenAI API Enhancements (Priority 1)

#### Core Chat Completions Missing Features
- [ ] **Modern Request Parameters**
  - [ ] `max_completion_tokens` (replaces deprecated `max_tokens`)
  - [ ] `n` parameter for multiple completions (1-128)
  - [ ] `top_p` nucleus sampling parameter
  - [ ] `frequency_penalty` and `presence_penalty` (-2 to 2)
  - [ ] `seed` parameter for deterministic sampling
  - [ ] `stop` sequences (string or array)
  - [ ] `service_tier` for rate limiting control

- [ ] **Response Format & Structured Outputs**
  - [ ] JSON mode: `response_format: {"type": "json_object"}`
  - [ ] JSON Schema structured outputs with validation
  - [ ] Refusal handling in responses
  - [ ] `logprobs` token probabilities in responses

- [ ] **Modern Tool/Function Calling**
  - [ ] Migrate from deprecated `functions` to modern `tools` API
  - [ ] `tool_choice` parameter for controlling tool usage
  - [ ] Parallel tool calls support
  - [ ] Tool calling in streaming responses

- [ ] **Advanced Message Content**
  - [ ] Multiple content parts per message (text + images + audio)
  - [ ] File content references
  - [ ] Audio content in messages

- [ ] **New Model Features**
  - [ ] Audio output with voice selection
  - [ ] Web search integration with `web_search_options`
  - [ ] Reasoning effort control for o1/o3 models
  - [ ] Developer role for o1+ models (replaces system for these models)
  - [ ] Predicted outputs for faster regeneration

- [ ] **Enhanced Usage Tracking**
  - [ ] Cached tokens, reasoning tokens, audio tokens in usage
  - [ ] More detailed cost breakdown

#### Additional OpenAI APIs (Priority 3)
- [ ] **Assistants API** (Beta)
  - [ ] Create/list/modify assistants
  - [ ] Thread management
  - [ ] Run management with tool integration
- [ ] **Files API**
  - [ ] File upload for assistants and fine-tuning
  - [ ] File management and retrieval
- [ ] **Image Generation** (DALL-E)
  - [ ] Text-to-image generation
  - [ ] Image variations and edits
- [ ] **Audio API**
  - [ ] Speech-to-text transcription
  - [ ] Text-to-speech generation
  - [ ] Audio translation
- [ ] **Moderation API**
  - [ ] Content safety classification
  - [ ] Multi-category moderation scores
- [ ] **Batch API**
  - [ ] Async batch processing
  - [ ] Cost-effective bulk operations
- [ ] **Fine-tuning API**
  - [ ] Custom model training
  - [ ] Job management and monitoring

### Additional APIs (Priority 6)
- [ ] Files API for uploads
- [ ] Fine-tuning management API
- [ ] Assistants API
- [ ] Rerank API
- [ ] Audio transcription API
- [ ] Text-to-speech API
- [ ] Image generation API
- [ ] Moderation API

### Security & Compliance (Priority 7)
- [ ] Guardrails system
  - [ ] PII masking
  - [ ] Prompt injection detection
  - [ ] Content moderation
  - [ ] Secret detection
  - [ ] Custom guardrail plugins
- [ ] Request sanitization
- [ ] Response validation

### Developer Experience (Priority 0)
- [x] Debug logging levels
- [ ] Enhanced mock system with patterns
- [ ] Provider comparison tools
- [ ] Migration guides from other libraries

### Features (Existing)
- [ ] Fine-tuning management

### Advanced Context Management
- [ ] Semantic chunking for better truncation
- [ ] Context compression techniques
- [ ] Dynamic context window adjustment
- [ ] Token budget allocation strategies

### Cost & Usage
- [ ] Usage analytics and reporting
- [ ] Cost optimization recommendations
- [ ] Budget alerts and limits
- [ ] Provider cost comparison
- [ ] Token usage predictions

### Testing & Quality
- [ ] Mock adapters for testing
- [ ] Integration test suite for each provider
- [ ] Performance benchmarks
- [ ] Load testing for concurrent requests
- [ ] Property-based tests for context management

### Documentation
- [ ] Comprehensive adapter implementation guide
- [ ] Provider-specific configuration examples
- [ ] Migration guide from other LLM libraries
- [ ] Best practices for context management
- [ ] Cost optimization strategies

## Notes

- The library aims to be the go-to solution for LLM integration in Elixir
- Focus remains on being a unified, reliable LLM client library
- All features should work consistently across providers where possible
- Provider-specific features should be clearly documented
- Performance and cost efficiency are key priorities
- Features that belong at the application layer have been moved to docs/DROPPED.md