#!/usr/bin/env python3
"""
Fetch model information from provider APIs.
Falls back to LiteLLM sync if API access fails.

Usage: python scripts/fetch_provider_models.py [provider]
"""

import os
import sys
import json
import yaml
import requests
from datetime import datetime
from typing import Dict, Any, Optional

class ModelFetcher:
    def __init__(self):
        self.config_dir = "config/models"
        os.makedirs(self.config_dir, exist_ok=True)
        
    def fetch_all(self):
        """Fetch models from all providers"""
        providers = ['anthropic', 'openai', 'groq', 'gemini', 'openrouter', 'ollama', 'bedrock']
        
        successful = []
        failed = []
        
        for provider in providers:
            print(f"\n🔄 Fetching {provider} models...")
            try:
                if self.fetch_provider(provider):
                    successful.append(provider)
                    print(f"✅ Successfully updated {provider}")
                else:
                    failed.append(provider)
                    print(f"⚠️  No API available for {provider}")
            except Exception as e:
                failed.append(provider)
                print(f"❌ Failed to update {provider}: {e}")
        
        if failed:
            print("\n⚠️  Some providers could not be updated via API.")
            print("   Run './scripts/update_models.sh --litellm' to sync from LiteLLM instead.")
    
    def fetch_provider(self, provider: str) -> bool:
        """Fetch models for a specific provider"""
        method = getattr(self, f'fetch_{provider}', None)
        if method:
            return method()
        else:
            print(f"No fetcher implemented for {provider}")
            return False
    
    def fetch_anthropic(self) -> bool:
        """Fetch Anthropic models via API"""
        api_key = os.environ.get('ANTHROPIC_API_KEY')
        if not api_key:
            print("  No ANTHROPIC_API_KEY found, skipping API fetch")
            return False
            
        headers = {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
        
        try:
            response = requests.get("https://api.anthropic.com/v1/models", headers=headers)
            if response.status_code == 200:
                data = response.json()
                models = {}
                
                # Process each model from the API - Anthropic uses 'data' not 'models'
                for model in data.get('data', []):
                    model_id = model.get('id', '')
                    models[model_id] = {
                        "context_window": model.get('context_length', 200000),
                        "max_output_tokens": model.get('max_output_length', 4096),
                        "capabilities": ["streaming"]
                    }
                    
                    # Add capabilities based on model features
                    if model.get('supports_tools', False):
                        models[model_id]["capabilities"].append("function_calling")
                    if model.get('supports_vision', False):
                        models[model_id]["capabilities"].append("vision")
                    if model.get('supports_system_messages', True):
                        models[model_id]["capabilities"].append("system_messages")
                    if model.get('supports_prompt_caching', False):
                        models[model_id]["capabilities"].append("prompt_caching")
                    if model.get('supports_computer_use', False):
                        models[model_id]["capabilities"].append("computer_use")
                    
                    # Detect capabilities from model ID
                    if 'claude-3' in model_id:
                        models[model_id]["capabilities"].extend(["json_mode", "xml_mode", "structured_outputs"])
                        if 'claude-3-5' in model_id:
                            models[model_id]["capabilities"].extend(["document_understanding", "latex_rendering"])
                
                if models:
                    # Preserve existing config structure
                    existing_config = {}
                    config_path = os.path.join(self.config_dir, "anthropic.yml")
                    if os.path.exists(config_path):
                        with open(config_path, 'r') as f:
                            existing_config = yaml.safe_load(f) or {}
                    
                    config = {
                        "provider": "anthropic",
                        "default_model": existing_config.get("default_model", "claude-3-5-sonnet-20241022"),
                        "models": models,
                        "metadata": {
                            "updated_at": datetime.now().isoformat(),
                            "source": "anthropic_api"
                        }
                    }
                    self._save_config("anthropic", config)
                    return True
                else:
                    print("  No models found in API response")
                    return False
            else:
                print(f"  API returned status {response.status_code}")
                return False
        except Exception as e:
            print(f"  API error: {e}")
            return False
    
    def fetch_openai(self) -> bool:
        """Fetch OpenAI models via API"""
        api_key = os.environ.get('OPENAI_API_KEY')
        
        if not api_key:
            print("  No OPENAI_API_KEY found, skipping API fetch")
            return False
            
        headers = {"Authorization": f"Bearer {api_key}"}
        try:
            response = requests.get("https://api.openai.com/v1/models", headers=headers)
            if response.status_code == 200:
                data = response.json()
                models = {}
                
                # Process each model
                for model in data.get('data', []):
                    model_id = model['id']
                    # Skip non-chat models
                    if any(x in model_id for x in ['embedding', 'tts', 'whisper', 'dall-e']):
                        continue
                        
                    capabilities = ["streaming", "system_messages"]
                    
                    # Detect capabilities from model ID
                    if 'gpt-4' in model_id:
                        capabilities.extend(["function_calling", "json_mode"])
                        if 'vision' in model_id or 'gpt-4o' in model_id:
                            capabilities.append("vision")
                        if 'gpt-4o' in model_id:
                            capabilities.append("structured_outputs")
                    elif 'gpt-3.5' in model_id:
                        capabilities.extend(["function_calling", "json_mode"])
                    elif 'o1' in model_id:
                        capabilities.extend(["reasoning", "long_context"])
                    
                    # Get context window with better defaults
                    context_window = model.get('context_length', 4096)
                    
                    # OpenAI API often returns incorrect context windows, so we override with known values
                    context_overrides = {
                        'gpt-4o': 128000,
                        'gpt-4o-mini': 128000,
                        'gpt-4-turbo': 128000,
                        'gpt-4-turbo-preview': 128000,
                        'gpt-4-0125-preview': 128000,
                        'gpt-4-1106-preview': 128000,
                        'gpt-4': 8192,
                        'gpt-4-0613': 8192,
                        'gpt-3.5-turbo': 16385,
                        'gpt-3.5-turbo-0125': 16385,
                        'gpt-3.5-turbo-1106': 16385,
                        'gpt-3.5-turbo-16k': 16385,
                        'o1-preview': 128000,
                        'o1-mini': 128000,
                        'o1': 200000,  # o1 has 200k context
                        'o3': 200000,
                        'o3-mini': 200000
                    }
                    
                    # Check for exact match first
                    if model_id in context_overrides:
                        context_window = context_overrides[model_id]
                    else:
                        # Check for partial matches
                        for pattern, ctx in context_overrides.items():
                            if pattern in model_id:
                                context_window = ctx
                                break
                    
                    models[model_id] = {
                        "context_window": context_window,
                        "capabilities": capabilities
                    }
                
                if models:
                    config = {
                        "provider": "openai",
                        "default_model": "gpt-4-turbo",
                        "models": models,
                        "metadata": {
                            "updated_at": datetime.now().isoformat(),
                            "source": "openai_api"
                        }
                    }
                    self._save_config("openai", config)
                    return True
            else:
                print(f"  API returned status {response.status_code}")
                return False
        except Exception as e:
            print(f"  API error: {e}")
            return False
    
    def fetch_groq(self) -> bool:
        """Fetch Groq models via API"""
        api_key = os.getenv('GROQ_API_KEY')
        if not api_key:
            print("  ⚠️  GROQ_API_KEY not found in environment")
            return False
            
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        
        try:
            response = requests.get("https://api.groq.com/openai/v1/models", headers=headers)
            if response.status_code == 200:
                data = response.json()
                models = {}
                
                # Process each model from the API
                for model in data.get('data', []):
                    model_id = model.get('id', '')
                    models[model_id] = {
                        "context_window": model.get('context_window', 4096),
                        "capabilities": ["streaming"]
                    }
                    
                    # Add capabilities based on model features
                    if model.get('supports_tools', False):
                        models[model_id]["capabilities"].append("function_calling")
                
                if models:
                    # Preserve existing config structure
                    existing_config = {}
                    if os.path.exists(f"config/models/groq.yml"):
                        with open(f"config/models/groq.yml", 'r') as f:
                            existing_config = yaml.safe_load(f) or {}
                    
                    # Update with API models
                    config = {
                        "provider": "groq",
                        "default_model": existing_config.get("default_model", "llama-3.3-70b-versatile"),
                        "models": {}
                    }
                    
                    # Preserve existing model data and merge with API data
                    for model_id, api_data in models.items():
                        existing_model = existing_config.get("models", {}).get(model_id, {})
                        config["models"][model_id] = {
                            "context_window": api_data["context_window"],
                            "capabilities": api_data["capabilities"]
                        }
                        # Preserve pricing if it exists
                        if "pricing" in existing_model:
                            config["models"][model_id]["pricing"] = existing_model["pricing"]
                    
                    # Save updated config
                    os.makedirs("config/models", exist_ok=True)
                    with open(f"config/models/groq.yml", 'w') as f:
                        yaml.dump(config, f, default_flow_style=False, sort_keys=False)
                    
                    print(f"  Saved {len(models)} models to config/models/groq.yml")
                    return True
                else:
                    print("  No models found in API response")
                    return False
            else:
                print(f"  API returned status {response.status_code}")
                return False
        except Exception as e:
            print(f"  Error: {e}")
            return False
    
    def fetch_gemini(self) -> bool:
        """Fetch Gemini models via API"""
        api_key = os.environ.get('GEMINI_API_KEY') or os.environ.get('GOOGLE_API_KEY')
        
        if not api_key:
            print("  No GEMINI_API_KEY or GOOGLE_API_KEY found, skipping API fetch")
            return False
            
        try:
            url = f"https://generativelanguage.googleapis.com/v1/models?key={api_key}"
            response = requests.get(url)
            if response.status_code == 200:
                data = response.json()
                models = {}
                
                for model in data.get('models', []):
                    if 'generateContent' in model.get('supportedGenerationMethods', []):
                        model_name = model['name'].replace('models/', '')
                        capabilities = ["streaming", "function_calling", "system_messages"]
                        
                        # Detect capabilities from model name and properties
                        if 'vision' in model_name or 'gemini-pro-vision' in model_name:
                            capabilities.append("vision")
                        if 'gemini-1.5' in model_name:
                            capabilities.extend(["long_context", "document_understanding", "audio_input"])
                            if 'pro' in model_name:
                                capabilities.append("video_understanding")
                        if model.get('supportsCodeExecution', False):
                            capabilities.append("code_execution")
                        if model.get('supportsGrounding', False):
                            capabilities.append("grounding")
                            
                        models[f"gemini/{model_name}"] = {
                            "context_window": model.get('inputTokenLimit', 32760),
                            "max_output_tokens": model.get('outputTokenLimit', 2048),
                            "capabilities": capabilities
                        }
                
                if models:
                    config = {
                        "provider": "gemini",
                        "default_model": "gemini/gemini-pro",
                        "models": models,
                        "metadata": {
                            "updated_at": datetime.now().isoformat(),
                            "source": "gemini_api"
                        }
                    }
                    self._save_config("gemini", config)
                    return True
            else:
                print(f"  API returned status {response.status_code}")
                return False
        except Exception as e:
            print(f"  API error: {e}")
            return False
    
    def fetch_openrouter(self) -> bool:
        """Fetch OpenRouter models via their public API"""
        try:
            response = requests.get("https://openrouter.ai/api/v1/models")
            if response.status_code == 200:
                data = response.json()
                models = {}
                
                for model in data.get('data', []):
                    model_id = model['id']
                    models[model_id] = {
                        "context_window": model.get('context_length', 4096),
                        "max_output_tokens": model.get('max_output_tokens'),
                        "capabilities": ["streaming"]
                    }
                    
                    # Add pricing if available
                    if 'pricing' in model:
                        prompt_price = float(model['pricing'].get('prompt', 0)) * 1_000_000
                        completion_price = float(model['pricing'].get('completion', 0)) * 1_000_000
                        if prompt_price > 0 or completion_price > 0:
                            models[model_id]["pricing"] = {
                                "input": prompt_price,
                                "output": completion_price
                            }
                
                if models:
                    config = {
                        "provider": "openrouter",
                        "default_model": "anthropic/claude-3-5-sonnet",
                        "models": models,
                        "metadata": {
                            "updated_at": datetime.now().isoformat(),
                            "source": "openrouter_api"
                        }
                    }
                    self._save_config("openrouter", config)
                    return True
            else:
                print(f"  API returned status {response.status_code}")
                return False
        except Exception as e:
            print(f"  API error: {e}")
            return False
    
    def fetch_ollama(self) -> bool:
        """Fetch Ollama models from local server"""
        base_url = os.environ.get('OLLAMA_API_BASE', 'http://localhost:11434')
        try:
            response = requests.get(f"{base_url}/api/tags", timeout=5)
            if response.status_code == 200:
                data = response.json()
                models = {}
                
                for model in data.get('models', []):
                    model_name = model['name']
                    model_info = {
                        "context_window": 4096,  # Default, will be updated if we get details
                        "capabilities": ["streaming"]
                    }
                    
                    # Try to get detailed info for each model using /api/show
                    try:
                        detail_response = requests.post(
                            f"{base_url}/api/show",
                            json={"name": model_name},
                            timeout=5
                        )
                        if detail_response.status_code == 200:
                            details = detail_response.json()
                            
                            # Update capabilities based on actual capabilities field
                            if "capabilities" in details:
                                caps = details["capabilities"]
                                if "tools" in caps or ("completion" in caps and "tools" in caps):
                                    model_info["capabilities"].append("function_calling")
                                if "embedding" in caps:
                                    model_info["capabilities"].append("embeddings")
                                    
                            # Get actual context window from model info
                            if "model_info" in details:
                                info = details["model_info"]
                                # Try different architecture fields
                                context = (
                                    info.get("qwen3.context_length") or
                                    info.get("llama.context_length") or
                                    info.get("bert.context_length") or
                                    info.get("mistral.context_length") or
                                    info.get("gemma.context_length") or
                                    info.get("gemma2.context_length") or
                                    info.get("general.context_length")
                                )
                                if context:
                                    model_info["context_window"] = context
                                    
                                # Get parameter size if available
                                param_count = info.get("general.parameter_count")
                                if param_count:
                                    # Convert to human readable
                                    if param_count >= 1e9:
                                        param_size = f"{param_count/1e9:.1f}B"
                                    else:
                                        param_size = f"{param_count/1e6:.0f}M"
                                    model_info["parameter_size"] = param_size
                            
                            # Also check details section
                            if "details" in details:
                                det = details["details"]
                                if "parameter_size" in det:
                                    model_info["parameter_size"] = det["parameter_size"]
                                    
                    except Exception as e:
                        # If show fails, fall back to name-based detection
                        print(f"    Could not get details for {model_name}: {e}")
                    
                    # Fallback: Add capabilities based on model name patterns
                    if "function_calling" not in model_info["capabilities"]:
                        if any(x in model_name.lower() for x in [
                            "llama3.1", "llama3.2", "llama3.3", 
                            "mistral", "mixtral", 
                            "qwen2", "qwen2.5", 
                            "command-r", "gemma2", "firefunction"
                        ]):
                            model_info["capabilities"].append("function_calling")
                    
                    if any(x in model_name.lower() for x in ["vision", "llava", "bakllava"]):
                        if "vision" not in model_info["capabilities"]:
                            model_info["capabilities"].append("vision")
                    
                    if any(x in model_name.lower() for x in ["embed", "embedding"]):
                        if "embeddings" not in model_info["capabilities"]:
                            model_info["capabilities"].append("embeddings")
                    
                    # Add to models dict with ollama/ prefix
                    models[f"ollama/{model_name}"] = model_info
                
                if models:
                    # Preserve existing config structure
                    existing_config = {}
                    config_path = os.path.join(self.config_dir, "ollama.yml")
                    if os.path.exists(config_path):
                        with open(config_path, 'r') as f:
                            existing_config = yaml.safe_load(f) or {}
                    
                    config = {
                        "provider": "ollama",
                        "default_model": existing_config.get("default_model", list(models.keys())[0] if models else "ollama/llama2"),
                        "models": models,
                        "metadata": {
                            "updated_at": datetime.now().isoformat(),
                            "source": "ollama_api"
                        }
                    }
                    self._save_config("ollama", config)
                    return True
                else:
                    print("  No models found in Ollama")
                    return False
            else:
                print(f"  Ollama API returned status {response.status_code}")
                return False
        except requests.exceptions.ConnectionError:
            print("  Ollama not running (start with 'ollama serve')")
            return False
        except Exception as e:
            print(f"  Error connecting to Ollama: {e}")
            return False
    
    def fetch_bedrock(self) -> bool:
        """Fetch Bedrock models"""
        # Bedrock requires AWS SDK and authentication
        # For now, we'll skip dynamic fetching
        print("  Bedrock requires AWS authentication, skipping API fetch")
        return False
    
    def _save_config(self, provider: str, config: Dict[str, Any]):
        """Save configuration to YAML file, preserving manual additions"""
        file_path = os.path.join(self.config_dir, f"{provider}.yml")
        
        # Load existing config if it exists
        existing_config = {}
        if os.path.exists(file_path):
            with open(file_path, 'r') as f:
                existing_config = yaml.safe_load(f) or {}
        
        # Merge with existing, preferring new data
        if 'models' in existing_config and 'models' in config:
            # Preserve manual additions in existing models
            for model_id, model_data in existing_config['models'].items():
                if model_id in config['models']:
                    # Merge model data, keeping manual fields
                    for key, value in model_data.items():
                        if key not in config['models'][model_id]:
                            config['models'][model_id][key] = value
                else:
                    # Keep models that aren't in the new data
                    config['models'][model_id] = model_data
        
        # Save updated config
        with open(file_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)
        
        print(f"  Saved {len(config.get('models', {}))} models to {file_path}")


def main():
    fetcher = ModelFetcher()
    
    if len(sys.argv) > 1:
        provider = sys.argv[1]
        if provider == '--help':
            print(__doc__)
            sys.exit(0)
        
        print(f"Fetching {provider} models...")
        if fetcher.fetch_provider(provider):
            print(f"✅ Successfully updated {provider}")
        else:
            print(f"⚠️  Could not fetch {provider} from API")
            print("   Run './scripts/update_models.sh --litellm' to sync from LiteLLM instead.")
    else:
        fetcher.fetch_all()


if __name__ == "__main__":
    main()