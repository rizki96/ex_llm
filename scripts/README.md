# Model Configuration Scripts

This directory contains scripts to update model configurations from various sources.

## Scripts

- **`update_models.sh`** - Main entry point for all updates
- **`fetch_provider_models.py`** - Fetches model info from provider APIs
- **`sync_from_litellm.py`** - Syncs model data from LiteLLM's database

## Usage

### Update from Provider APIs

Update all providers:
```bash
./scripts/update_models.sh
```

Update a specific provider:
```bash
./scripts/update_models.sh openai
./scripts/update_models.sh anthropic
./scripts/update_models.sh gemini
./scripts/update_models.sh openrouter
./scripts/update_models.sh ollama
./scripts/update_models.sh bedrock
```

### Sync from LiteLLM

Sync all 56 providers from LiteLLM (includes providers we haven't implemented):
```bash
./scripts/update_models.sh --litellm
```

This will update configurations for all providers including Azure, Mistral, Cohere, 
Together AI, Perplexity, and many more.

## Environment Variables

Some providers require API keys to fetch model information:

```bash
export ANTHROPIC_API_KEY="your-key"      # Optional - uses static data if not provided
export OPENAI_API_KEY="your-key"         # Optional - uses static data if not provided
export GEMINI_API_KEY="your-key"         # Optional - uses static data if not provided
export GOOGLE_API_KEY="your-key"         # Alternative to GEMINI_API_KEY
export OPENROUTER_API_KEY="your-key"     # Not required - public API
```

## How It Works

### Provider API Updates
- Fetches latest model information directly from provider APIs
- Falls back to static data if API is unavailable
- Preserves manual additions in YAML files
- Updates pricing, context windows, and capabilities

### LiteLLM Sync
- Reads from LiteLLM's comprehensive model database
- Converts pricing to per-million tokens
- Maps capabilities between LiteLLM and ExLLM formats
- Creates/updates YAML files for ALL providers (not just implemented ones)

## YAML Structure

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
    deprecation_date: "2025-10-01"  # If applicable
```

## Troubleshooting

- **No models found**: Check API keys and network connection
- **Ollama errors**: Ensure Ollama is running locally (`ollama serve`)
- **Permission denied**: Run `chmod +x scripts/*.sh scripts/*.py`
- **Missing dependencies**: Install with `pip3 install requests pyyaml`
- **LiteLLM sync fails**: Ensure `../litellm` directory exists with `model_prices_and_context_window.json`