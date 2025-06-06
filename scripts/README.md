# Model Configuration Scripts

This directory contains scripts to update model configurations and provider capabilities from various sources.

## Scripts

- **`update_models.sh`** - Main entry point for all updates
- **`fetch_provider_models.py`** - Fetches model info from provider APIs with enhanced capability detection
- **`fetch_provider_capabilities.py`** - Discovers and updates provider capabilities from APIs
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

### Fetch Provider Capabilities

Fetch and save capabilities to YAML files:
```bash
python scripts/fetch_provider_capabilities.py
```

Fetch specific provider capabilities:
```bash
python scripts/fetch_provider_capabilities.py openai
```

Update provider_capabilities.ex with discovered features:
```bash
python scripts/fetch_provider_capabilities.py --update-elixir
```

This will:
- Query provider APIs for available endpoints and features
- Detect capabilities from model IDs and API responses
- Save discovered capabilities to `config/models/{provider}_capabilities.yml`
- Optionally update the Elixir `provider_capabilities.ex` file

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
export ANTHROPIC_API_KEY="your-key"      # Required for Anthropic models list
export OPENAI_API_KEY="your-key"         # Required for OpenAI models list
export GEMINI_API_KEY="your-key"         # Required for Gemini models list
export GOOGLE_API_KEY="your-key"         # Alternative to GEMINI_API_KEY
export GROQ_API_KEY="your-key"          # Required for Groq models list
```

Note: If API keys are not provided, the script will skip those providers. 
Use `--litellm` mode for comprehensive model data without needing API keys.

## How It Works

### Provider API Updates
- Fetches latest model information directly from provider APIs when available
- Enhanced capability detection:
  - **OpenAI**: Detects vision (GPT-4V), structured outputs (GPT-4o), reasoning (o1 models)
  - **Anthropic**: Detects tool use, vision, prompt caching, computer use
  - **Gemini**: Detects long context, video understanding, audio input, code execution
- Preserves manual additions in YAML files
- Updates context windows and capabilities
- Note: For comprehensive model data including pricing, use `--litellm` mode

### Capability Discovery
The `fetch_provider_capabilities.py` script:
- Queries provider APIs for supported endpoints
- Detects features from model responses
- Maps common capabilities across providers
- Can update the main provider_capabilities.ex file

### LiteLLM Sync
- Reads from LiteLLM's comprehensive model database
- Converts pricing to per-million tokens
- Maps capabilities between LiteLLM and ExLLM formats
- Creates/updates YAML files for ALL providers (not just implemented ones)

## YAML Structure

### Model Configuration
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
      - prompt_caching
      - computer_use
    deprecation_date: "2025-10-01"  # If applicable
```

### Capability Discovery
```yaml
provider: openai
discovered_at: "2024-01-06T12:00:00"
endpoints:
  - chat
  - embeddings
  - images
  - audio
  - fine_tuning
  - assistants
features:
  - streaming
  - function_calling
  - vision
  - image_generation
  - speech_synthesis
  - speech_recognition
model_capabilities:
  gpt-4o:
    context_window: 128000
    capabilities:
      - vision
      - structured_outputs
      - function_calling
```

## API Fetch Status

See [API_FETCH_STATUS.md](API_FETCH_STATUS.md) for details on which providers support API-based model fetching.

## Troubleshooting

- **No models found**: Check API keys and network connection
- **Ollama errors**: Ensure Ollama is running locally (`ollama serve`)
- **Permission denied**: Run `chmod +x scripts/*.sh scripts/*.py`
- **Missing dependencies**: Install with `pip3 install requests pyyaml`
- **LiteLLM sync fails**: Ensure `../litellm` directory exists with `model_prices_and_context_window.json`
- **Capability update fails**: Review the generated `.new` file before replacing provider_capabilities.ex