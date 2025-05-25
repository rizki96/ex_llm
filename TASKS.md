# ExLLM Tasks

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

## In Progress

- [ ] Enhanced streaming error recovery
- [ ] Request retry logic with exponential backoff

## Todo

### Features
- [ ] Function calling support across all adapters
- [ ] Vision/multimodal support standardization
- [ ] Embeddings API
- [ ] Fine-tuning management
- [ ] Model capability discovery
- [ ] Token-level streaming (not just chunk-level)
- [ ] Response caching with TTL

### Provider Enhancements
- [ ] Cohere adapter
- [ ] Hugging Face Inference API adapter
- [ ] Azure OpenAI adapter (different from OpenAI)
- [ ] Replicate adapter
- [ ] Together AI adapter
- [ ] Perplexity adapter

### Advanced Context Management
- [ ] Semantic chunking for better truncation
- [ ] Context compression techniques
- [ ] Multi-conversation context sharing
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
- All features should work consistently across providers where possible
- Provider-specific features should be clearly documented
- Performance and cost efficiency are key priorities