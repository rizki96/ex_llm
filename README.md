# ExLLM

A unified Elixir client for Large Language Models with integrated cost tracking, providing a consistent interface across multiple LLM providers.

> ⚠️ **Alpha Quality Software**: This library is in early development. APIs may change without notice until version 1.0.0 is released. Use in production at your own risk.

## What's New in v0.4.2

- **Updated Default Model**: Changed default Bumblebee model to Qwen/Qwen3-0.6B
- **Breaking Change**: Renamed `:local` provider atom to `:bumblebee` for clarity
- **Enhanced Documentation**: Improved package structure and documentation references

## Features

- **Unified API**: Single interface for multiple LLM providers
- **Streaming Support**: Real-time streaming responses with error recovery
- **Cost Tracking**: Automatic cost calculation for all API calls
- **Session Management**: Built-in conversation state tracking and persistence
- **Structured Outputs**: Schema validation and retries via Instructor integration
- **Function Calling**: Unified interface for tool use across providers
- **Model Discovery**: Query and compare model capabilities across providers
- **Response Caching**: Cache real provider responses for offline testing and cost reduction
- **Type Safety**: Comprehensive typespecs and structured data
- **Extensible**: Easy to add new LLM providers via adapter pattern

## Supported Providers

ExLLM supports **14 providers** with access to **300+ models**:

- **Anthropic Claude** - Claude 4, 3.7, 3.5, and 3 series models
- **OpenAI** - GPT-4.1, o1 reasoning models, GPT-4o, and GPT-3.5 series
- **AWS Bedrock** - Multi-provider access (Anthropic, Amazon Nova, Meta Llama, etc.)
- **Google Gemini** - Gemini 2.5, 2.0, and 1.5 series with multimodal support
- **OpenRouter** - Access to 300+ models from multiple providers
- **Groq** - Ultra-fast inference with Llama 4, DeepSeek R1, and more
- **X.AI** - Grok models with web search and reasoning capabilities
- **Mistral AI** - Mistral Large, Pixtral, and specialized code models
- **Perplexity** - Search-enhanced language models
- **Ollama** - Local model runner (any model in your installation)
- **LM Studio** - Local model server with OpenAI-compatible API
- **Bumblebee** - Local model inference with Elixir/Nx
- **Mock Adapter** - For testing and development

## Installation

Add `ex_llm` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.4.2"},
    
    # Optional hardware acceleration backends (choose one):
    {:exla, "~> 0.7", optional: true},
    
    # Optional: For Apple Silicon Metal acceleration
    {:emlx, github: "elixir-nx/emlx", branch: "main", optional: true}
  ]
end
```

## Quick Start

### 1. Configuration

Set your API keys as environment variables:

```bash
export ANTHROPIC_API_KEY="your-anthropic-key"
export OPENAI_API_KEY="your-openai-key"
export GROQ_API_KEY="your-groq-key"
# ... other provider keys as needed
```

### 2. Basic Usage

```elixir
# Single completion
{:ok, response} = ExLLM.chat(:anthropic, [
  %{role: "user", content: "Explain quantum computing in simple terms"}
])

IO.puts(response.content)

# Streaming response
ExLLM.chat_stream(:openai, [
  %{role: "user", content: "Write a short story"}
], fn chunk ->
  IO.write(chunk.delta)
end)

# With session management
{:ok, session} = ExLLM.Session.new(:groq)
{:ok, session, response} = ExLLM.Session.chat(session, "Hello!")
{:ok, session, response} = ExLLM.Session.chat(session, "How are you?")
```

## Documentation

📚 **[Quick Start Guide](docs/QUICKSTART.md)** - Get up and running in 5 minutes  
📖 **[User Guide](docs/USER_GUIDE.md)** - Comprehensive documentation of all features  
🔧 **[Logger Guide](docs/LOGGER.md)** - Debug logging and troubleshooting  
⚡ **[Provider Capabilities](docs/PROVIDER_CAPABILITIES.md)** - Feature comparison across providers

### Key Topics Covered in the User Guide

- **Configuration**: Environment variables, config files, and provider setup
- **Chat Completions**: Messages, parameters, and response handling
- **Streaming**: Real-time responses with error recovery
- **Session Management**: Conversation state and persistence
- **Function Calling**: Tool use and structured interactions
- **Vision & Multimodal**: Image processing and multimodal inputs
- **Cost Tracking**: Automatic cost calculation and token estimation
- **Error Handling**: Retry logic and error recovery strategies
- **Response Caching**: Cache real responses for testing and development
- **Model Discovery**: Query available models and capabilities
- **Testing**: Mock adapter and testing strategies

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

- 📖 **Documentation**: [User Guide](docs/USER_GUIDE.md)
- 🐛 **Issues**: [GitHub Issues](https://github.com/azmaveth/ex_llm/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/azmaveth/ex_llm/discussions)