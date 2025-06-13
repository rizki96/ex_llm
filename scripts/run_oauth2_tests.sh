#!/bin/bash

# Run OAuth2 Tests Script
# 
# This script checks for valid OAuth2 tokens and runs OAuth2-specific tests
# Usage: ./scripts/run_oauth2_tests.sh

set -e

echo "🔐 OAuth2 Test Runner"
echo "===================="
echo ""

# Check if .gemini_tokens exists
if [ ! -f ".gemini_tokens" ]; then
    echo "❌ Error: No OAuth2 tokens found!"
    echo ""
    echo "Please run the OAuth2 setup first:"
    echo "  elixir scripts/setup_oauth2.exs"
    echo ""
    echo "See docs/gemini/OAUTH2_SETUP_GUIDE.md for detailed instructions."
    exit 1
fi

# Check if token is expired
if command -v jq &> /dev/null; then
    EXPIRES_AT=$(jq -r '.expires_at' .gemini_tokens)
    CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    if [[ "$EXPIRES_AT" < "$CURRENT_TIME" ]]; then
        echo "⚠️  Warning: OAuth2 token appears to be expired!"
        echo "   Token expired at: $EXPIRES_AT"
        echo "   Current time:     $CURRENT_TIME"
        echo ""
        echo "Attempting to refresh token..."
        elixir scripts/refresh_oauth2_token.exs
        
        if [ $? -ne 0 ]; then
            echo "❌ Failed to refresh token. Please run setup again:"
            echo "  elixir scripts/setup_oauth2.exs"
            exit 1
        fi
        echo ""
    else
        echo "✅ OAuth2 token is valid until: $EXPIRES_AT"
    fi
else
    echo "ℹ️  Note: Install 'jq' to enable automatic token expiration checking"
fi

echo ""

# Check for tuned model environment variable
if [ -n "$TEST_TUNED_MODEL" ]; then
    echo "✅ Using tuned model: $TEST_TUNED_MODEL"
else
    echo "ℹ️  Note: Set TEST_TUNED_MODEL to test Permissions API with a real tuned model"
fi

echo ""
echo "Running OAuth2 tests..."
echo "----------------------"

# Run tests with oauth2 tag
mix test --only oauth2 $@

echo ""
echo "✅ OAuth2 tests completed!"
echo ""
echo "📚 Additional Resources:"
echo "  - Test setup guide: docs/gemini/OAUTH2_TEST_SETUP.md"
echo "  - OAuth2 setup:     docs/gemini/OAUTH2_SETUP_GUIDE.md"
echo "  - Refresh tokens:   elixir scripts/refresh_oauth2_token.exs"