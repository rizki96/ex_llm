#!/bin/bash

# Update model configurations
# Usage: 
#   ./scripts/update_models.sh              # Update from provider APIs
#   ./scripts/update_models.sh [provider]   # Update specific provider from API
#   ./scripts/update_models.sh --litellm    # Sync all from LiteLLM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python 3 is required"
    exit 1
fi

# Install required Python packages if needed
echo "📦 Checking Python dependencies..."
pip3 install -q requests pyyaml 2>/dev/null || true

cd "$PROJECT_ROOT"

if [ "$1" == "--litellm" ]; then
    echo "🔄 Syncing model configurations from LiteLLM..."
    python3 "$SCRIPT_DIR/sync_from_litellm.py"
    echo ""
    echo "✅ Synced all provider configurations from LiteLLM!"
    echo "   This includes providers we haven't implemented yet."
elif [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Update model configurations"
    echo ""
    echo "Usage:"
    echo "  $0              # Update all providers from their APIs"
    echo "  $0 [provider]   # Update specific provider from API"
    echo "  $0 --litellm    # Sync all providers from LiteLLM"
    echo ""
    echo "Available providers for API updates:"
    echo "  - openai"
    echo "  - anthropic" 
    echo "  - gemini"
    echo "  - openrouter"
    echo "  - ollama (requires local Ollama server)"
    echo "  - bedrock"
    echo ""
    echo "Environment variables:"
    echo "  OPENAI_API_KEY     - For OpenAI API (optional)"
    echo "  ANTHROPIC_API_KEY  - For Anthropic API (optional)"
    echo "  GEMINI_API_KEY     - For Gemini API (optional)"
    echo "  OPENROUTER_API_KEY - For OpenRouter API (not required)"
else
    echo "🔄 Updating model configurations from provider APIs..."
    
    if [ $# -eq 0 ]; then
        python3 "$SCRIPT_DIR/fetch_provider_models.py"
    else
        python3 "$SCRIPT_DIR/fetch_provider_models.py" "$1"
    fi
    
    echo ""
    echo "✅ Model configurations updated!"
    echo ""
    echo "You can manually edit the YAML files in config/models/ if needed."
    echo "The updater preserves any manual additions you've made."
fi