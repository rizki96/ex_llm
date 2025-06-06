# ExLLM Example Application

The comprehensive example application (`example_app.exs`) demonstrates all features of the ExLLM library in an interactive CLI format.

## Quick Start

### Using Ollama (Default - Local)

1. Install Ollama from https://ollama.ai
2. Ensure Ollama is running:
   ```bash
   ollama serve  # if not already running
   ```
3. Run the example app (uses existing Qwen3 8B model):
   ```bash
   ./example_app.exs
   ```

Note: The app uses the `hf.co/unsloth/Qwen3-8B-GGUF:IQ4_XS` model which can be downloaded from https://huggingface.co/unsloth/Qwen3-8B-GGUF. This is a 4.6 GB model with efficient IQ4_XS quantization for fast inference. If you want to use a different model, you can set the `OLLAMA_MODEL` environment variable to the desired model name, e.g., `OLLAMA_MODEL=llama3.2:3b ./example_app.exs`.

### Using Other Providers

Set the `PROVIDER` environment variable and ensure you have the required API key:

```bash
# OpenAI
export OPENAI_API_KEY="your-key"
PROVIDER=openai ./example_app.exs

# Anthropic (Claude)
export ANTHROPIC_API_KEY="your-key" 
PROVIDER=anthropic ./example_app.exs

# Groq (Fast Cloud)
export GROQ_API_KEY="your-key"
PROVIDER=groq ./example_app.exs

# Mock (Testing - no API key needed)
PROVIDER=mock ./example_app.exs
```

## Features Demonstrated

### 1. Basic Chat
Simple message exchange with an LLM, showing token usage and response time.

### 2. Streaming Chat
Real-time streaming responses that appear as they're generated.

### 3. Session Management
Multi-turn conversations with history preservation and session saving/loading.

### 4. Context Management
Handling of token limits, context window validation, and message truncation strategies.

### 5. Function Calling
LLM-driven function execution for tasks like weather queries and calculations.

### 6. Structured Output (Instructor)
Extract structured data from unstructured text using Ecto schemas.

### 7. Vision/Multimodal
Analyze images from URLs or local files, extract text (OCR).

### 8. Embeddings & Semantic Search
Generate text embeddings and perform similarity-based search.

### 9. Model Capabilities Explorer
Discover model features, compare models, and get recommendations.

### 10. Caching Demo
Response caching for improved performance and cost savings.

### 11. Retry & Error Recovery
Automatic retry with exponential backoff for transient failures.

### 12. Cost Tracking
Track API usage costs across multiple requests.

### 13. Advanced Features
Demonstrations of stream recovery, dynamic model selection, and more.

## Provider Support

| Feature | Ollama | OpenAI | Anthropic | Groq | Mock |
|---------|--------|--------|-----------|------|------|
| Basic Chat | ✓ | ✓ | ✓ | ✓ | ✓ |
| Streaming | ✓ | ✓ | ✓ | ✓ | ✓ |
| Functions | ✓ | ✓ | ✓ | ✓ | ✓ |
| Vision | ✓ | ✓* | ✓* | ✗ | ✗ |
| Embeddings | ✓ | ✓ | ✗ | ✗ | ✓ |
| Cost Tracking | ✗ | ✓ | ✓ | ✓ | ✓ |

\* Only specific models support vision (e.g., gpt-4o, claude-3-5-sonnet)

## Troubleshooting

### Ollama Connection Error
- Ensure Ollama is running: `ollama serve`
- Check if the model is installed: `ollama list`
- Verify the API is accessible: `curl http://localhost:11434/api/tags`

### API Key Errors
- Ensure environment variables are set correctly
- Check API key permissions and quotas
- Verify the key is active and not expired

### Feature Not Available
Some features are provider-specific. The app will notify you if a feature isn't supported by your chosen provider and may offer alternatives.

