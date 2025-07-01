#!/bin/bash

# Clean test for all providers
source ~/.env

echo "ExLLM Provider Test Results"
echo "==========================="
echo ""

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
    "lmstudio"
    "mock"
)

for provider in "${providers[@]}"; do
    echo -n "$provider: "
    
    # Run test and check for success
    output=$(cd examples && PROVIDER=$provider timeout 15 elixir example_app.exs basic-chat "Hello! What's 2+2?" 2>&1)
    
    if echo "$output" | grep -q "Response:"; then
        echo "✅ WORKING"
    elif echo "$output" | grep -q "Error:"; then
        error=$(echo "$output" | grep "Error:" | head -1)
        echo "❌ ERROR - $error"
    elif [ $? -eq 124 ]; then
        echo "⏱️ TIMEOUT"
    else
        # Check for other failures
        if echo "$output" | grep -q "connection refused"; then
            echo "❌ CONNECTION REFUSED (server not running)"
        elif echo "$output" | grep -q "unexpected_pipeline_state"; then
            echo "❌ PIPELINE STATE ERROR"
        else
            echo "❌ FAILED"
        fi
    fi
done

echo ""
echo "==========================="