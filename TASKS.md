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
- [x] Google Gemini adapter (basic implementation - Pro, Ultra variants)
  - [ ] Full API implementation in progress (see Gemini API Implementation section)
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
  - [x] **BREAKING:** Removed :local alias completely (use :bumblebee instead)
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
- Implement comprehensive Gemini API support (TDD approach)
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

### Gemini API Implementation (Priority 0) - TDD Approach

#### Phase 1: Core Foundation

##### [x] 1. Models API (GEMINI-API-01-MODELS.md) ✅
- [x] Create `test/ex_llm/gemini/models_test.exs`
  - [x] Test listing available models
  - [x] Test getting model details
  - [x] Test model capabilities and limits
  - [x] Test error handling for invalid models
- [x] Implement `lib/ex_llm/gemini/models.ex`
  - [x] `list_models/1` - List available models
  - [x] `get_model/2` - Get specific model details
  - [x] Model struct with all properties
  - [x] Error handling
- [x] Run tests and ensure they pass
- [x] Update model registry with Gemini models

##### [x] 2. Content Generation API (GEMINI-API-02-GENERATING-CONTENT.md) ✅ 
- [x] Create `test/ex_llm/gemini/content_test.exs`
  - [x] Test basic text generation
  - [x] Test streaming responses
  - [x] Test with system instructions
  - [x] Test with generation config (temperature, top_p, etc.)
  - [x] Test with safety settings
  - [x] Test multimodal inputs (text + images)
  - [x] Test structured output (JSON mode)
  - [x] Test function calling
  - [x] Test error scenarios
- [x] Implement `lib/ex_llm/gemini/content.ex`
  - [x] `generate_content/3` - Non-streaming generation
  - [x] `stream_generate_content/3` - Streaming generation
  - [x] Request/response structs
  - [x] Generation config handling
  - [x] Safety settings
  - [x] Tool/function definitions
- [x] Integration with main ExLLM adapter pattern
- [x] Run tests and ensure they pass (validation tests pass, API tests require valid key)

##### [x] 3. Token Counting API (GEMINI-API-04-TOKENS.md) ✅
- [x] Create `test/ex_llm/adapters/gemini/tokens_test.exs`
  - [x] Test counting tokens for text
  - [x] Test counting tokens for multimodal content
  - [x] Test with different models
  - [x] Test error handling
- [x] Implement `lib/ex_llm/gemini/tokens.ex`
  - [x] `count_tokens/3` - Count tokens for content
  - [x] Token count response struct
  - [x] Integration with content generation
- [x] Run tests and ensure they pass

#### Phase 2: Advanced Features

##### [x] 4. Files API (GEMINI-API-05-FILES.md) ✅
- [x] Create `test/ex_llm/adapters/gemini/files_test.exs`
  - [x] Test file upload
  - [x] Test file listing
  - [x] Test file deletion
  - [x] Test file metadata retrieval
  - [x] Test file state transitions
  - [x] Test error handling
- [x] Implement `lib/ex_llm/gemini/files.ex`
  - [x] `upload_file/3` - Upload media files (resumable upload)
  - [x] `list_files/1` - List uploaded files
  - [x] `get_file/2` - Get file metadata
  - [x] `delete_file/2` - Delete a file
  - [x] `wait_for_file/3` - Wait for file processing
  - [x] File struct and state management
- [x] Run tests and ensure they pass

##### [x] 5. Context Caching API (GEMINI-API-06-CACHING.md) ✅
- [x] Create `test/ex_llm/gemini/caching_test.exs`
  - [x] Test creating cached content
  - [x] Test listing cached content
  - [x] Test updating cached content
  - [x] Test deleting cached content
  - [x] Test using cached content in generation
  - [x] Test TTL and expiration
- [x] Implement `lib/ex_llm/gemini/caching.ex`
  - [x] `create_cached_content/2` - Create cache entry
  - [x] `list_cached_contents/1` - List cache entries
  - [x] `get_cached_content/2` - Get cache details
  - [x] `update_cached_content/3` - Update cache
  - [x] `delete_cached_content/2` - Delete cache
  - [x] Integration with content generation
- [x] Run tests and ensure they pass

##### [x] 6. Embeddings API (GEMINI-API-07-EMBEDDING.md) ✅
- [x] Create `test/ex_llm/gemini/embeddings_test.exs`
  - [x] Test text embeddings
  - [x] Test batch embeddings
  - [x] Test different embedding models
  - [x] Test content types (query vs document)
  - [x] Test error handling
- [x] Implement `lib/ex_llm/gemini/embeddings.ex`
  - [x] `embed_content/3` - Generate embeddings
  - [x] Batch embedding support
  - [x] Task type configuration
  - [x] Integration with main embeddings interface
- [x] Run tests and ensure they pass

#### Phase 3: Live API

