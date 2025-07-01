#!/bin/bash

# Test all providers with basic-chat demo
source ~/.env

echo "Testing ExLLM providers with basic-chat demo..."
echo "============================================="

# Array of providers to test
providers=(
    "openai"
    "anthropic" 
    "groq"
    "xai"
    "gemini"
    "openrouter"
    "mistral"
    "perplexity"
    "ollama"
    "mock"
)

# Test message
TEST_MESSAGE="Hello! What's 2+2?"

# Test each provider
for provider in "${providers[@]}"; do
    echo ""
    echo "Testing $provider..."
    echo "-------------------"
    
    # Run the test
    PROVIDER=$provider timeout 30 elixir example_app.exs basic-chat "$TEST_MESSAGE" 2>&1 | grep -E "(Response:|Error:|cost:|Token usage:|failed|timeout)"
    
    if [ $? -eq 124 ]; then
        echo "⚠️  TIMEOUT after 30 seconds"
    elif [ $? -eq 0 ]; then
        echo "✅ Success"
    else
        echo "❌ Failed"
    fi
done

echo ""
echo "============================================="
echo "Test complete!"