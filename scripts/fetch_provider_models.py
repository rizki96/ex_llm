#!/usr/bin/env python3
"""
Fetch model information from provider APIs and documentation.
This Python script is more robust for web scraping than Elixir.

Usage: python scripts/fetch_provider_models.py [provider]
"""

import os
import sys
import json
import yaml
import requests
from datetime import datetime
from typing import Dict, Any, Optional
import time

class ModelFetcher:
    def __init__(self):
        self.config_dir = "config/models"
        os.makedirs(self.config_dir, exist_ok=True)
        
    def fetch_all(self):
        """Fetch models from all providers"""
        providers = ['anthropic', 'openai', 'gemini', 'openrouter', 'ollama', 'bedrock']
        
        for provider in providers:
            print(f"\n🔄 Fetching {provider} models...")
            try:
                self.fetch_provider(provider)
                print(f"✅ Successfully updated {provider}")
            except Exception as e:
                print(f"❌ Failed to update {provider}: {e}")
    
    def fetch_provider(self, provider: str):
        """Fetch models for a specific provider"""
        method = getattr(self, f'fetch_{provider}', None)
        if method:
            method()
        else:
            print(f"No fetcher implemented for {provider}")
    
    def fetch_anthropic(self):
        """Fetch Anthropic models"""
        # Anthropic doesn't have a public models API, so we use known models
        models = {
            "claude-3-5-sonnet-20241022": {
                "context_window": 200000,
                "max_output_tokens": 8192,
                "pricing": {"input": 3.00, "output": 15.00},
                "capabilities": ["streaming", "function_calling", "vision"],
                "release_date": "2024-10-22"
            },
            "claude-3-5-haiku-20241022": {
                "context_window": 200000,
                "max_output_tokens": 8192,
                "pricing": {"input": 0.80, "output": 4.00},
                "capabilities": ["streaming", "function_calling", "vision"],
                "release_date": "2024-10-22"
            },
            "claude-3-opus-20240229": {
                "context_window": 200000,
                "max_output_tokens": 4096,
                "pricing": {"input": 15.00, "output": 75.00},
                "capabilities": ["streaming", "function_calling", "vision"],
                "release_date": "2024-02-29"
            },
            "claude-3-sonnet-20240229": {
                "context_window": 200000,
                "max_output_tokens": 4096,
                "pricing": {"input": 3.00, "output": 15.00},
                "capabilities": ["streaming", "function_calling", "vision"],
                "release_date": "2024-02-29"
            },
            "claude-3-haiku-20240307": {
                "context_window": 200000,
                "max_output_tokens": 4096,
                "pricing": {"input": 0.25, "output": 1.25},
                "capabilities": ["streaming", "function_calling", "vision"],
                "release_date": "2024-03-07"
            },
            "claude-sonnet-4-20250514": {
                "context_window": 200000,
                "max_output_tokens": 8192,
                "pricing": {"input": 3.00, "output": 15.00},
                "capabilities": ["streaming", "function_calling", "vision"],
                "release_date": "2025-05-14"
            }
        }
        
        config = {
            "provider": "anthropic",
            "default_model": "claude-sonnet-4-20250514",
            "models": models
        }
        
        self._save_config("anthropic", config)
    
    def fetch_openai(self):
        """Fetch OpenAI models via API"""
        api_key = os.environ.get("OPENAI_API_KEY")
        
        if api_key:
            headers = {"Authorization": f"Bearer {api_key}"}
            try:
                response = requests.get("https://api.openai.com/v1/models", headers=headers)
                if response.status_code == 200:
                    data = response.json()
                    models = self._parse_openai_models(data["data"])
                else:
                    models = self._get_static_openai_models()
            except Exception:
                models = self._get_static_openai_models()
        else:
            models = self._get_static_openai_models()
        
        config = {
            "provider": "openai",
            "default_model": "gpt-4o-mini",
            "models": models
        }
        
        self._save_config("openai", config)
    
    def _parse_openai_models(self, api_models):
        """Parse OpenAI API response"""
        known_models = {
            "gpt-4o": {
                "context_window": 128000,
                "max_output_tokens": 16384,
                "pricing": {"input": 2.50, "output": 10.00},
                "capabilities": ["streaming", "function_calling", "vision"]
            },
            "gpt-4o-mini": {
                "context_window": 128000,
                "max_output_tokens": 16384,
                "pricing": {"input": 0.15, "output": 0.60},
                "capabilities": ["streaming", "function_calling", "vision"]
            },
            "gpt-4-turbo": {
                "context_window": 128000,
                "max_output_tokens": 4096,
                "pricing": {"input": 10.00, "output": 30.00},
                "capabilities": ["streaming", "function_calling", "vision"]
            },
            "gpt-4": {
                "context_window": 8192,
                "max_output_tokens": 4096,
                "pricing": {"input": 30.00, "output": 60.00},
                "capabilities": ["streaming", "function_calling"]
            },
            "gpt-3.5-turbo": {
                "context_window": 16385,
                "max_output_tokens": 4096,
                "pricing": {"input": 0.50, "output": 1.50},
                "capabilities": ["streaming", "function_calling"]
            },
            "gpt-3.5-turbo-16k": {
                "context_window": 16385,
                "max_output_tokens": 4096,
                "pricing": {"input": 3.00, "output": 4.00},
                "capabilities": ["streaming", "function_calling"]
            }
        }
        
        # Add any new models from API that we don't know about
        for model in api_models:
            model_id = model["id"]
            if model_id not in known_models and "gpt" in model_id:
                if "instruct" not in model_id and "edit" not in model_id:
                    known_models[model_id] = {
                        "context_window": self._guess_context_window(model_id),
                        "capabilities": ["streaming", "function_calling"]
                    }
        
        return known_models
    
    def _get_static_openai_models(self):
        """Return static OpenAI model data"""
        return {
            "gpt-4o": {
                "context_window": 128000,
                "max_output_tokens": 16384,
                "pricing": {"input": 2.50, "output": 10.00},
                "capabilities": ["streaming", "function_calling", "vision"]
            },
            "gpt-4o-mini": {
                "context_window": 128000,
                "max_output_tokens": 16384,
                "pricing": {"input": 0.15, "output": 0.60},
                "capabilities": ["streaming", "function_calling", "vision"]
            },
            "gpt-4-turbo": {
                "context_window": 128000,
                "max_output_tokens": 4096,
                "pricing": {"input": 10.00, "output": 30.00},
                "capabilities": ["streaming", "function_calling", "vision"]
            },
            "gpt-3.5-turbo": {
                "context_window": 16385,
                "max_output_tokens": 4096,
                "pricing": {"input": 0.50, "output": 1.50},
                "capabilities": ["streaming", "function_calling"]
            }
        }
    
    def _guess_context_window(self, model_id: str) -> int:
        """Guess context window based on model name"""
        if "32k" in model_id:
            return 32768
        elif "16k" in model_id:
            return 16385
        elif "turbo" in model_id:
            return 128000
        elif "gpt-4" in model_id:
            return 8192
        else:
            return 4096
    
    def fetch_gemini(self):
        """Fetch Gemini models"""
        api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
        
        if api_key:
            try:
                url = f"https://generativelanguage.googleapis.com/v1/models?key={api_key}"
                response = requests.get(url)
                if response.status_code == 200:
                    data = response.json()
                    models = self._parse_gemini_models(data.get("models", []))
                else:
                    models = self._get_static_gemini_models()
            except Exception:
                models = self._get_static_gemini_models()
        else:
            models = self._get_static_gemini_models()
        
        config = {
            "provider": "gemini",
            "default_model": "gemini-2.0-flash",
            "models": models
        }
        
        self._save_config("gemini", config)
    
    def _parse_gemini_models(self, api_models):
        """Parse Gemini API response"""
        models = {}
        
        for model in api_models:
            if "gemini" in model.get("name", ""):
                model_id = model["name"].replace("models/", "")
                models[model_id] = {
                    "context_window": model.get("inputTokenLimit", 32768),
                    "max_output_tokens": model.get("outputTokenLimit", 8192),
                    "capabilities": self._get_gemini_capabilities(model)
                }
        
        # Add pricing for known models
        pricing_map = {
            "gemini-2.0-flash": {"input": 0.10, "output": 0.40},
            "gemini-1.5-pro": {"input": 1.25, "output": 5.00},
            "gemini-1.5-flash": {"input": 0.075, "output": 0.30}
        }
        
        for model_id, pricing in pricing_map.items():
            if model_id in models:
                models[model_id]["pricing"] = pricing
        
        return models
    
    def _get_gemini_capabilities(self, model):
        """Extract capabilities from Gemini model"""
        caps = ["streaming"]
        
        if model.get("supportedGenerationMethods"):
            if "generateContent" in model["supportedGenerationMethods"]:
                caps.append("function_calling")
        
        if "vision" in model.get("name", "") or "pro" in model.get("name", ""):
            caps.append("vision")
            
        return caps
    
    def _get_static_gemini_models(self):
        """Return static Gemini model data"""
        return {
            "gemini-2.0-flash": {
                "context_window": 1048576,
                "max_output_tokens": 8192,
                "pricing": {"input": 0.10, "output": 0.40},
                "capabilities": ["streaming", "function_calling", "vision"]
            },
            "gemini-1.5-pro": {
                "context_window": 2097152,
                "max_output_tokens": 8192,
                "pricing": {"input": 1.25, "output": 5.00},
                "capabilities": ["streaming", "function_calling", "vision"]
            },
            "gemini-1.5-flash": {
                "context_window": 1048576,
                "max_output_tokens": 8192,
                "pricing": {"input": 0.075, "output": 0.30},
                "capabilities": ["streaming", "function_calling", "vision"]
            }
        }
    
    def fetch_openrouter(self):
        """Fetch OpenRouter models via their public API"""
        try:
            response = requests.get("https://openrouter.ai/api/v1/models")
            if response.status_code == 200:
                data = response.json()
                models = self._parse_openrouter_models(data.get("data", []))
            else:
                models = {}
        except Exception as e:
            print(f"Error fetching OpenRouter models: {e}")
            models = {}
        
        config = {
            "provider": "openrouter",
            "default_model": "openai/gpt-4o-mini",
            "models": models
        }
        
        self._save_config("openrouter", config)
    
    def _parse_openrouter_models(self, api_models):
        """Parse OpenRouter API response"""
        models = {}
        
        # Get top 30 models by popularity/quality
        priority_models = [
            "openai/gpt-4o", "openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet",
            "google/gemini-pro", "meta-llama/llama-3-70b", "mistralai/mistral-large"
        ]
        
        # First add priority models
        for model in api_models:
            model_id = model.get("id", "")
            if any(pm in model_id for pm in priority_models):
                models[model_id] = self._parse_openrouter_model(model)
        
        # Then add other interesting models up to 30 total
        for model in api_models:
            if len(models) >= 30:
                break
            model_id = model.get("id", "")
            if model_id not in models:
                models[model_id] = self._parse_openrouter_model(model)
        
        return models
    
    def _parse_openrouter_model(self, model):
        """Parse individual OpenRouter model"""
        return {
            "context_window": model.get("context_length", 4096),
            "pricing": {
                "input": (model.get("pricing", {}).get("prompt", 0) or 0) * 1_000_000,
                "output": (model.get("pricing", {}).get("completion", 0) or 0) * 1_000_000
            },
            "capabilities": ["streaming", "function_calling"]
        }
    
    def fetch_ollama(self):
        """Fetch locally installed Ollama models"""
        try:
            response = requests.get("http://localhost:11434/api/tags")
            if response.status_code == 200:
                data = response.json()
                models = self._parse_ollama_models(data.get("models", []))
            else:
                models = self._get_static_ollama_models()
        except Exception:
            models = self._get_static_ollama_models()
        
        config = {
            "provider": "ollama",
            "default_model": "llama3.2",
            "models": models
        }
        
        self._save_config("ollama", config)
    
    def _parse_ollama_models(self, api_models):
        """Parse Ollama API response"""
        models = {}
        
        for model in api_models:
            model_name = model.get("name", "")
            if model_name:
                models[model_name] = {
                    "context_window": self._get_ollama_context_window(model_name),
                    "pricing": {"input": 0.0, "output": 0.0},
                    "capabilities": ["streaming"]
                }
        
        return models
    
    def _get_ollama_context_window(self, model_name: str) -> int:
        """Get context window for Ollama model"""
        if "llama3" in model_name:
            return 8192
        elif "llama2" in model_name:
            return 4096
        elif "mixtral" in model_name:
            return 32768
        elif "mistral" in model_name:
            return 8192
        elif "phi" in model_name:
            return 2048
        else:
            return 4096
    
    def _get_static_ollama_models(self):
        """Return common Ollama models"""
        return {
            "llama3.2": {
                "context_window": 128000,
                "pricing": {"input": 0.0, "output": 0.0},
                "capabilities": ["streaming"]
            },
            "llama3.1": {
                "context_window": 128000,
                "pricing": {"input": 0.0, "output": 0.0},
                "capabilities": ["streaming"]
            },
            "llama2": {
                "context_window": 4096,
                "pricing": {"input": 0.0, "output": 0.0},
                "capabilities": ["streaming"]
            },
            "mistral": {
                "context_window": 8192,
                "pricing": {"input": 0.0, "output": 0.0},
                "capabilities": ["streaming"]
            },
            "mixtral": {
                "context_window": 32768,
                "pricing": {"input": 0.0, "output": 0.0},
                "capabilities": ["streaming"]
            }
        }
    
    def fetch_bedrock(self):
        """Fetch AWS Bedrock models (static data)"""
        # Bedrock doesn't have a simple API, so we use static data
        models = {
            # Amazon Nova
            "nova-micro": {
                "context_window": 128000,
                "pricing": {"input": 0.035, "output": 0.14},
                "capabilities": ["streaming"]
            },
            "nova-lite": {
                "context_window": 300000,
                "pricing": {"input": 0.06, "output": 0.24},
                "capabilities": ["streaming", "vision"]
            },
            "nova-pro": {
                "context_window": 300000,
                "pricing": {"input": 0.80, "output": 3.20},
                "capabilities": ["streaming", "vision"]
            },
            # Anthropic
            "claude-3-5-sonnet-20241022": {
                "context_window": 200000,
                "pricing": {"input": 3.00, "output": 15.00},
                "capabilities": ["streaming", "function_calling", "vision"]
            },
            "claude-3-5-haiku-20241022": {
                "context_window": 200000,
                "pricing": {"input": 0.80, "output": 4.00},
                "capabilities": ["streaming", "function_calling", "vision"]
            },
            # Meta Llama
            "llama3.2-90b-instruct": {
                "context_window": 128000,
                "pricing": {"input": 0.88, "output": 0.88},
                "capabilities": ["streaming"]
            },
            "llama3.2-11b-instruct": {
                "context_window": 128000,
                "pricing": {"input": 0.32, "output": 0.32},
                "capabilities": ["streaming", "vision"]
            },
            # Mistral
            "pixtral-large-2025-02": {
                "context_window": 128000,
                "pricing": {"input": 2.00, "output": 6.00},
                "capabilities": ["streaming", "vision"]
            }
        }
        
        config = {
            "provider": "bedrock",
            "default_model": "nova-lite",
            "models": models
        }
        
        self._save_config("bedrock", config)
    
    def _save_config(self, provider: str, config: Dict[str, Any]):
        """Save configuration to YAML file"""
        filepath = os.path.join(self.config_dir, f"{provider}.yml")
        
        # Load existing config if it exists
        if os.path.exists(filepath):
            with open(filepath, 'r') as f:
                existing = yaml.safe_load(f) or {}
            
            # Merge with existing, preserving manual additions
            if "models" in existing and "models" in config:
                for model_id, model_data in existing["models"].items():
                    if model_id in config["models"]:
                        # Preserve existing data, update with new
                        config["models"][model_id] = {**model_data, **config["models"][model_id]}
                    else:
                        # Keep models that were manually added
                        config["models"][model_id] = model_data
        
        # Add metadata
        config["last_updated"] = datetime.now().isoformat()
        config["update_source"] = "fetch_provider_models.py"
        
        # Write to file
        with open(filepath, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)
        
        print(f"  Saved {len(config.get('models', {}))} models to {filepath}")


def main():
    fetcher = ModelFetcher()
    
    if len(sys.argv) > 1:
        provider = sys.argv[1]
        print(f"Fetching models for {provider}...")
        fetcher.fetch_provider(provider)
    else:
        print("Fetching models for all providers...")
        fetcher.fetch_all()


if __name__ == "__main__":
    main()