##### [x] 7. Live API (GEMINI-API-03-LIVE-API.md) ✅
- [x] Add WebSocket client library (Gun)
- [x] Create `test/ex_llm/adapters/gemini/live_test.exs`
  - [x] Test WebSocket connection (URL building and headers)
  - [x] Test message building (setup, client content, realtime input, tool response)
  - [x] Test message parsing (server content, tool calls, transcription, go away)
  - [x] Test validation (setup config, realtime input, generation config)
  - [x] Test struct definitions (all message types)
- [x] Implement `lib/ex_llm/gemini/live.ex`
  - [x] WebSocket client implementation using Gun
  - [x] GenServer-based session management
  - [x] Audio/video/text streaming support
  - [x] Event handling and message parsing
  - [x] Tool execution interface
  - [x] Connection lifecycle management
  - [x] Comprehensive validation and error handling
- [x] Run tests and ensure they pass (23 tests, 100% pass rate)

#### Phase 4: Fine-tuning

##### [x] 8. Fine-tuning API (GEMINI-API-08-TUNING_TUNING.md) ✅
- [x] Create `test/ex_llm/gemini/tuning_test.exs`
  - [x] Test creating tuned models
  - [x] Test listing tuned models
  - [x] Test monitoring tuning jobs
  - [x] Test using tuned models
  - [x] Test hyperparameter configuration
- [x] Implement `lib/ex_llm/gemini/tuning.ex`
  - [x] `create_tuned_model/2` - Start tuning job
  - [x] `list_tuned_models/1` - List tuned models
  - [x] `get_tuned_model/2` - Get tuning details
  - [x] `delete_tuned_model/2` - Delete tuned model
  - [x] `generate_content/3` - Generate using tuned model
  - [x] `stream_generate_content/3` - Stream using tuned model
  - [x] All struct definitions (TunedModel, TuningTask, etc.)
- [x] Run tests and ensure they pass (unit tests pass, integration tests require valid API key)

##### [x] 9. Tuning Permissions (GEMINI-API-09-TUNING_PERMISSIONS.md) ✅
- [x] Create `test/ex_llm/gemini/permissions_test.exs`
  - [x] Test creating permissions
  - [x] Test listing permissions
  - [x] Test updating permissions
  - [x] Test deleting permissions
  - [x] Test transfer ownership
- [x] Implement `lib/ex_llm/gemini/permissions.ex`
  - [x] Permission CRUD operations
  - [x] Role management (READER, WRITER, OWNER)
  - [x] Grantee types (USER, GROUP, EVERYONE)
  - [x] Transfer ownership operation
- [x] Run tests and ensure they pass (unit tests pass, integration tests require OAuth2)
- [x] **Important Note**: Permissions API requires OAuth2 authentication, not API keys!

#### Phase 5: Semantic Retrieval

##### [x] 10. Question Answering (GEMINI-API-10-SEMANTIC-RETRIEVAL_QUESTION-ANSWERING.md) ✅
- [x] Create `test/ex_llm/gemini/qa_test.exs`
  - [x] Test query API with inline passages
  - [x] Test query API with semantic retriever
  - [x] Test answer generation with different styles
  - [x] Test with different answer styles (abstractive, extractive, verbose)
  - [x] Test temperature control and safety settings
  - [x] Test response parsing and error handling
- [x] Implement `lib/ex_llm/gemini/qa.ex`
  - [x] `generate_answer/4` - Semantic search and QA
  - [x] Answer generation config with temperature and safety
  - [x] Grounding with inline passages and semantic retriever
  - [x] Input validation and structured response parsing
  - [x] Support for both API key and OAuth2 authentication
- [x] Run tests and ensure they pass (unit tests pass, integration tests require valid API key/corpus)

##### [x] 11. Corpus Management (GEMINI-API-11-SEMANTIC-RETRIEVAL_CORPUS.md) ✅
- [x] Create `test/ex_llm/gemini/corpus_test.exs`
  - [x] Test creating corpora with auto-generated and custom names
  - [x] Test listing corpora with pagination support
  - [x] Test updating corpora (display name changes)
  - [x] Test deleting corpora with force option
  - [x] Test querying corpora with metadata filters
  - [x] Test input validation and error handling
  - [x] Test response parsing for all operations
- [x] Implement `lib/ex_llm/gemini/corpus.ex`
  - [x] Complete CRUD operations (create, list, get, update, delete)
  - [x] Semantic search with query_corpus function
  - [x] Metadata filter system with conditions and operators
  - [x] Input validation for all parameters
  - [x] OAuth2 authentication support (required for corpus operations)
  - [x] Pagination support for listing
  - [x] Structured response parsing
- [x] Run tests and ensure they pass (unit tests pass, integration tests require OAuth2 token)

##### [x] 12. Document Management (GEMINI-API-13-SEMANTIC-RETRIEVAL_DOCUMENT.md) ✅
- [x] Create `test/ex_llm/adapters/gemini/document_test.exs`
  - [x] Test creating documents with metadata
  - [x] Test listing documents with pagination
  - [x] Test updating documents with field masks
  - [x] Test deleting documents with force option
  - [x] Test querying documents with semantic search
  - [x] Test custom metadata handling (string, numeric, string list)
  - [x] Test validation and error handling
