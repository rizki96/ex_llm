#!/bin/bash

# Update model configurations from provider APIs
# Usage: ./scripts/update_models.sh [provider]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔄 Updating model configurations..."
echo "Project root: $PROJECT_ROOT"

# Check if Python is available
if command -v python3 &> /dev/null; then
    echo "Using Python fetcher..."
    cd "$PROJECT_ROOT"
    
    # Install required Python packages if needed
    pip3 install -q requests pyyaml 2>/dev/null || true
    
    # Run the Python script
    if [ $# -eq 0 ]; then
        python3 "$SCRIPT_DIR/fetch_provider_models.py"
    else
        python3 "$SCRIPT_DIR/fetch_provider_models.py" "$1"
    fi
elif command -v elixir &> /dev/null; then
    echo "Using Elixir fetcher..."
    cd "$PROJECT_ROOT"
    
    # Run the Elixir script
    if [ $# -eq 0 ]; then
        elixir "$SCRIPT_DIR/update_model_configs.exs"
    else
        elixir "$SCRIPT_DIR/update_model_configs.exs" "$1"
    fi
else
    echo "❌ Error: Neither Python 3 nor Elixir is available"
    exit 1
fi

echo ""
echo "✅ Model configurations updated!"
echo ""
echo "You can manually edit the YAML files in config/models/ if needed."
echo "The updater preserves any manual additions you've made."