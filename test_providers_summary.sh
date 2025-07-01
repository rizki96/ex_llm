#!/bin/bash

# Test summary for all providers
source ~/.env

echo "ExLLM Provider Test Summary"
echo "==========================="
echo ""

# Test each provider with basic chat
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

# Track results
working=()
failed=()

for provider in "${providers[@]}"; do
    echo -n "Testing $provider... "
    
    # Run the test and capture output
    output=$(PROVIDER=$provider timeout 15 elixir example_app.exs basic-chat "Hello! What's 2+2?" 2>&1)
    
    if echo "$output" | grep -q "Response:"; then
        echo "✅ WORKING"
        working+=($provider)
        
        # Extract key info
        response=$(echo "$output" | grep "Response:" | sed 's/Response: //')
        tokens=$(echo "$output" | grep "Total:" | head -1 | sed 's/.*Total: //')
        cost=$(echo "$output" | grep "Cost:" -A1 | tail -1 | sed 's/.*Total: //')
        
        echo "  Response: $response"
        echo "  Tokens: $tokens"
        echo "  Cost: $cost"
    elif echo "$output" | grep -q "Error:"; then
        echo "❌ ERROR"
        failed+=($provider)
        error=$(echo "$output" | grep "Error:" | head -1)
        echo "  $error"
    elif [ $? -eq 124 ]; then
        echo "⏱️ TIMEOUT"
        failed+=($provider)
    else
        echo "❌ FAILED"
        failed+=($provider)
        # Show first error line
        echo "$output" | grep -E "(error|Error|failed)" | head -1 | sed 's/^/  /'
    fi
    echo ""
done

# Summary
echo "==========================="
echo "Summary:"
echo "  Working: ${#working[@]} providers (${working[@]})"
echo "  Failed: ${#failed[@]} providers (${failed[@]})"
echo ""

# Test streaming with a working provider
if [ ${#working[@]} -gt 0 ]; then
    echo "Testing streaming with ${working[0]}..."
    echo "Tell me a very short joke" | PROVIDER=${working[0]} timeout 15 elixir example_app.exs 2>&1 | grep -A5 "Streaming Chat" | tail -5
fi