- [x] Implement `lib/ex_llm/gemini/document.ex`
  - [x] Complete CRUD operations (create, list, get, update, delete)
  - [x] Semantic search with query_document function
  - [x] Custom metadata system with all value types
  - [x] Input validation for all parameters
  - [x] Authentication support (API key and OAuth2)
  - [x] Pagination support for listing
  - [x] Comprehensive struct definitions
- [x] Run tests and ensure they pass (20 unit tests, 100% pass rate)

##### [x] 13. Chunk Management (GEMINI-API-12-SEMANTIC-RETRIEVAL_CHUNK.md) ✅
- [x] Create `test/ex_llm/adapters/gemini/chunk_test.exs`
  - [x] Test creating chunks with data and metadata
  - [x] Test listing chunks with pagination
  - [x] Test updating chunks with field masks
  - [x] Test deleting chunks
  - [x] Test batch operations (create, update, delete)
  - [x] Test validation and error handling for all operations
  - [x] Test struct definitions and parsing
- [x] Implement `lib/ex_llm/gemini/chunk.ex`
  - [x] Complete CRUD operations (create, list, get, update, delete)
  - [x] Batch operations (batch_create, batch_update, batch_delete)
  - [x] Custom metadata system with all value types
  - [x] Input validation for all parameters
  - [x] Authentication support (API key and OAuth2)
  - [x] Pagination support for listing
  - [x] Comprehensive struct definitions (Chunk, ChunkData, CustomMetadata, etc.)
- [x] Run tests and ensure they pass (22 unit tests, 100% pass rate)

##### [x] 14. Retrieval Permissions (GEMINI-API-14-SEMANTIC-RETRIEVAL_PERMISSIONS.md) ✅
- [x] Create `test/ex_llm/adapters/gemini/retrieval_permissions_test.exs`
  - [x] Test corpus permissions (create, list, get, update, delete)
  - [x] Test permission validation for corpus operations
  - [x] Test role hierarchy (READER, WRITER, OWNER)
  - [x] Test grantee types (USER, GROUP, EVERYONE)
  - [x] Test authentication methods (API key and OAuth2)
  - [x] Test struct definitions and JSON parsing
- [x] Extend existing `lib/ex_llm/gemini/permissions.ex`
  - [x] Corpus permissions already supported (corpora/{corpus} parent format)
  - [x] Complete CRUD operations for corpus permissions
  - [x] Input validation and error handling
  - [x] Support for all grantee types and roles
- [x] Run tests and ensure they pass (15 unit tests, 9 passing non-integration tests)

#### Phase 6: Integration

##### [x] 15. Complete Integration (GEMINI-API-15-ALL-METHODS.md) ✅
- [x] Create `test/ex_llm/adapters/gemini/integration_test.exs`
  - [x] Test end-to-end workflows with adapter
  - [x] Test cross-feature interactions and API modules
  - [x] Test error propagation and handling
  - [x] Test performance characteristics (marked with @tag :performance)
- [x] Enhance `lib/ex_llm/adapters/gemini.ex`
  - [x] Main adapter implementation (chat, streaming, embeddings)
  - [x] Integration with ExLLM interfaces (unified API)
  - [x] Feature detection and capabilities via ModelCapabilities
  - [x] Error handling and configuration validation
- [x] ExLLM module already supports Gemini provider
- [x] All individual API modules tested and working

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

# Automatic Test Response Caching Implementation Plan

## ✅ IMPLEMENTATION COMPLETE!

The automatic test response caching system has been successfully implemented with all core features:

### Completed Features:
- ✅ **Timestamp-based caching** - No version conflicts, natural chronological ordering
- ✅ **Automatic interception** - Zero configuration required for integration tests
- ✅ **Smart cache selection** - Multiple fallback strategies (latest_success, latest_any, best_match)
- ✅ **TTL management** - Configurable expiration with per-test-type overrides
- ✅ **Content deduplication** - Symlinks for identical responses save disk space
- ✅ **Comprehensive monitoring** - Hit rates, cost savings, performance metrics
- ✅ **Test helpers** - Easy cache management functions for tests
- ✅ **Mix tasks** - Command-line tools for cache operations
- ✅ **Full documentation** - Usage guide, configuration, best practices
- ✅ **Cache metadata tracking** - Responses include `from_cache` metadata flag

### Usage:
```elixir
# Automatic - just tag your tests!
@moduletag :integration  # That's it! Caching is automatic

# Check statistics
mix ex_llm.cache.stats

# Clear cache
mix ex_llm.cache.clear
```

---

## Overview

This document outlines the implementation plan for automatic test response caching in ExLLM. The goal is to automatically save every real API response during integration tests for replay in future test runs, reducing API costs and improving test reliability.

## Current State Analysis

### Existing Caching Infrastructure
ExLLM already has a sophisticated caching system with the following components:

1. **ExLLM.Cache** - Runtime ETS-based caching with optional disk persistence
2. **ExLLM.ResponseCache** - Disk-based response collection for Mock adapter
3. **ExLLM.CachingInterceptor** - Higher-level response collection for testing
4. **Mock Adapter Integration** - Ability to replay cached responses

