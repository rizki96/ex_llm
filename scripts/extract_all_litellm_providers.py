#!/usr/bin/env python3
"""
Extract ALL provider information from LiteLLM's model database.
Creates YAML configuration files for every provider found, not just the ones we support.

Usage: python scripts/extract_all_litellm_providers.py
"""

import os
import sys
import json
import yaml
import requests
from datetime import datetime
from typing import Dict, Any, Optional, List, Set
from collections import defaultdict
import re

class LiteLLMExtractor:
    def __init__(self):
        self.config_dir = "config/models"
        os.makedirs(self.config_dir, exist_ok=True)
        self.litellm_url = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
        self.stats = defaultdict(int)
        
    def extract_all(self):
        """Extract all provider information from LiteLLM"""
        print("🔄 Fetching LiteLLM model database...")
        
        try:
            response = requests.get(self.litellm_url)
            response.raise_for_status()
            data = response.json()
            
            print(f"✅ Successfully fetched {len(data)} models from LiteLLM")
            
            # Extract providers
            providers = self._extract_providers(data)
            
            # Process each provider
            for provider in sorted(providers):
                self._process_provider(provider, data)
                
            # Show statistics
            self._show_statistics()
            
        except Exception as e:
            print(f"❌ Failed to fetch LiteLLM data: {e}")
            sys.exit(1)
    
    def _extract_providers(self, data: Dict[str, Any]) -> Set[str]:
        """Extract all unique providers from the model data"""
        providers = set()
        
        for model_id, model_data in data.items():
            # Extract provider from model ID
            # Most models follow pattern: provider/model-name
            if "/" in model_id:
                provider = model_id.split("/")[0]
            else:
                # Some models don't have a slash, try to infer provider
                if model_id.startswith("gpt"):
                    provider = "openai"
                elif model_id.startswith("claude"):
                    provider = "anthropic"
                elif model_id.startswith("gemini"):
                    provider = "google"
                elif model_id.startswith("llama"):
                    provider = "meta"
                elif model_id.startswith("mistral"):
                    provider = "mistral"
                elif model_id.startswith("command"):
                    provider = "cohere"
                elif model_id.startswith("embed"):
                    provider = "cohere"
                elif model_id.startswith("text-") or model_id.startswith("davinci"):
                    provider = "openai"
                else:
                    provider = "unknown"
            
            # Clean up provider names
            provider = provider.lower().strip()
            
            # Map common variations to canonical names
            provider_map = {
                "azure": "azure",
                "bedrock": "bedrock",
                "vertex_ai": "vertex_ai",
                "google": "google",
                "gemini": "google",
                "openrouter": "openrouter",
                "deepinfra": "deepinfra",
                "perplexity": "perplexity",
                "together": "together",
                "together_ai": "together",
                "fireworks": "fireworks",
                "fireworks_ai": "fireworks",
                "groq": "groq",
                "mistral": "mistral",
                "mistralai": "mistral",
                "cohere": "cohere",
                "cohere_chat": "cohere",
                "replicate": "replicate",
                "huggingface": "huggingface",
                "ai21": "ai21",
                "nlp_cloud": "nlp_cloud",
                "aleph_alpha": "aleph_alpha",
                "baseten": "baseten",
                "vllm": "vllm",
                "sagemaker": "sagemaker",
                "petals": "petals",
                "palm": "google",
                "vertex": "vertex_ai",
                "voyage": "voyage",
                "databricks": "databricks",
                "predibase": "predibase",
                "nvidia_nim": "nvidia",
                "nvidia": "nvidia",
                "watsonx": "watsonx",
                "friendliai": "friendliai",
                "cloudflare": "cloudflare",
                "text-completion-openai": "openai",
                "text-completion-codestral": "mistral",
                "chat-completion-openai": "openai",
                "completion": "openai"
            }
            
            if provider in provider_map:
                provider = provider_map[provider]
            
            providers.add(provider)
            self.stats["total_models"] += 1
        
        return providers
    
    def _process_provider(self, provider: str, data: Dict[str, Any]):
        """Process all models for a specific provider"""
        print(f"\n📦 Processing {provider}...")
        
        models = {}
        provider_models = []
        
        # Find all models for this provider
        for model_id, model_data in data.items():
            if self._belongs_to_provider(model_id, provider):
                provider_models.append((model_id, model_data))
        
        if not provider_models:
            print(f"  ⚠️  No models found for {provider}")
            return
        
        # Process each model
        for model_id, model_data in provider_models:
            cleaned_id = self._clean_model_id(model_id, provider)
            model_info = self._extract_model_info(model_data)
            
            if model_info:
                models[cleaned_id] = model_info
                self.stats[f"{provider}_models"] += 1
        
        if models:
            # Create config
            config = {
                "provider": provider,
                "provider_type": self._get_provider_type(provider),
                "models": models,
                "model_count": len(models),
                "last_updated": datetime.now().isoformat(),
                "update_source": "litellm_model_database",
                "litellm_url": self.litellm_url
            }
            
            # Add default model if we can determine one
            default_model = self._get_default_model(provider, models)
            if default_model:
                config["default_model"] = default_model
            
            # Save config
            self._save_config(provider, config)
            print(f"  ✅ Extracted {len(models)} models for {provider}")
        else:
            print(f"  ⚠️  No valid models extracted for {provider}")
    
    def _belongs_to_provider(self, model_id: str, provider: str) -> bool:
        """Check if a model belongs to a specific provider"""
        # Direct match
        if model_id.startswith(f"{provider}/"):
            return True
        
        # Special cases
        if provider == "openai":
            if any(model_id.startswith(prefix) for prefix in ["gpt", "text-", "davinci", "babbage", "ada", "curie"]):
                return True
            if "turbo" in model_id and "/" not in model_id:
                return True
        elif provider == "anthropic":
            if model_id.startswith("claude") and "/" not in model_id:
                return True
        elif provider == "google":
            if any(model_id.startswith(prefix) for prefix in ["gemini", "palm", "bison"]):
                return True
        elif provider == "meta":
            if model_id.startswith("llama") and "/" not in model_id:
                return True
        elif provider == "mistral":
            if any(model_id.startswith(prefix) for prefix in ["mistral", "mixtral", "codestral"]):
                return True
        elif provider == "cohere":
            if any(model_id.startswith(prefix) for prefix in ["command", "embed"]):
                return True
        elif provider == "unknown":
            # Catch models that don't match any known pattern
            if "/" not in model_id and not any(model_id.startswith(p) for p in 
                ["gpt", "claude", "gemini", "llama", "mistral", "command", "embed", "text-", "davinci"]):
                return True
        
        return False
    
    def _clean_model_id(self, model_id: str, provider: str) -> str:
        """Clean model ID by removing provider prefix if present"""
        if model_id.startswith(f"{provider}/"):
            return model_id[len(provider) + 1:]
        return model_id
    
    def _extract_model_info(self, model_data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Extract model information from LiteLLM data"""
        info = {}
        
        # Context window
        if "max_tokens" in model_data:
            info["context_window"] = model_data["max_tokens"]
        elif "max_input_tokens" in model_data:
            info["context_window"] = model_data["max_input_tokens"]
        
        # Max output tokens
        if "max_output_tokens" in model_data:
            info["max_output_tokens"] = model_data["max_output_tokens"]
        elif "max_completion_tokens" in model_data:
            info["max_output_tokens"] = model_data["max_completion_tokens"]
        
        # Pricing
        pricing = {}
        if "input_cost_per_token" in model_data:
            # Convert from per-token to per-million-tokens
            pricing["input"] = float(model_data["input_cost_per_token"]) * 1_000_000
        if "output_cost_per_token" in model_data:
            pricing["output"] = float(model_data["output_cost_per_token"]) * 1_000_000
        
        if pricing:
            info["pricing"] = pricing
        
        # Mode (chat vs completion)
        if "mode" in model_data:
            info["mode"] = model_data["mode"]
        
        # Supports functions
        if "supports_function_calling" in model_data:
            info["supports_function_calling"] = model_data["supports_function_calling"]
        
        # Supports vision
        if "supports_vision" in model_data:
            info["supports_vision"] = model_data["supports_vision"]
        
        # Supports streaming (most models do)
        if "supports_streaming" in model_data:
            info["supports_streaming"] = model_data["supports_streaming"]
        
        # Deprecation info
        if "deprecated" in model_data:
            info["deprecated"] = model_data["deprecated"]
        if "deprecation_date" in model_data:
            info["deprecation_date"] = model_data["deprecation_date"]
        
        # Additional metadata
        if "description" in model_data:
            info["description"] = model_data["description"]
        if "created_at" in model_data:
            info["created_at"] = model_data["created_at"]
        if "updated_at" in model_data:
            info["updated_at"] = model_data["updated_at"]
        
        # Extract capabilities array
        capabilities = []
        if info.get("supports_streaming", True):
            capabilities.append("streaming")
        if info.get("supports_function_calling"):
            capabilities.append("function_calling")
        if info.get("supports_vision"):
            capabilities.append("vision")
        
        if capabilities:
            info["capabilities"] = capabilities
        
        # Clean up - remove supports_* fields as we now have capabilities
        for key in ["supports_streaming", "supports_function_calling", "supports_vision"]:
            info.pop(key, None)
        
        return info if info else None
    
    def _get_provider_type(self, provider: str) -> str:
        """Determine the type of provider"""
        cloud_providers = ["openai", "anthropic", "google", "cohere", "ai21", "voyage", "mistral"]
        inference_providers = ["together", "deepinfra", "groq", "fireworks", "replicate", "baseten"]
        platform_providers = ["bedrock", "vertex_ai", "azure", "sagemaker", "databricks", "watsonx"]
        router_providers = ["openrouter", "cloudflare"]
        local_providers = ["ollama", "vllm", "petals", "huggingface"]
        
        if provider in cloud_providers:
            return "cloud"
        elif provider in inference_providers:
            return "inference"
        elif provider in platform_providers:
            return "platform"
        elif provider in router_providers:
            return "router"
        elif provider in local_providers:
            return "local"
        else:
            return "other"
    
    def _get_default_model(self, provider: str, models: Dict[str, Any]) -> Optional[str]:
        """Try to determine a sensible default model for the provider"""
        # Provider-specific defaults
        defaults = {
            "openai": ["gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo"],
            "anthropic": ["claude-3-5-sonnet-20241022", "claude-3-sonnet-20240229"],
            "google": ["gemini-2.0-flash", "gemini-1.5-flash", "gemini-pro"],
            "cohere": ["command-r", "command"],
            "mistral": ["mistral-large", "mistral-medium", "mistral-small"],
            "meta": ["llama-3.2-70b", "llama-3.1-70b", "llama-3-70b"],
            "groq": ["llama-3.2-70b-chat", "mixtral-8x7b-instruct"],
            "together": ["meta-llama/Llama-3-70b-chat-hf"],
            "deepinfra": ["meta-llama/Llama-3-70b-chat-hf"]
        }
        
        if provider in defaults:
            for default in defaults[provider]:
                if default in models:
                    return default
        
        # If no specific default, try to find a reasonable one
        # Prefer newer, mid-sized models
        model_list = list(models.keys())
        
        # Look for keywords indicating good defaults
        for keyword in ["mini", "flash", "small", "base"]:
            for model in model_list:
                if keyword in model.lower() and not models[model].get("deprecated"):
                    return model
        
        # Return first non-deprecated model
        for model in model_list:
            if not models[model].get("deprecated"):
                return model
        
        # If all else fails, return first model
        return model_list[0] if model_list else None
    
    def _save_config(self, provider: str, config: Dict[str, Any]):
        """Save configuration to YAML file"""
        # Clean provider name for filename
        filename = re.sub(r'[^a-z0-9_]', '_', provider.lower())
        filepath = os.path.join(self.config_dir, f"{filename}.yml")
        
        # Sort models by name for consistency
        if "models" in config:
            sorted_models = dict(sorted(config["models"].items()))
            config["models"] = sorted_models
        
        # Write to file
        with open(filepath, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False, width=120)
        
        self.stats["providers_processed"] += 1
    
    def _show_statistics(self):
        """Show extraction statistics"""
        print("\n" + "="*60)
        print("📊 EXTRACTION STATISTICS")
        print("="*60)
        
        print(f"Total models found: {self.stats['total_models']}")
        print(f"Total providers processed: {self.stats['providers_processed']}")
        print()
        
        # Show per-provider stats
        provider_stats = [(k.replace("_models", ""), v) for k, v in self.stats.items() 
                         if k.endswith("_models")]
        provider_stats.sort(key=lambda x: x[1], reverse=True)
        
        if provider_stats:
            print("Models per provider:")
            for provider, count in provider_stats[:20]:  # Show top 20
                print(f"  {provider:<20} {count:>5} models")
            
            if len(provider_stats) > 20:
                print(f"  ... and {len(provider_stats) - 20} more providers")


def main():
    extractor = LiteLLMExtractor()
    extractor.extract_all()


if __name__ == "__main__":
    main()