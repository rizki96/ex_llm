#!/usr/bin/env python3
"""
Extract ALL provider model configurations from LiteLLM to ExLLM YAML format.
This includes providers we haven't implemented yet, for future reference.
"""

import json
import yaml
import os
from pathlib import Path
from collections import defaultdict

# Map LiteLLM capability names to ExLLM capability names
CAPABILITY_MAP = {
    "supports_function_calling": "function_calling",
    "supports_vision": "vision",
    "supports_audio_input": "audio_input",
    "supports_audio_output": "audio_output",
    "supports_prompt_caching": "prompt_caching",
    "supports_response_schema": "structured_output",
    "supports_system_messages": "system_messages",
    "supports_reasoning": "reasoning",
    "supports_web_search": "web_search",
    "supports_pdf_input": "pdf_input",
    "supports_parallel_function_calling": "parallel_function_calling",
    "supports_native_streaming": "streaming",
    "supports_tool_choice": "tool_choice"
}

def load_litellm_data():
    """Load LiteLLM's model configuration"""
    litellm_path = Path("../litellm/model_prices_and_context_window.json")
    if not litellm_path.exists():
        print(f"Error: {litellm_path} not found")
        return {}
    
    with open(litellm_path, 'r') as f:
        return json.load(f)

def convert_pricing(litellm_model):
    """Convert LiteLLM pricing to ExLLM format (per million tokens)"""
    input_cost = litellm_model.get("input_cost_per_token", 0) * 1_000_000
    output_cost = litellm_model.get("output_cost_per_token", 0) * 1_000_000
    
    # Only include pricing if non-zero
    if input_cost > 0 or output_cost > 0:
        pricing = {
            "input": round(input_cost, 4),
            "output": round(output_cost, 4)
        }
        
        # Add reasoning cost if present
        reasoning_cost = litellm_model.get("output_cost_per_reasoning_token", 0) * 1_000_000
        if reasoning_cost > 0:
            pricing["reasoning"] = round(reasoning_cost, 4)
            
        return pricing
    return None

def convert_capabilities(litellm_model):
    """Convert LiteLLM capabilities to ExLLM format"""
    capabilities = []
    
    # Always add streaming for chat models
    if litellm_model.get("mode") == "chat":
        capabilities.append("streaming")
    
    for lit_cap, ex_cap in CAPABILITY_MAP.items():
        if litellm_model.get(lit_cap, False):
            if ex_cap not in capabilities:
                capabilities.append(ex_cap)
    
    return capabilities if capabilities else None

def process_all_providers(litellm_data):
    """Process models and group by ALL providers"""
    providers = defaultdict(dict)
    provider_stats = defaultdict(int)
    
    for model_id, model_data in litellm_data.items():
        if model_id == "sample_spec":
            continue
            
        provider = model_data.get("litellm_provider")
        if not provider:
            continue
            
        provider_stats[provider] += 1
        
        # Convert model data
        model_config = {}
        
        # Context window
        if "max_input_tokens" in model_data:
            model_config["context_window"] = model_data["max_input_tokens"]
        elif "max_tokens" in model_data:
            model_config["context_window"] = model_data["max_tokens"]
        
        # Max output tokens
        if "max_output_tokens" in model_data and model_data["max_output_tokens"] > 0:
            model_config["max_output_tokens"] = model_data["max_output_tokens"]
        
        # Pricing
        pricing = convert_pricing(model_data)
        if pricing:
            model_config["pricing"] = pricing
        
        # Capabilities
        capabilities = convert_capabilities(model_data)
        if capabilities:
            model_config["capabilities"] = capabilities
        
        # Deprecation date
        if "deprecation_date" in model_data:
            model_config["deprecation_date"] = model_data["deprecation_date"]
        
        # Mode (chat, embedding, etc.)
        if "mode" in model_data and model_data["mode"] != "chat":
            model_config["mode"] = model_data["mode"]
        
        # Add any additional metadata
        if "supported_endpoints" in model_data:
            model_config["supported_endpoints"] = model_data["supported_endpoints"]
        if "supported_modalities" in model_data:
            model_config["supported_modalities"] = model_data["supported_modalities"]
        if "supported_output_modalities" in model_data:
            model_config["supported_output_modalities"] = model_data["supported_output_modalities"]
            
        providers[provider][model_id] = model_config
    
    return providers, provider_stats

def write_provider_config(provider, models, stats):
    """Write configuration for a provider"""
    # Create config directory if it doesn't exist
    config_dir = Path("config/models")
    config_dir.mkdir(parents=True, exist_ok=True)
    
    # Prepare provider config
    config = {
        "provider": provider,
        "models": models
    }
    
    # Add default model if we can determine one
    if models:
        # Try to find a sensible default
        model_names = list(models.keys())
        default_candidates = [
            m for m in model_names 
            if "latest" in m or "default" in m or not any(x in m for x in ["deprecated", "old", "legacy"])
        ]
        if default_candidates:
            config["default_model"] = default_candidates[0]
        else:
            config["default_model"] = model_names[0]
    
    # Write YAML file
    config_path = config_dir / f"{provider}.yml"
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    
    print(f"Created {provider}.yml with {len(models)} models")

def main():
    print("Extracting ALL provider model data from LiteLLM...")
    litellm_data = load_litellm_data()
    
    if not litellm_data:
        return
    
    print(f"Found {len(litellm_data)} total models")
    
    # Process all providers
    providers, provider_stats = process_all_providers(litellm_data)
    
    # Sort providers by number of models
    sorted_providers = sorted(provider_stats.items(), key=lambda x: x[1], reverse=True)
    
    print(f"\nFound {len(providers)} unique providers:")
    print("-" * 50)
    
    for provider, count in sorted_providers:
        print(f"{provider:30} {count:4} models")
    
    print("\nCreating YAML configuration files...")
    print("-" * 50)
    
    # Write configuration for each provider
    for provider, models in providers.items():
        if models:
            write_provider_config(provider, models, provider_stats[provider])
    
    print("\n✅ Extraction complete!")
    
    # Show which providers we already support
    existing_adapters = ["openai", "anthropic", "groq", "gemini", "bedrock", "openrouter", "ollama"]
    new_providers = [p for p in providers.keys() if p not in existing_adapters]
    
    print(f"\nExisting adapters: {len([p for p in existing_adapters if p in providers])}")
    print(f"New providers available: {len(new_providers)}")
    
    if new_providers:
        print("\nTop 10 new providers by model count:")
        new_sorted = [(p, provider_stats[p]) for p in new_providers]
        new_sorted.sort(key=lambda x: x[1], reverse=True)
        for provider, count in new_sorted[:10]:
            print(f"  - {provider:25} ({count} models)")

if __name__ == "__main__":
    main()