### Current Limitations for Automatic Test Caching
- Manual activation required (environment variables/config)
- No automatic test environment detection
- Limited integration test scenario organization
- No cache versioning for API response format changes
- No selective caching for specific test patterns

## Implementation Tasks

### Phase 1: Foundation and Configuration (Priority: High)

#### Task 1.1: Create Test Cache Configuration System
- [ ] **File**: `lib/ex_llm/test_cache_config.ex`
- [ ] **Purpose**: Centralized configuration for test response caching
- [ ] **Features**:
  - Automatic detection of test environment (`Mix.env() == :test`)
  - Integration test detection (`:integration` tag presence)
  - OAuth2 test detection (`:oauth2` tag presence)
  - Configuration hierarchy: environment variables > test config > defaults
- [ ] **Configuration Options**:
  ```elixir
  config :ex_llm, :test_cache,
    enabled: true,                    # Enable automatic test caching
    auto_detect: true,               # Auto-enable in test environment
    cache_dir: "test/cache",         # Test cache directory
    organization: :by_provider,      # :by_provider, :by_test_module, :by_tag
    cache_integration_tests: true,   # Cache integration test responses
    cache_oauth2_tests: true,        # Cache OAuth2 test responses
    replay_by_default: true,         # Use cached responses by default
    save_on_miss: true,             # Save new responses when cache miss
    ttl: :timer.days(7),            # Cache TTL (7 days default, :infinity to never expire)
    
    # Timestamp-based caching
    timestamp_format: :iso8601,           # Filename timestamp format
    fallback_strategy: :latest_success,   # :latest_success, :latest_any, :best_match
    
    # Retention policy
    max_entries_per_cache: 10,            # Keep max 10 timestamped entries per cache key
    cleanup_older_than: :timer.days(30),  # Delete entries older than 30 days
    compress_older_than: :timer.days(7),  # Compress entries older than 7 days
    
    # Content optimization
    deduplicate_content: true,            # Use symlinks for identical content
    content_hash_algorithm: :sha256       # Hash algorithm for deduplication
  ```

#### Task 1.2: Enhance Test Environment Detection
- [ ] **File**: `lib/ex_llm/test_cache_detector.ex`
- [ ] **Purpose**: Intelligent detection of test scenarios requiring caching
- [ ] **Features**:
  - Detect integration tests by examining ExUnit tags
  - Detect OAuth2 tests by examining ExUnit tags and test module names
  - Runtime detection of live API usage vs mocked responses
  - Process-level state tracking for test caching mode
- [ ] **Functions**:
  ```elixir
  def integration_test_running?() :: boolean()
  def oauth2_test_running?() :: boolean()
  def should_cache_responses?() :: boolean()
  def get_current_test_context() :: %{module: atom(), tags: [atom()], name: string()}
  ```

#### Task 1.3: Create Test Cache Storage Backend
- [ ] **File**: `lib/ex_llm/cache/storage/test_cache.ex`
- [ ] **Purpose**: Specialized storage backend for timestamp-based test response caching
- [ ] **Features**:
  - Hierarchical organization by provider/test module/scenario
  - Timestamp-based file naming for natural chronological ordering
  - Rich metadata index with content deduplication
  - Fuzzy matching for similar requests across timestamps
  - TTL-based cache expiration and cleanup
  - Smart fallback strategies (latest success, latest any, best match)
- [ ] **Storage Structure**:
  ```
  test/cache/
  ├── integration/                 # Integration tests
  │   ├── anthropic/
  │   │   ├── chat_basic/
  │   │   │   ├── 2024-01-15T10-30-45Z.json    # Timestamped responses
  │   │   │   ├── 2024-01-20T14-22-10Z.json
  │   │   │   ├── 2024-01-22T09-15-33Z.json
  │   │   │   └── index.json                   # Cache index and metadata
  │   │   └── chat_streaming/
  │   ├── openai/
  │   └── gemini/
  └── oauth2/                      # OAuth2 tests
      ├── gemini/
      │   ├── corpus_crud/
      │   │   ├── 2024-01-18T16-45-12Z.json
      │   │   ├── 2024-01-21T11-30-25Z.json
      │   │   └── index.json
      │   └── document_operations/
  ```

#### Task 1.4: Implement TTL and Cache Selection System
- [ ] **File**: `lib/ex_llm/test_cache_ttl.ex`
- [ ] **Purpose**: Handle cache selection and TTL logic for timestamp-based caching
- [ ] **Features**:
  - Check cache age against configurable TTL across all timestamps
  - Smart selection of best cache entry based on fallback strategy
  - Configurable TTL per test type (integration vs OAuth2)
  - Force refresh options for specific test scenarios
