# Model Configuration Update Scripts

This directory contains scripts to automatically fetch and update model information from various LLM providers.

## Usage

### Update all providers
```bash
./scripts/update_models.sh
```

### Update a specific provider
```bash
./scripts/update_models.sh anthropic
./scripts/update_models.sh openai
./scripts/update_models.sh gemini
./scripts/update_models.sh openrouter
./scripts/update_models.sh ollama
./scripts/update_models.sh bedrock
```

## How it works

The scripts fetch model information from:
- **API endpoints** when available (OpenAI, Gemini, OpenRouter, Ollama)
- **Static data** for providers without public APIs (Anthropic, Bedrock)
- **Documentation scraping** as a fallback (currently uses static data)

The scripts will:
1. Load existing YAML configuration if it exists
2. Fetch latest model data from the provider
3. Merge the data, preserving any manual additions
4. Update pricing, context windows, and capabilities
5. Save back to the YAML file with metadata

## Environment Variables

Some providers require API keys to fetch detailed model information:

```bash
export ANTHROPIC_API_KEY="your-key"      # Optional - uses static data if not provided
export OPENAI_API_KEY="your-key"         # Optional - uses static data if not provided
export GEMINI_API_KEY="your-key"         # Optional - uses static data if not provided
export GOOGLE_API_KEY="your-key"         # Alternative to GEMINI_API_KEY
export OPENROUTER_API_KEY="your-key"     # Not required - public API
```

## Manual Updates

The YAML files in `config/models/` can be edited manually. The update scripts will preserve your manual changes while updating known fields.

### YAML Structure
```yaml
provider: anthropic
default_model: "claude-3-5-sonnet-20241022"
models:
  claude-3-5-sonnet-20241022:
    context_window: 200000
    max_output_tokens: 8192
    pricing:
      input: 3.00   # per million tokens
      output: 15.00 # per million tokens
    capabilities:
      - streaming
      - function_calling
      - vision
    release_date: "2024-10-22"  # Optional metadata
```

## Implementation Details

### Python Script (`fetch_provider_models.py`)
- More robust for web scraping and API calls
- Handles retries and error cases gracefully
- Preserves existing manual configuration

### Elixir Script (`update_model_configs.exs`)
- Uses Mix.install for dependencies
- Native to the ExLLM project
- Good for simple API calls

### Bash Wrapper (`update_models.sh`)
- Detects available runtime (Python or Elixir)
- Provides consistent interface
- Handles dependency checks

## Adding New Providers

To add a new provider:

1. Add the provider to the scripts
2. Implement the fetch method
3. Define the YAML structure
4. Add any required API endpoints

## Troubleshooting

- **No models found**: Check API keys and network connection
- **Ollama errors**: Ensure Ollama is running locally (`ollama serve`)
- **Permission denied**: Run `chmod +x scripts/*.sh scripts/*.py`
- **Missing dependencies**: Install with `pip3 install requests pyyaml`