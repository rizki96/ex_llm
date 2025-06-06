#!/usr/bin/env python3
"""
Enhanced script to fetch both model information and provider capabilities from APIs.
Can update both YAML model configs and the Elixir provider_capabilities.ex file.

Usage: 
    python scripts/fetch_provider_capabilities.py [provider]
    python scripts/fetch_provider_capabilities.py --update-elixir
"""

import os
import sys
import json
import yaml
import requests
from datetime import datetime
from typing import Dict, Any, Optional, List, Set

class CapabilityFetcher:
    def __init__(self):
        self.config_dir = "config/models"
        self.capabilities_file = "lib/ex_llm/provider_capabilities.ex"
        os.makedirs(self.config_dir, exist_ok=True)
        
        # Map of feature detection from API responses
        self.feature_mappings = {
            'openai': {
                'gpt': ['streaming', 'function_calling', 'system_messages', 'json_mode'],
                'gpt-4': ['vision'],  # GPT-4V models
                'gpt-4o': ['vision', 'structured_outputs'],
                'o1': ['reasoning', 'long_context'],
                'dall-e': ['image_generation'],
                'whisper': ['speech_recognition'],
                'tts': ['speech_synthesis'],
                'embedding': ['embeddings']
            },
            'anthropic': {
                'claude': ['streaming', 'function_calling', 'system_messages', 'json_mode', 'xml_mode'],
                'claude-3': ['vision', 'structured_outputs', 'long_context'],
                'claude-3-5': ['computer_use', 'latex_rendering', 'document_understanding']
            },
            'gemini': {
                'gemini': ['streaming', 'function_calling', 'system_messages', 'json_mode', 'vision'],
                'gemini-1.5': ['long_context', 'video_understanding', 'audio_input', 'document_understanding'],
                'gemini-2': ['code_execution', 'grounding']
            }
        }
        
    def detect_capabilities_from_model_id(self, provider: str, model_id: str) -> List[str]:
        """Detect capabilities based on model ID patterns"""
        capabilities = set()
        
        if provider in self.feature_mappings:
            for pattern, features in self.feature_mappings[provider].items():
                if pattern in model_id.lower():
                    capabilities.update(features)
                    
        return list(capabilities)
    
    def fetch_openai_capabilities(self) -> Dict[str, Any]:
        """Fetch comprehensive OpenAI capabilities"""
        api_key = os.environ.get('OPENAI_API_KEY')
        if not api_key:
            print("  No OPENAI_API_KEY found")
            return {}
            
        headers = {"Authorization": f"Bearer {api_key}"}
        capabilities = {
            'endpoints': set(),
            'features': set(),
            'models': {}
        }
        
        try:
            # Fetch models
            response = requests.get("https://api.openai.com/v1/models", headers=headers)
            if response.status_code == 200:
                data = response.json()
                
                for model in data.get('data', []):
                    model_id = model['id']
                    
                    # Detect model type and capabilities
                    if 'embedding' in model_id:
                        capabilities['endpoints'].add('embeddings')
                        capabilities['features'].add('embeddings')
                    elif 'dall-e' in model_id:
                        capabilities['endpoints'].add('images')
                        capabilities['features'].add('image_generation')
                    elif 'whisper' in model_id:
                        capabilities['endpoints'].add('audio')
                        capabilities['features'].add('speech_recognition')
                    elif 'tts' in model_id:
                        capabilities['endpoints'].add('audio')
                        capabilities['features'].add('speech_synthesis')
                    else:
                        # Chat models
                        capabilities['endpoints'].add('chat')
                        model_caps = self.detect_capabilities_from_model_id('openai', model_id)
                        capabilities['features'].update(model_caps)
                        
                        # Store model-specific capabilities
                        context_window = model.get('context_length', 4096)
                        
                        # Override known incorrect context windows
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
                            'o1': 200000,
                            'o3': 200000,
                            'o3-mini': 200000
                        }
                        
                        if model_id in context_overrides:
                            context_window = context_overrides[model_id]
                        else:
                            for pattern, ctx in context_overrides.items():
                                if pattern in model_id:
                                    context_window = ctx
                                    break
                        
                        capabilities['models'][model_id] = {
                            'context_window': context_window,
                            'capabilities': model_caps
                        }
                
                # Known OpenAI endpoints and features
                capabilities['endpoints'].update(['completions', 'fine_tuning', 'files', 
                                                'assistants', 'threads', 'runs', 'vector_stores'])
                capabilities['features'].update(['streaming', 'function_calling', 'cost_tracking', 
                                               'usage_tracking', 'dynamic_model_listing', 
                                               'batch_operations', 'file_uploads', 
                                               'rate_limiting_headers', 'system_messages', 
                                               'json_mode', 'tool_use', 'parallel_function_calling',
                                               'assistants_api', 'code_interpreter', 'retrieval',
                                               'fine_tuning_api', 'moderation', 'logprobs',
                                               'seed_control', 'response_format'])
                                               
            return {
                'endpoints': list(capabilities['endpoints']),
                'features': list(capabilities['features']),
                'models': capabilities['models']
            }
            
        except Exception as e:
            print(f"  Error fetching OpenAI capabilities: {e}")
            return {}
    
    def fetch_anthropic_capabilities(self) -> Dict[str, Any]:
        """Fetch Anthropic capabilities"""
        api_key = os.environ.get('ANTHROPIC_API_KEY')
        if not api_key:
            return {}
            
        headers = {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01"
        }
        
        capabilities = {
            'endpoints': ['chat', 'messages'],
            'features': set(),
            'models': {}
        }
        
        try:
            # Try to get model list
            response = requests.get("https://api.anthropic.com/v1/models", headers=headers)
            if response.status_code == 200:
                data = response.json()
                
                for model in data.get('data', []):
                    model_id = model.get('id', '')
                    model_caps = self.detect_capabilities_from_model_id('anthropic', model_id)
                    
                    # Add capabilities from API response
                    if model.get('supports_tools'):
                        model_caps.append('function_calling')
                        model_caps.append('tool_use')
                    if model.get('supports_vision'):
                        model_caps.append('vision')
                    if model.get('supports_system_messages', True):
                        model_caps.append('system_messages')
                        
                    capabilities['features'].update(model_caps)
                    capabilities['models'][model_id] = {
                        'context_window': model.get('context_length', 200000),
                        'max_output_tokens': model.get('max_output_length', 4096),
                        'capabilities': model_caps
                    }
            
            # Known Anthropic features
            capabilities['features'].update(['streaming', 'function_calling', 'cost_tracking',
                                           'usage_tracking', 'rate_limiting_headers', 
                                           'system_messages', 'vision', 'tool_use',
                                           'context_caching', 'computer_use', 'structured_outputs',
                                           'json_mode', 'xml_mode', 'multiple_images',
                                           'document_understanding', 'code_execution',
                                           'latex_rendering', 'long_context', 'prompt_caching',
                                           'batch_processing'])
                                           
            return {
                'endpoints': capabilities['endpoints'],
                'features': list(capabilities['features']),
                'models': capabilities['models']
            }
            
        except Exception as e:
            print(f"  Error fetching Anthropic capabilities: {e}")
            # Return known capabilities even if API fails
            return {
                'endpoints': ['chat', 'messages'],
                'features': ['streaming', 'function_calling', 'vision', 'tool_use', 
                           'system_messages', 'json_mode', 'xml_mode'],
                'models': {}
            }
    
    def fetch_gemini_capabilities(self) -> Dict[str, Any]:
        """Fetch Gemini capabilities"""
        api_key = os.environ.get('GEMINI_API_KEY') or os.environ.get('GOOGLE_API_KEY')
        if not api_key:
            return {}
            
        capabilities = {
            'endpoints': ['chat', 'embeddings', 'count_tokens'],
            'features': set(),
            'models': {}
        }
        
        try:
            url = f"https://generativelanguage.googleapis.com/v1/models?key={api_key}"
            response = requests.get(url)
            
            if response.status_code == 200:
                data = response.json()
                
                for model in data.get('models', []):
                    model_name = model['name'].replace('models/', '')
                    supported_methods = model.get('supportedGenerationMethods', [])
                    
                    model_caps = self.detect_capabilities_from_model_id('gemini', model_name)
                    
                    # Add capabilities based on supported methods
                    if 'generateContent' in supported_methods:
                        model_caps.extend(['streaming', 'function_calling'])
                    if 'embedContent' in supported_methods:
                        model_caps.append('embeddings')
                        
                    capabilities['features'].update(model_caps)
                    capabilities['models'][model_name] = {
                        'context_window': model.get('inputTokenLimit', 32768),
                        'max_output_tokens': model.get('outputTokenLimit', 2048),
                        'capabilities': model_caps
                    }
            
            # Known Gemini features
            capabilities['features'].update(['streaming', 'function_calling', 'cost_tracking',
                                           'usage_tracking', 'dynamic_model_listing',
                                           'system_messages', 'vision', 'tool_use',
                                           'json_mode', 'structured_outputs', 'grounding',
                                           'code_execution', 'multiple_images',
                                           'video_understanding', 'audio_input',
                                           'document_understanding', 'safety_settings',
                                           'citation_metadata', 'multi_turn_conversations',
                                           'context_caching'])
                                           
            return {
                'endpoints': capabilities['endpoints'],
                'features': list(capabilities['features']),
                'models': capabilities['models']
            }
            
        except Exception as e:
            print(f"  Error fetching Gemini capabilities: {e}")
            return {}
    
    def update_provider_capabilities_ex(self, all_capabilities: Dict[str, Dict]) -> bool:
        """Update the Elixir provider_capabilities.ex file with discovered capabilities"""
        print("\n📝 Updating provider_capabilities.ex...")
        
        # Read the current file
        with open(self.capabilities_file, 'r') as f:
            content = f.read()
        
        # For each provider with discovered capabilities, update the features
        for provider, caps in all_capabilities.items():
            if not caps or 'features' not in caps:
                continue
                
            # Find the provider section
            provider_start = content.find(f"{provider}: %__MODULE__.ProviderInfo{{")
            if provider_start == -1:
                print(f"  ⚠️  Could not find {provider} in provider_capabilities.ex")
                continue
                
            # Find the features list for this provider
            features_start = content.find("features: [", provider_start)
            if features_start == -1:
                continue
                
            features_end = content.find("]", features_start)
            if features_end == -1:
                continue
                
            # Extract current features
            current_features_str = content[features_start:features_end+1]
            
            # Build new features list
            new_features = sorted(set(caps['features']))
            new_features_str = "features: [\n        "
            
            # Format features nicely
            for i, feature in enumerate(new_features):
                if i > 0 and i % 4 == 0:
                    new_features_str += "\n        "
                new_features_str += f":{feature}"
                if i < len(new_features) - 1:
                    new_features_str += ", "
                else:
                    new_features_str += "\n      ]"
            
            # Update endpoints if available
            if 'endpoints' in caps:
                endpoints_start = content.find("endpoints: [", provider_start)
                if endpoints_start != -1 and endpoints_start < features_start:
                    endpoints_end = content.find("]", endpoints_start)
                    new_endpoints = sorted(set(caps['endpoints']))
                    new_endpoints_str = "endpoints: ["
                    new_endpoints_str += ", ".join(f":{e}" for e in new_endpoints)
                    new_endpoints_str += "]"
                    content = content[:endpoints_start] + new_endpoints_str + content[endpoints_end+1:]
            
            # Replace features in content
            content = content[:features_start] + new_features_str + content[features_end+1:]
            
            print(f"  ✅ Updated {provider} with {len(new_features)} features")
        
        # Write updated content
        with open(self.capabilities_file + '.new', 'w') as f:
            f.write(content)
            
        print(f"\n  💾 Saved to {self.capabilities_file}.new")
        print("  Review the changes and rename to provider_capabilities.ex if correct")
        return True
    
    def save_capabilities_yaml(self, provider: str, capabilities: Dict[str, Any]):
        """Save capabilities to a YAML file for reference"""
        file_path = os.path.join(self.config_dir, f"{provider}_capabilities.yml")
        
        data = {
            'provider': provider,
            'discovered_at': datetime.now().isoformat(),
            'endpoints': capabilities.get('endpoints', []),
            'features': capabilities.get('features', []),
            'model_capabilities': capabilities.get('models', {})
        }
        
        with open(file_path, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)
            
        print(f"  💾 Saved capabilities to {file_path}")
    
    def fetch_all_capabilities(self) -> Dict[str, Dict]:
        """Fetch capabilities from all providers"""
        all_capabilities = {}
        
        providers = {
            'openai': self.fetch_openai_capabilities,
            'anthropic': self.fetch_anthropic_capabilities,
            'gemini': self.fetch_gemini_capabilities
        }
        
        for provider, fetcher in providers.items():
            print(f"\n🔄 Fetching {provider} capabilities...")
            caps = fetcher()
            
            if caps:
                all_capabilities[provider] = caps
                self.save_capabilities_yaml(provider, caps)
                print(f"  ✅ Discovered {len(caps.get('features', []))} features")
            else:
                print(f"  ⚠️  Could not fetch capabilities")
                
        return all_capabilities


def main():
    fetcher = CapabilityFetcher()
    
    if len(sys.argv) > 1:
        if sys.argv[1] == '--update-elixir':
            # Fetch all capabilities and update the Elixir file
            all_caps = fetcher.fetch_all_capabilities()
            if all_caps:
                fetcher.update_provider_capabilities_ex(all_caps)
        elif sys.argv[1] == '--help':
            print(__doc__)
        else:
            # Fetch capabilities for a specific provider
            provider = sys.argv[1]
            method = getattr(fetcher, f'fetch_{provider}_capabilities', None)
            if method:
                caps = method()
                if caps:
                    fetcher.save_capabilities_yaml(provider, caps)
                    print(f"\n✅ Fetched {provider} capabilities")
                else:
                    print(f"\n⚠️  Could not fetch {provider} capabilities")
            else:
                print(f"Provider {provider} not supported")
    else:
        # Just fetch and save capabilities
        fetcher.fetch_all_capabilities()


if __name__ == "__main__":
    main()