- [ ] **Functions**:
  ```elixir
  def select_cache_entry(cache_dir, ttl, strategy) :: {:ok, timestamp} | {:expired, latest} | :none
  def cache_expired?(timestamp, ttl) :: boolean()
  def get_latest_valid_entry(cache_dir, ttl) :: {:ok, timestamp} | :none
  def get_latest_successful_entry(cache_dir, ttl) :: {:ok, timestamp} | :none
  def force_refresh_for_test?(test_context) :: boolean()
  def calculate_ttl(test_tags, provider) :: non_neg_integer() | :infinity
  ```

#### Task 1.5: Implement Timestamp Management and Cleanup System
- [ ] **File**: `lib/ex_llm/test_cache_timestamp.ex`
- [ ] **Purpose**: Manage timestamped cache entries and cleanup policies
- [ ] **Features**:
  - Generate consistent timestamp-based filenames
  - List and sort available timestamps for cache keys
  - Implement retention policies (max entries, max age)
  - Content deduplication using file hashes
  - Automatic cleanup of old timestamps
- [ ] **Functions**:
  ```elixir
  def generate_timestamp_filename() :: String.t()
  def parse_timestamp_from_filename(filename) :: {:ok, DateTime.t()} | :error
  def list_cache_timestamps(cache_dir) :: [DateTime.t()]
  def cleanup_old_entries(cache_dir, max_entries, max_age) :: cleanup_report()
  def deduplicate_content(cache_dir) :: dedup_report()
  def get_content_hash(file_path) :: String.t()
  ```

#### Task 1.6: Enhanced Cache Index with Timestamp Tracking
- [ ] **File**: `lib/ex_llm/test_cache_index.ex`
- [ ] **Purpose**: Maintain index of timestamped cache entries with metadata
- [ ] **Index Structure**:
  ```elixir
  %CacheIndex{
    # Cache key identification
    cache_key: "anthropic/chat_basic",
    test_context: %{module: "AnthropicIntegrationTest", tags: [:integration]},
    
    # TTL configuration
    ttl: :timer.days(7),
    fallback_strategy: :latest_success,
    
    # Timestamp entries (sorted newest first)
    entries: [
      %{
        timestamp: ~U[2024-01-22 09:15:33Z],
        filename: "2024-01-22T09-15-33Z.json",
        status: :success,           # :success, :error, :timeout
        size: 1024,
        content_hash: "abc123def",  # For deduplication
        response_time_ms: 1250,
        api_version: "2023-06-01",
        cost: %{input: 0.001, output: 0.003, total: 0.004}
      },
      %{
        timestamp: ~U[2024-01-20 14:22:10Z],
        filename: "2024-01-20T14-22-10Z.json", 
        status: :success,
        size: 998,
        content_hash: "abc123def",  # Same hash = duplicate content
        response_time_ms: 980,
        api_version: "2023-06-01",
        cost: %{input: 0.001, output: 0.002, total: 0.003}
      }
    ],
    
    # Usage statistics
    total_requests: 45,
    cache_hits: 43,
    last_accessed: ~U[2024-01-22 12:00:00Z],
    access_count: 45,
    
    # Cleanup tracking
    last_cleanup: ~U[2024-01-20 00:00:00Z],
    cleanup_before: ~U[2024-01-01 00:00:00Z]  # Delete entries before this date
  }
  ```

### Phase 2: Automatic Response Capture (Priority: High)

#### Task 2.1: Create Test Response Interceptor
- [ ] **File**: `lib/ex_llm/test_response_interceptor.ex`
- [ ] **Purpose**: Automatically intercept and cache responses during tests
- [ ] **Features**:
  - Hook into HTTPClient request/response cycle
  - Automatic cache key generation based on test context
  - Rich metadata capture (timing, test info, provider details)
  - Streaming response reassembly and caching
- [ ] **Integration Points**:
  - `ExLLM.Adapters.Shared.HTTPClient`
  - `ExLLM.Cache.with_cache/3`
  - ExUnit test lifecycle hooks

#### Task 2.2: Enhance HTTPClient with Timestamp-Based Test Caching
- [ ] **File**: `lib/ex_llm/adapters/shared/http_client.ex`
- [ ] **Purpose**: Add timestamp-based test caching support to HTTP client
- [ ] **Changes**:
  - Add test cache check before making real HTTP requests
  - Select best cache entry based on TTL and fallback strategy
  - Save new responses with timestamp-based filenames
  - Capture and save responses when test caching is enabled
  - Maintain original error handling and retry logic
  - Support for both streaming and non-streaming responses
  - Fallback to older timestamps when fresh requests fail
- [ ] **New Functions**:
  ```elixir
  defp maybe_use_test_cache(url, body, headers, opts)
  defp select_best_cache_entry(cache_dir, ttl, strategy)
  defp save_timestamped_response(request_data, response_data, metadata)
  defp build_test_cache_key(url, body, test_context)
  defp fallback_to_older_timestamp(cache_dir, error)
  defp update_cache_index(cache_dir, new_entry)
  ```

