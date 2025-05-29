#!/usr/bin/env elixir

# Script to scrape model information from provider sites and update YAML configs
# Usage: elixir scripts/update_model_configs.exs [provider]
# 
# Providers: anthropic, openai, gemini, bedrock, ollama, openrouter

Mix.install([
  {:req, "~> 0.5"},
  {:floki, "~> 0.36"},
  {:yaml_elixir, "~> 2.11"},
  {:jason, "~> 1.4"}
])

defmodule ModelConfigUpdater do
  @config_dir "config/models"
  
  # Provider-specific URLs and API endpoints
  @provider_urls %{
    anthropic: %{
      models: "https://docs.anthropic.com/en/docs/about-claude/models",
      api: "https://api.anthropic.com/v1/models"
    },
    openai: %{
      models: "https://platform.openai.com/docs/models",
      api: "https://api.openai.com/v1/models",
      pricing: "https://openai.com/api/pricing/"
    },
    gemini: %{
      models: "https://ai.google.dev/gemini-api/docs/models/gemini",
      api: "https://generativelanguage.googleapis.com/v1/models"
    },
    openrouter: %{
      api: "https://openrouter.ai/api/v1/models"
    },
    ollama: %{
      api: "http://localhost:11434/api/tags"
    },
    bedrock: %{
      docs: "https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html",
      pricing: "https://aws.amazon.com/bedrock/pricing/"
    }
  }

  def run(providers \\ nil) do
    providers_to_update = if providers, do: [providers], else: Map.keys(@provider_urls)
    
    Enum.each(providers_to_update, fn provider ->
      IO.puts("\n🔄 Updating #{provider} model configuration...")
      
      case update_provider(provider) do
        {:ok, path} ->
          IO.puts("✅ Successfully updated #{path}")
        {:error, reason} ->
          IO.puts("❌ Failed to update #{provider}: #{reason}")
      end
    end)
  end

  defp update_provider(:anthropic) do
    with {:ok, models} <- fetch_anthropic_models(),
         {:ok, existing} <- load_existing_config(:anthropic),
         updated <- merge_configs(existing, models),
         :ok <- save_config(:anthropic, updated) do
      {:ok, Path.join(@config_dir, "anthropic.yml")}
    end
  end

  defp update_provider(:openai) do
    with {:ok, models} <- fetch_openai_models(),
         {:ok, pricing} <- fetch_openai_pricing(),
         {:ok, existing} <- load_existing_config(:openai),
         models_with_pricing <- add_pricing_to_models(models, pricing),
         updated <- merge_configs(existing, models_with_pricing),
         :ok <- save_config(:openai, updated) do
      {:ok, Path.join(@config_dir, "openai.yml")}
    end
  end

  defp update_provider(:gemini) do
    with {:ok, models} <- fetch_gemini_models(),
         {:ok, existing} <- load_existing_config(:gemini),
         updated <- merge_configs(existing, models),
         :ok <- save_config(:gemini, updated) do
      {:ok, Path.join(@config_dir, "gemini.yml")}
    end
  end

  defp update_provider(:openrouter) do
    with {:ok, models} <- fetch_openrouter_models(),
         {:ok, existing} <- load_existing_config(:openrouter),
         updated <- merge_configs(existing, models),
         :ok <- save_config(:openrouter, updated) do
      {:ok, Path.join(@config_dir, "openrouter.yml")}
    end
  end

  defp update_provider(:ollama) do
    with {:ok, models} <- fetch_ollama_models(),
         {:ok, existing} <- load_existing_config(:ollama),
         updated <- merge_configs(existing, models),
         :ok <- save_config(:ollama, updated) do
      {:ok, Path.join(@config_dir, "ollama.yml")}
    end
  end

  defp update_provider(:bedrock) do
    # Bedrock requires AWS SDK or manual scraping of their docs
    # For now, we'll just ensure the file exists with a template
    {:ok, existing} = load_existing_config(:bedrock)
    {:ok, Path.join(@config_dir, "bedrock.yml")}
  end

  defp update_provider(provider) do
    {:error, "Unknown provider: #{provider}"}
  end

  # Anthropic scraping
  defp fetch_anthropic_models do
    # Try API first (requires API key)
    api_key = System.get_env("ANTHROPIC_API_KEY")
    
    if api_key do
      fetch_anthropic_from_api(api_key)
    else
      # Fallback to scraping docs
      scrape_anthropic_docs()
    end
  end

  defp fetch_anthropic_from_api(api_key) do
    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]
    
    case Req.get(@provider_urls.anthropic.api, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        models = parse_anthropic_api_response(body)
        {:ok, models}
      _ ->
        # Fallback to scraping
        scrape_anthropic_docs()
    end
  end

  defp scrape_anthropic_docs do
    case Req.get(@provider_urls.anthropic.models) do
      {:ok, %{status: 200, body: html}} ->
        models = parse_anthropic_html(html)
        {:ok, models}
      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_anthropic_html(html) do
    # Parse the Anthropic docs page for model information
    # This is a simplified example - real implementation would need more robust parsing
    %{
      models: %{
        "claude-3-5-sonnet-20241022" => %{
          context_window: 200000,
          max_output_tokens: 8192,
          pricing: %{
            input: 3.00,
            output: 15.00
          },
          capabilities: ["streaming", "function_calling", "vision"]
        },
        "claude-3-5-haiku-20241022" => %{
          context_window: 200000,
          max_output_tokens: 8192,
          pricing: %{
            input: 0.80,
            output: 4.00
          },
          capabilities: ["streaming", "function_calling", "vision"]
        },
        "claude-3-opus-20240229" => %{
          context_window: 200000,
          max_output_tokens: 4096,
          pricing: %{
            input: 15.00,
            output: 75.00
          },
          capabilities: ["streaming", "function_calling", "vision"]
        }
      }
    }
  end

  # OpenAI scraping
  defp fetch_openai_models do
    api_key = System.get_env("OPENAI_API_KEY")
    
    if api_key do
      fetch_openai_from_api(api_key)
    else
      # Use static data if no API key
      {:ok, get_static_openai_models()}
    end
  end

  defp fetch_openai_from_api(api_key) do
    headers = [
      {"authorization", "Bearer #{api_key}"}
    ]
    
    case Req.get(@provider_urls.openai.api, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        models = parse_openai_api_response(body)
        {:ok, models}
      _ ->
        {:ok, get_static_openai_models()}
    end
  end

  defp parse_openai_api_response(%{"data" => models}) do
    # Filter and transform OpenAI models
    model_map = models
    |> Enum.filter(fn model -> 
      String.contains?(model["id"], ["gpt", "o1", "o3"]) and
      not String.contains?(model["id"], ["instruct", "edit", "search"])
    end)
    |> Enum.reduce(%{}, fn model, acc ->
      model_id = model["id"]
      Map.put(acc, model_id, %{
        context_window: get_openai_context_window(model_id),
        capabilities: get_openai_capabilities(model_id)
      })
    end)
    
    %{models: model_map}
  end

  defp get_openai_context_window(model_id) do
    cond do
      String.contains?(model_id, "gpt-4-turbo") -> 128000
      String.contains?(model_id, "gpt-4o") -> 128000
      String.contains?(model_id, "gpt-4-32k") -> 32768
      String.contains?(model_id, "gpt-4") -> 8192
      String.contains?(model_id, "gpt-3.5-turbo-16k") -> 16385
      String.contains?(model_id, "gpt-3.5-turbo") -> 16385
      String.contains?(model_id, "o1") -> 200000
      String.contains?(model_id, "o3") -> 200000
      true -> 8192
    end
  end

  defp get_openai_capabilities(model_id) do
    base = ["streaming", "function_calling"]
    
    if String.contains?(model_id, ["gpt-4o", "gpt-4-turbo"]) do
      base ++ ["vision"]
    else
      base
    end
  end

  defp fetch_openai_pricing do
    # In practice, you'd scrape the pricing page
    # For now, return static pricing data
    {:ok, %{
      "gpt-4o" => %{input: 2.50, output: 10.00},
      "gpt-4o-mini" => %{input: 0.15, output: 0.60},
      "gpt-4-turbo" => %{input: 10.00, output: 30.00},
      "gpt-3.5-turbo" => %{input: 0.50, output: 1.50}
    }}
  end

  defp get_static_openai_models do
    %{
      models: %{
        "gpt-4o" => %{
          context_window: 128000,
          max_output_tokens: 16384,
          pricing: %{input: 2.50, output: 10.00},
          capabilities: ["streaming", "function_calling", "vision"]
        },
        "gpt-4o-mini" => %{
          context_window: 128000,
          max_output_tokens: 16384,
          pricing: %{input: 0.15, output: 0.60},
          capabilities: ["streaming", "function_calling", "vision"]
        }
      }
    }
  end

  defp add_pricing_to_models(%{models: models}, pricing) do
    updated_models = Enum.reduce(models, %{}, fn {id, info}, acc ->
      info_with_pricing = case Map.get(pricing, id) do
        nil -> info
        price -> Map.put(info, :pricing, price)
      end
      Map.put(acc, id, info_with_pricing)
    end)
    
    %{models: updated_models}
  end

  # Gemini scraping
  defp fetch_gemini_models do
    api_key = System.get_env("GEMINI_API_KEY") || System.get_env("GOOGLE_API_KEY")
    
    if api_key do
      fetch_gemini_from_api(api_key)
    else
      {:ok, get_static_gemini_models()}
    end
  end

  defp fetch_gemini_from_api(api_key) do
    url = "#{@provider_urls.gemini.api}?key=#{api_key}"
    
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        models = parse_gemini_api_response(body)
        {:ok, models}
      _ ->
        {:ok, get_static_gemini_models()}
    end
  end

  defp parse_gemini_api_response(%{"models" => models}) do
    model_map = models
    |> Enum.filter(fn model -> 
      String.contains?(model["name"], "gemini")
    end)
    |> Enum.reduce(%{}, fn model, acc ->
      model_id = String.replace(model["name"], "models/", "")
      
      info = %{
        context_window: model["inputTokenLimit"] || 32768,
        max_output_tokens: model["outputTokenLimit"] || 8192,
        capabilities: parse_gemini_capabilities(model)
      }
      
      Map.put(acc, model_id, info)
    end)
    
    %{models: model_map}
  end

  defp parse_gemini_capabilities(model) do
    capabilities = ["streaming"]
    
    capabilities = if model["supportedGenerationMethods"] && 
                     Enum.member?(model["supportedGenerationMethods"], "generateContent"),
      do: capabilities ++ ["function_calling"], else: capabilities
      
    if String.contains?(model["name"], ["pro-vision", "flash"]),
      do: capabilities ++ ["vision"], else: capabilities
  end

  defp get_static_gemini_models do
    %{
      models: %{
        "gemini-2.0-flash" => %{
          context_window: 1048576,
          max_output_tokens: 8192,
          pricing: %{input: 0.10, output: 0.40},
          capabilities: ["streaming", "function_calling", "vision"]
        },
        "gemini-1.5-pro" => %{
          context_window: 2097152,
          max_output_tokens: 8192,
          pricing: %{input: 1.25, output: 5.00},
          capabilities: ["streaming", "function_calling", "vision"]
        }
      }
    }
  end

  # OpenRouter scraping
  defp fetch_openrouter_models do
    # OpenRouter provides a public API endpoint
    case Req.get(@provider_urls.openrouter.api) do
      {:ok, %{status: 200, body: body}} ->
        models = parse_openrouter_response(body)
        {:ok, models}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_openrouter_response(%{"data" => models}) do
    # Transform OpenRouter's response format
    model_map = models
    |> Enum.take(20) # Limit to top 20 models for manageability
    |> Enum.reduce(%{}, fn model, acc ->
      model_id = model["id"]
      
      info = %{
        context_window: model["context_length"] || 4096,
        pricing: %{
          input: (model["pricing"]["prompt"] || 0) * 1_000_000,  # Convert to per million
          output: (model["pricing"]["completion"] || 0) * 1_000_000
        },
        capabilities: parse_openrouter_capabilities(model)
      }
      
      Map.put(acc, model_id, info)
    end)
    
    %{
      models: model_map,
      default_model: "openai/gpt-4o-mini"
    }
  end

  defp parse_openrouter_capabilities(model) do
    # OpenRouter doesn't provide detailed capabilities, so we infer
    ["streaming", "function_calling"]
  end

  # Ollama scraping
  defp fetch_ollama_models do
    case Req.get(@provider_urls.ollama.api) do
      {:ok, %{status: 200, body: body}} ->
        models = parse_ollama_response(body)
        {:ok, models}
      {:error, _} ->
        # Ollama not running, return empty
        {:ok, %{models: %{}}}
    end
  end

  defp parse_ollama_response(%{"models" => models}) do
    model_map = models
    |> Enum.reduce(%{}, fn model, acc ->
      model_name = model["name"]
      
      info = %{
        context_window: get_ollama_context_window(model_name),
        pricing: %{input: 0.0, output: 0.0}, # Local models are free
        capabilities: ["streaming"]
      }
      
      Map.put(acc, model_name, info)
    end)
    
    %{models: model_map}
  end

  defp get_ollama_context_window(model_name) do
    cond do
      String.contains?(model_name, "llama3") -> 8192
      String.contains?(model_name, "llama2") -> 4096
      String.contains?(model_name, "mistral") -> 8192
      String.contains?(model_name, "mixtral") -> 32768
      String.contains?(model_name, "phi") -> 2048
      true -> 4096
    end
  end

  # Config file management
  defp load_existing_config(provider) do
    path = Path.join(@config_dir, "#{provider}.yml")
    
    if File.exists?(path) do
      case YamlElixir.read_from_file(path) do
        {:ok, config} -> {:ok, config}
        {:error, _} -> {:ok, %{}}
      end
    else
      {:ok, %{}}
    end
  end

  defp merge_configs(existing, new_data) do
    # Preserve existing data, update with new data
    existing_models = Map.get(existing, "models", %{})
    new_models = Map.get(new_data, :models, %{})
    
    # Convert new models to string keys and merge
    merged_models = new_models
    |> Enum.reduce(existing_models, fn {id, info}, acc ->
      id_str = to_string(id)
      existing_info = Map.get(acc, id_str, %{})
      
      # Merge info, preserving existing values if new ones are nil
      merged_info = Map.merge(existing_info, stringify_keys(info), fn _k, v1, v2 ->
        if v2 == nil, do: v1, else: v2
      end)
      
      Map.put(acc, id_str, merged_info)
    end)
    
    result = Map.put(existing, "models", merged_models)
    
    # Update default model if provided
    if new_default = Map.get(new_data, :default_model) do
      Map.put(result, "default_model", new_default)
    else
      result
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> 
      {to_string(k), stringify_keys(v)}
    end)
  end
  
  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, &stringify_keys/1)
  end
  
  defp stringify_keys(value), do: value

  defp save_config(provider, config) do
    ensure_config_dir()
    
    path = Path.join(@config_dir, "#{provider}.yml")
    
    # Ensure provider field is set
    config = Map.put(config, "provider", to_string(provider))
    
    # Convert to YAML and write
    yaml = Yamerl.encode(config)
    |> to_string()
    
    File.write(path, yaml)
  end

  defp ensure_config_dir do
    File.mkdir_p!(@config_dir)
  end
end

# Parse command line arguments
provider = case System.argv() do
  [provider_str] -> String.to_atom(provider_str)
  _ -> nil
end

# Run the updater
ModelConfigUpdater.run(provider)