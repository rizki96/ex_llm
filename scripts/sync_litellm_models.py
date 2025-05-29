#!/usr/bin/env python3
"""
Sync model configuration from LiteLLM to ExLLM YAML format.
"""

import json
import yaml
import os
from pathlib import Path

# Map LiteLLM providers to ExLLM providers
PROVIDER_MAP = {
    "openai": "openai",
    "anthropic": "anthropic",
    "groq": "groq",
    "gemini": "gemini",
    "vertex_ai": "gemini",
    "bedrock": "bedrock",
    "openrouter": "openrouter",
    "ollama": "ollama",
    "ollama_chat": "ollama",
}

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
        return {
            "input": round(input_cost, 4),
            "output": round(output_cost, 4)
        }
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

def process_models_by_provider(litellm_data):
    """Group models by provider"""
    providers = {}
    
    for model_id, model_data in litellm_data.items():
        if model_id == "sample_spec":
            continue
            
        provider = model_data.get("litellm_provider")
        if not provider or provider not in PROVIDER_MAP:
            continue
            
        ex_provider = PROVIDER_MAP[provider]
        
        if ex_provider not in providers:
            providers[ex_provider] = {}
        
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
        
        # Add reasoning token cost if present
        if model_data.get("output_cost_per_reasoning_token", 0) > 0:
            if "pricing" not in model_config:
                model_config["pricing"] = {}
            model_config["pricing"]["reasoning"] = round(
                model_data["output_cost_per_reasoning_token"] * 1_000_000, 4
            )
        
        providers[ex_provider][model_id] = model_config
    
    return providers

def load_existing_config(provider):
    """Load existing ExLLM config for a provider"""
    config_path = Path(f"config/models/{provider}.yml")
    if config_path.exists():
        with open(config_path, 'r') as f:
            return yaml.safe_load(f) or {}
    return {"provider": provider}

def merge_configs(existing, new_models):
    """Merge new model data with existing config, preserving manual additions"""
    if "models" not in existing:
        existing["models"] = {}
    
    for model_id, new_data in new_models.items():
        if model_id in existing["models"]:
            # Merge with existing, new data takes precedence
            existing_model = existing["models"][model_id]
            for key, value in new_data.items():
                if key == "capabilities":
                    # Merge capabilities
                    existing_caps = set(existing_model.get("capabilities", []))
                    new_caps = set(value)
                    existing_model["capabilities"] = sorted(list(existing_caps | new_caps))
                else:
                    existing_model[key] = value
        else:
            # Add new model
            existing["models"][model_id] = new_data
    
    return existing

def update_provider_config(provider, models):
    """Update configuration for a provider"""
    existing = load_existing_config(provider)
    updated = merge_configs(existing, models)
    
    # Ensure required fields
    if "provider" not in updated:
        updated["provider"] = provider
    
    # Write back
    config_path = Path(f"config/models/{provider}.yml")
    config_path.parent.mkdir(exist_ok=True)
    
    with open(config_path, 'w') as f:
        yaml.dump(updated, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    
    print(f"Updated {provider}: {len(models)} models")

def main():
    print("Loading LiteLLM model data...")
    litellm_data = load_litellm_data()
    
    if not litellm_data:
        return
    
    print(f"Found {len(litellm_data)} models")
    
    # Process by provider
    providers = process_models_by_provider(litellm_data)
    
    # Update each provider
    for provider, models in providers.items():
        if models:
            update_provider_config(provider, models)
    
    print("\n✅ Sync complete!")
    
    # Show summary
    for provider, models in providers.items():
        print(f"\n{provider.upper()}:")
        model_list = list(models.keys())[:5]
        print(f"  Models: {', '.join(model_list)}")
        if len(models) > 5:
            print(f"  ... and {len(models) - 5} more")

if __name__ == "__main__":
    main()