#### Task 2.3: Implement Response Metadata Capture
- [ ] **File**: `lib/ex_llm/test_response_metadata.ex`
- [ ] **Purpose**: Capture comprehensive metadata for cached responses
- [ ] **Metadata Fields**:
  ```elixir
  %ResponseMetadata{
    # Request Information
    provider: "anthropic",
    endpoint: "/v1/messages",
    method: "POST",
    request_body: %{...},
    request_headers: [...],
    
    # Response Information
    response_body: %{...},
    response_headers: [...],
    status_code: 200,
    response_time_ms: 1245,
    
    # Test Context
    test_module: "ExLLM.AnthropicIntegrationTest",
    test_name: "basic chat completion",
    test_tags: [:integration, :anthropic],
    test_pid: "#PID<0.123.45>",
    
    # Caching Information
    cached_at: ~U[2024-01-01 00:00:00Z],
    cache_version: "1.0",
    api_version: "2023-06-01",
    
    # Usage Tracking
    usage: %{input_tokens: 10, output_tokens: 25, total_tokens: 35},
    cost: %{input: 0.0001, output: 0.0005, total: 0.0006}
  }
  ```

### Phase 3: Intelligent Cache Replay (Priority: High)

#### Task 3.1: Create Test Cache Matcher
- [ ] **File**: `lib/ex_llm/test_cache_matcher.ex`
- [ ] **Purpose**: Intelligent matching of requests to cached responses
- [ ] **Features**:
  - Exact match for identical requests
  - Fuzzy matching for similar requests (configurable tolerance)
  - Content-based matching for different formatting
  - Test context-aware matching
- [ ] **Matching Strategies**:
  ```elixir
  def exact_match(request, cached_requests)
  def fuzzy_match(request, cached_requests, tolerance \\ 0.9)
  def semantic_match(request, cached_requests)
  def context_match(request, cached_requests, test_context)
  ```

#### Task 3.2: Implement Cache-First Request Strategy with Timestamps
- [ ] **File**: `lib/ex_llm/test_cache_strategy.ex`
- [ ] **Purpose**: Implement cache-first strategy for test requests with timestamp selection
- [ ] **Strategy Flow**:
  1. Check if test caching is enabled
  2. Generate cache key from request and test context
  3. Load cache index for the cache key
  4. **Select best timestamp entry based on strategy**:
     - `:latest_success`: Most recent successful response within TTL
     - `:latest_any`: Most recent response (success or error) within TTL
     - `:best_match`: Best matching response considering content similarity
  5. If valid timestamp found: return cached response
  6. If no valid cache or expired: make real request and save with new timestamp
  7. If real request fails: fallback to older timestamps if available
- [ ] **Fallback Handling**:
  - Graceful degradation when cache is corrupted
  - Fallback to older timestamps when refresh fails
  - Configurable cache miss behavior (fail vs. make real request)
  - Cache warming during test setup
  - Automatic cleanup based on age and count limits

#### Task 3.3: Add Cache Statistics and Monitoring
- [ ] **File**: `lib/ex_llm/test_cache_stats.ex`
- [ ] **Purpose**: Track cache performance and cost savings with timestamp-based metrics
- [ ] **Features**:
  - Cache hit/miss ratios per test suite
  - TTL-based refresh statistics
  - Timestamp fallback usage tracking
  - Cost savings calculations
  - Response time comparisons (cached vs. real)
  - Test suite completion time improvements
  - Storage overhead monitoring with deduplication stats
- [ ] **Reporting**:
  ```elixir
  def print_cache_summary()
  # Output:
  # Test Cache Summary:
  # ==================
  # Total Requests: 150
  # Cache Hits: 130 (86.7%)
  # Cache Misses: 8 (5.3%)
  # TTL Refreshes: 12 (8.0%)
  # Fallback to Older Timestamp: 2 (1.3%)
  # Cost Savings: $2.45
  # Time Savings: 45.2 seconds
  # Storage Used: 15.3 MB (unique: 8.1 MB, duplicates: 7.2 MB)
  # Deduplication Ratio: 47% space saved
  # Total Timestamps: 234
  # Oldest Cache Entry: 3 days ago
  # Average Cache Age: 1.2 days
  ```

### Phase 4: Test Integration and Configuration (Priority: Medium)

#### Task 4.1: Update Test Helper Functions
- [ ] **File**: `test/support/test_helpers.ex`
- [ ] **Purpose**: Add test cache helpers and utilities with timestamp-based operations
- [ ] **New Functions**:
  ```elixir
  def with_test_cache(opts \\ [], func)
  def clear_test_cache(scope \\ :all)
  def warm_test_cache(test_module)
  def verify_cache_integrity()
  def force_cache_miss(pattern)
  def force_cache_refresh(pattern)
  def set_test_ttl(test_pattern, ttl)
  def list_cache_timestamps(cache_pattern)
  def restore_cache_timestamp(cache_pattern, timestamp)
  def cleanup_old_timestamps(max_age \\ :timer.days(30))
  def deduplicate_cache_content(cache_pattern \\ :all)
  def get_cache_stats(test_module \\ :all)
  def set_fallback_strategy(test_pattern, strategy)
  ```

