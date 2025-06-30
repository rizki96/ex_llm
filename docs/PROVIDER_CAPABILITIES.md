# Provider Capabilities Guide

This document explains how to find and update provider capabilities in ExLLM.

## Current Provider Capabilities

Provider capabilities are defined in `lib/ex_llm/provider_capabilities.ex`. Each provider has:

- **endpoints**: API endpoints available (e.g., `:chat`, `:embeddings`, `:images`)
- **features**: Capabilities supported (e.g., `:streaming`, `:vision`, `:function_calling`)
- **authentication**: Auth methods supported (e.g., `:api_key`, `:oauth2`)
- **limitations**: Known limitations and constraints

## How to Find Provider Capabilities

### 1. Official Documentation

Always check the official documentation for the most accurate information:

- **OpenAI**: https://platform.openai.com/docs/api-reference
  - Models: https://platform.openai.com/docs/models
  - Capabilities: Check individual endpoint docs
  
- **Anthropic**: https://docs.anthropic.com/
  - Models: https://docs.anthropic.com/en/docs/models
  - Features: https://docs.anthropic.com/en/docs/capabilities
  
- **Google Gemini**: https://ai.google.dev/docs
  - Models: https://ai.google.dev/models/gemini
  - API capabilities: https://ai.google.dev/api/rest
  
- **AWS Bedrock**: https://docs.aws.amazon.com/bedrock/
  - Model providers: https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html
  
- **Groq**: https://console.groq.com/docs
  - Models: https://console.groq.com/docs/models
  
- **X.AI**: https://docs.x.ai/
  - API reference: https://docs.x.ai/api

### 2. API Discovery Endpoints

Some providers offer API endpoints to discover capabilities:

```elixir
# OpenAI - List available models
{:ok, models} = ExLLM.list_models(:openai)

# Check if a model supports specific features
# Note: Programmatic capability checking is under development
# For now, refer to config/models/ directory
```

### 3. Feature Mapping

Here's how common features map across providers:

| Feature | OpenAI | Anthropic | Gemini | Bedrock |
|---------|---------|-----------|---------|----------|
| Chat | ✓ `/v1/chat/completions` | ✓ `/v1/messages` | ✓ `/v1beta/models/.../generateContent` | ✓ `/invoke` |
| Embeddings | ✓ `/v1/embeddings` | ✗ | ✓ `/v1beta/models/.../embedContent` | ✓ (varies) |
| Images | ✓ `/v1/images/generations` | ✗ | ✗ | ✗ (use Stable Diffusion) |
| Vision | ✓ (GPT-4V) | ✓ (Claude 3) | ✓ (Gemini Pro Vision) | ✓ (varies) |
| Function Calling | ✓ | ✓ (Tools) | ✓ | ✓ (varies) |
| Streaming | ✓ | ✓ | ✓ | ✓ |
| JSON Mode | ✓ | ✓ | ✓ | ✓ (varies) |

## Updating Provider Capabilities

When updating capabilities in `provider_capabilities.ex`:

1. **Check Official Docs**: Always verify against the latest documentation
2. **Test Features**: Actually test that features work as expected
3. **Update Both Places**: Update both `endpoints` and `features` arrays
4. **Document Limitations**: Add any constraints to the `limitations` map

### Example Update

```elixir
# In provider_capabilities.ex
openai: %__MODULE__.ProviderInfo{
  # ... other fields ...
  endpoints: [
    :chat,           # /v1/chat/completions
    :embeddings,     # /v1/embeddings
    :images,         # /v1/images/generations
    :audio,          # /v1/audio/transcriptions, /v1/audio/translations, /v1/audio/speech
    :moderations,    # /v1/moderations
    :files,          # /v1/files
    :fine_tuning,    # /v1/fine-tuning/jobs
    :assistants,     # /v1/assistants
    :threads,        # /v1/threads
    :runs,           # /v1/threads/{thread_id}/runs
    :vector_stores   # /v1/vector_stores
  ],
  features: [
    :streaming,
    :function_calling,
    :vision,
    :image_generation,    # DALL-E
    :speech_synthesis,    # TTS
    :speech_recognition,  # Whisper
    :embeddings,
    :fine_tuning_api,
    :assistants_api,
    :code_interpreter,
    :retrieval,
    :structured_outputs,
    :json_mode,
    :logprobs,
    :seed_control,
    # ... etc
  ]
}
```

## Testing Provider Capabilities

To verify capabilities are correctly configured:

```elixir
# Check if a provider supports a feature
ExLLM.ProviderCapabilities.supports?(:openai, :image_generation)
# => true

# Find all providers that support embeddings
ExLLM.ProviderCapabilities.find_providers_with_features([:embeddings])
# => [:openai, :gemini, :bedrock, :ollama]

# Get full capability info  
# Note: Programmatic capabilities API under development
# For now, check config/models/ YAML files for provider capabilities
```

## Common Gotchas

1. **Feature vs Endpoint**: Some capabilities are features (`:vision`), others are endpoints (`:images`)
2. **Provider-Specific Names**: Each provider may call the same feature differently
3. **Beta Features**: Mark beta/experimental features in limitations
4. **Model-Specific**: Some features depend on the specific model (e.g., vision only in GPT-4V)
5. **Region/Tier Limits**: Some features have geographic or pricing tier restrictions

## Contributing

When adding a new provider or updating capabilities:

1. Research the provider's full API surface
2. Test each capability you add
3. Document any special requirements
4. Update this guide if you discover new patterns