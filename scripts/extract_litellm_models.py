#!/usr/bin/env python3
"""
Extract model data from LiteLLM model_prices_and_context_window.json
and format it for ExLLM YAML configuration.
"""

import json
import yaml
from pathlib import Path

# Read the LiteLLM model configuration
litellm_path = Path("../../litellm/model_prices_and_context_window.json")
with open(litellm_path, 'r') as f:
    model_data = json.load(f)

# Provider mappings from LiteLLM to ExLLM
provider_mapping = {
    "anthropic": "anthropic",
    "openai": "openai",
    "groq": "groq",
    "gemini": "gemini",
    "bedrock": "bedrock",
    "openrouter": "openrouter",
    "ollama": "ollama"
}

# Extract models by provider
models_by_provider = {}

for model_id, info in model_data.items():
    if model_id == "sample_spec":
        continue
        
    litellm_provider = info.get("litellm_provider", "")
    
    # Map to our provider names
    if litellm_provider in provider_mapping:
        provider = provider_mapping[litellm_provider]
        
        if provider not in models_by_provider:
            models_by_provider[provider] = {}
        
        # Extract key information
        model_info = {
            "context_window": info.get("max_input_tokens", info.get("max_tokens", 4096)),
            "max_output_tokens": info.get("max_output_tokens", info.get("max_tokens", 4096)),
        }
        
        # Add pricing if available (convert from per-token to per-million-tokens)
        if "input_cost_per_token" in info and info["input_cost_per_token"] > 0:
            model_info["cost_per_million_input_tokens"] = info["input_cost_per_token"] * 1_000_000
        
        if "output_cost_per_token" in info and info["output_cost_per_token"] > 0:
            model_info["cost_per_million_output_tokens"] = info["output_cost_per_token"] * 1_000_000
            
        # Add capabilities
        capabilities = []
        if info.get("supports_function_calling"):
            capabilities.append("function_calling")
        if info.get("supports_vision"):
            capabilities.append("vision")
        if info.get("supports_response_schema") or info.get("supports_json_mode"):
            capabilities.append("json_mode")
        if info.get("supports_streaming", True) and info.get("mode") == "chat":
            capabilities.append("streaming")
        if info.get("supports_prompt_caching"):
            capabilities.append("prompt_caching")
        if info.get("supports_reasoning"):
            capabilities.append("reasoning")
        if info.get("supports_web_search"):
            capabilities.append("web_search")
        if info.get("supports_computer_use"):
            capabilities.append("computer_use")
        if info.get("supports_audio_input"):
            capabilities.append("audio_input")
        if info.get("supports_audio_output"):
            capabilities.append("audio_output")
            
        if capabilities:
            model_info["capabilities"] = capabilities
            
        # Clean up model ID for our format
        clean_model_id = model_id
        if "/" in model_id and provider in ["anthropic", "openai", "gemini"]:
            # Remove provider prefix for some providers
            clean_model_id = model_id.split("/", 1)[1]
        
        models_by_provider[provider][clean_model_id] = model_info

# Write out YAML files for each provider
output_dir = Path("../config/models")
output_dir.mkdir(parents=True, exist_ok=True)

# Process each provider
for provider, models in models_by_provider.items():
    if not models:
        continue
        
    # Read existing config if it exists
    config_file = output_dir / f"{provider}.yml"
    existing_config = {}
    if config_file.exists():
        with open(config_file, 'r') as f:
            existing_config = yaml.safe_load(f) or {}
    
    # Merge with new data, preserving existing custom fields
    if "models" not in existing_config:
        existing_config["models"] = {}
    
    # Update models with new data
    for model_id, model_info in models.items():
        if model_id in existing_config["models"]:
            # Preserve existing custom fields, update with new data
            existing_config["models"][model_id].update(model_info)
        else:
            existing_config["models"][model_id] = model_info
    
    # Write updated config
    with open(config_file, 'w') as f:
        yaml.dump(existing_config, f, default_flow_style=False, sort_keys=False)
    
    print(f"Updated {config_file} with {len(models)} models")

# Print summary
print("\nSummary:")
for provider, models in models_by_provider.items():
    print(f"  {provider}: {len(models)} models")
    # Show a few example models
    example_models = list(models.keys())[:3]
    for model in example_models:
        print(f"    - {model}")
    if len(models) > 3:
        print(f"    ... and {len(models) - 3} more")