#### Task 4.2: Enhance Integration Test Setup
- [ ] **Files**: All integration test files
- [ ] **Purpose**: Add automatic test caching to integration tests
- [ ] **Changes**:
  - Add setup hooks for test cache initialization
  - Configure cache warming for known test scenarios
  - Add cache verification in test teardown
  - Implement cache-aware test ordering

#### Task 4.3: Update OAuth2 Test Configuration
- [ ] **Files**: `test/ex_llm/adapters/gemini/*oauth2*_test.exs`
- [ ] **Purpose**: Special handling for OAuth2 test caching
- [ ] **Features**:
  - OAuth2 token anonymization in cache
  - Request signature generation excluding sensitive data
  - Automatic cache invalidation on token refresh
  - Special handling for time-sensitive operations

### Phase 5: TTL Management and Timestamp Cleanup (Priority: Medium)

#### Task 5.1: Implement Automatic Cache Cleanup Scheduler
- [ ] **File**: `lib/ex_llm/test_cache_scheduler.ex`
- [ ] **Purpose**: Background process for managing cache TTL and timestamp cleanup
- [ ] **Features**:
  - Periodic scanning for expired cache entries
  - Proactive refresh of critical cache entries before expiration
  - Automatic timestamp cleanup based on age and count limits
  - Content deduplication across timestamps
  - Configurable cleanup strategies (eager, lazy, manual)
- [ ] **Functions**:
  ```elixir
  def start_scheduler(opts \\ []) :: {:ok, pid()} | {:error, reason}
  def schedule_refresh(cache_pattern, delay) :: :ok
  def run_cleanup_cycle() :: cleanup_report()
  def run_deduplication_cycle() :: dedup_report()
  def refresh_critical_caches() :: refresh_report()
  ```

#### Task 5.2: Enhanced API Version Detection and Compatibility
- [ ] **File**: `lib/ex_llm/test_cache_api_versioning.ex`
- [ ] **Purpose**: Handle API version changes and timestamp-based fallback strategies
- [ ] **Features**:
  - API version detection and compatibility checking
  - Timestamp-based fallback when API versions differ
  - Automatic cache refresh when breaking API changes detected
  - Smart selection of compatible timestamps
  - API evolution tracking across timestamps

#### Task 5.3: Add Cache Compression and Optimization
- [ ] **File**: `lib/ex_llm/test_cache_optimizer.ex`
- [ ] **Purpose**: Optimize cache storage and performance
- [ ] **Features**:
  - Response compression for large payloads
  - Cache deduplication for identical responses
  - Periodic cache cleanup and optimization
  - Cache size monitoring and management

#### Task 5.4: Create Enhanced Cache Management CLI
- [x] **File**: `lib/mix/tasks/ex_llm.cache.ex`
- [x] **Purpose**: Command-line tools for cache management with TTL and timestamps
- [x] **Commands**:
  ```bash
  # Basic cache management
  mix ex_llm.cache.clear                    # Clear all test cache
  mix ex_llm.cache.stats                    # Show cache statistics with TTL info
  mix ex_llm.cache.verify                   # Verify cache integrity
  mix ex_llm.cache.warm --suite oauth2      # Warm cache for test suite
  
  # TTL and refresh management
  mix ex_llm.cache.refresh --expired        # Refresh all expired cache entries
  mix ex_llm.cache.refresh --pattern "openai/*"  # Refresh specific pattern
  mix ex_llm.cache.set-ttl --pattern "oauth2/*" --ttl "1d"  # Set TTL for pattern
  mix ex_llm.cache.check-expiry             # Show cache entries near expiration
  
  # Timestamp management
  mix ex_llm.cache.timestamps --list --pattern "anthropic/*"  # List timestamps for pattern
  mix ex_llm.cache.timestamps --cleanup     # Clean up old timestamps
  mix ex_llm.cache.timestamps --restore "2024-01-15T10:30:45Z"  # Restore specific timestamp
  mix ex_llm.cache.deduplicate              # Remove duplicate content across timestamps
  
  # Import/Export with timestamps
  mix ex_llm.cache.export --format json --include-timestamps  # Export with all timestamps
  mix ex_llm.cache.import --file cache.json --preserve-timestamps  # Import preserving timestamps
  mix ex_llm.cache.compress --older-than "7d"  # Compress old timestamps
  ```

### Phase 6: Documentation and Testing (Priority: Medium)

#### Task 6.1: Create Test Caching Documentation
- [x] **File**: `docs/test_caching.md`
- [x] **Content**:
  - How automatic test caching works
  - Configuration options and best practices
  - Troubleshooting common issues
  - Cost savings and performance benefits
  - Integration with CI/CD pipelines

#### Task 6.2: Add Test Coverage for Caching System
- [ ] **Files**: `test/ex_llm/test_cache_*_test.exs`
- [ ] **Purpose**: Comprehensive testing of caching functionality
- [ ] **Test Categories**:
  - Unit tests for cache components
  - Integration tests for end-to-end caching
  - Performance tests for cache overhead
  - Edge case handling tests

