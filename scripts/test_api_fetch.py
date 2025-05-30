#!/usr/bin/env python3
"""
Test script to verify API fetch functionality.
This simulates what happens when API keys are properly set.
"""

import os
import sys

# Add the project root to Python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Test that the fetch_provider_models module works
try:
    from scripts.fetch_provider_models import ModelFetcher
    print("✅ Successfully imported ModelFetcher")
    
    # Create fetcher instance
    fetcher = ModelFetcher()
    print("✅ Created ModelFetcher instance")
    
    # Check for API keys
    providers = {
        'openai': 'OPENAI_API_KEY',
        'anthropic': 'ANTHROPIC_API_KEY', 
        'gemini': 'GEMINI_API_KEY',
        'google': 'GOOGLE_API_KEY'
    }
    
    print("\n🔑 API Key Status:")
    for provider, key_name in providers.items():
        key_value = os.environ.get(key_name, '')
        if key_value:
            print(f"  {provider}: ✅ {key_name} is set (length: {len(key_value)})")
        else:
            print(f"  {provider}: ❌ {key_name} not found")
    
    print("\n📝 To test the API fetch:")
    print("1. Set your API keys as environment variables:")
    print("   export OPENAI_API_KEY='your-key-here'")
    print("   export ANTHROPIC_API_KEY='your-key-here'")
    print("   export GEMINI_API_KEY='your-key-here'")
    print("\n2. Run the fetch script:")
    print("   uv run python scripts/fetch_provider_models.py openai")
    print("   uv run python scripts/fetch_provider_models.py --all")
    print("\n3. Or use the shell wrapper:")
    print("   ./scripts/update_models.sh openai")
    print("   ./scripts/update_models.sh")
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()