#### Task 6.3: Update Configuration Documentation
- [x] **Files**: `README.md`, `config/config.exs`
- [x] **Purpose**: Document new test caching configuration options
- [x] **Content**:
  - Environment variable documentation
  - Configuration examples for different scenarios
  - Migration guide from manual to automatic caching

## Implementation Timeline

### Week 1-2: Foundation (Phase 1)
- Complete Tasks 1.1-1.6
- Basic test environment detection and configuration
- TTL system and backup/versioning infrastructure

### Week 3-4: Automatic Capture (Phase 2) 
- Complete Tasks 2.1-2.3
- Core response interception and storage functionality
- TTL-aware cache checking and refresh logic

### Week 5-6: Cache Replay (Phase 3)
- Complete Tasks 3.1-3.3
- Intelligent cache matching and replay system with TTL support
- Version fallback mechanisms

### Week 7-8: Integration (Phase 4)
- Complete Tasks 4.1-4.3
- Full integration with existing test suites
- TTL and versioning helper functions

### Week 9-10: TTL Management and Cleanup (Phase 5)
- Complete Tasks 5.1-5.4
- Automated refresh scheduling and version cleanup
- Enhanced CLI tools for cache management

### Week 11+: Documentation and Testing (Phase 6)
- Complete Tasks 6.1-6.3
- Comprehensive documentation and test coverage
- Performance optimization and final polish

## Success Criteria

### Primary Goals
- [ ] Integration tests automatically cache responses by default
- [ ] OAuth2 tests work seamlessly with cached responses
- [ ] Cost reduction of >90% for repeated test runs
- [ ] Zero configuration required for basic usage
- [ ] Backward compatibility with existing test infrastructure

### Performance Targets
- [ ] Cache hit ratio >95% for repeated test runs
- [ ] Test suite runtime improvement >50% with cache
- [ ] Cache storage overhead <100MB for full test suite
- [ ] Cache lookup time <10ms per request

### Quality Assurance
- [ ] All existing tests pass with caching enabled
- [ ] Cache integrity verified with checksum validation
- [ ] Graceful fallback when cache is unavailable
- [ ] Clear error messages for cache-related issues

## Risk Mitigation

### Technical Risks
- **Cache corruption**: Implement checksum validation and automatic cache repair
- **Test flakiness**: Ensure cached responses maintain original timing and error patterns
- **Storage requirements**: Implement compression and cleanup strategies
- **Integration complexity**: Maintain clear separation between caching and core functionality

### Process Risks
- **Breaking changes**: Comprehensive test coverage and gradual rollout
- **Performance regression**: Benchmark cache overhead and optimize hot paths
- **Maintenance burden**: Clear documentation and automated cache management

## Configuration Examples

### Development Environment
```elixir
# config/test.exs
config :ex_llm, :test_cache,
  enabled: true,
  auto_detect: true,
  cache_dir: "test/cache",
  replay_by_default: true,
  save_on_miss: true,
  ttl: :timer.days(7),              # Refresh cache weekly
  fallback_strategy: :latest_success,
  max_entries_per_cache: 5,
  deduplicate_content: true
```

### CI Environment
```bash
# .github/workflows/test.yml
env:
  EX_LLM_TEST_CACHE_ENABLED: "true"
  EX_LLM_TEST_CACHE_DIR: "/tmp/ex_llm_cache"
  EX_LLM_TEST_CACHE_REPLAY_ONLY: "true"  # Don't make real requests in CI
  EX_LLM_TEST_CACHE_TTL: "0"             # Use any cached response in CI
  EX_LLM_TEST_CACHE_FALLBACK_STRATEGY: "latest_any"  # Use any timestamp if needed
```

### Local Development
```bash
# Force cache miss for specific tests
export EX_LLM_TEST_CACHE_FORCE_MISS="AnthropicIntegrationTest"

# Force cache refresh for specific tests (ignores TTL)
export EX_LLM_TEST_CACHE_FORCE_REFRESH="OAuth2Test"

# Set custom TTL for development
export EX_LLM_TEST_CACHE_TTL="3600"  # 1 hour TTL

# Set fallback strategy
export EX_LLM_TEST_CACHE_FALLBACK_STRATEGY="latest_success"  # or latest_any, best_match

# Disable caching for debugging
export EX_LLM_TEST_CACHE_ENABLED="false"

# Use specific timestamp for testing
export EX_LLM_TEST_CACHE_USE_TIMESTAMP="2024-01-15T10:30:45Z"

# Control cleanup behavior
export EX_LLM_TEST_CACHE_MAX_ENTRIES="10"
export EX_LLM_TEST_CACHE_CLEANUP_OLDER_THAN="30d"
```

This comprehensive plan builds upon ExLLM's existing caching infrastructure to provide seamless, automatic test response caching that will significantly reduce API costs and improve test reliability.

---

## Notes

- The library aims to be the go-to solution for LLM integration in Elixir
- Focus remains on being a unified, reliable LLM client library
- All features should work consistently across providers where possible
- Provider-specific features should be clearly documented
- Performance and cost efficiency are key priorities
- Features that belong at the application layer have been moved to docs/DROPPED.md