#!/usr/bin/env elixir
# Example: Managing Ollama model configurations

# This example demonstrates how to use the Ollama adapter's
# configuration management functions to keep your ollama.yml
# file in sync with your locally installed models.

# When running inside the project, we don't need Mix.install
# Mix.install([{:ex_llm, path: ".."}])

defmodule OllamaConfigExample do
  def run do
    IO.puts("=== Ollama Configuration Management Example ===\n")
    
    # Check if Ollama is running
    case ExLLM.Adapters.Ollama.version() do
      {:ok, version} ->
        IO.puts("✓ Ollama is running: #{inspect(version)}")
        
      {:error, _} ->
        IO.puts("✗ Ollama is not running. Please start it with: ollama serve")
        System.halt(1)
    end
    
    # 1. Generate configuration for all models (preview)
    IO.puts("\n1. Generating configuration for all installed models...")
    case ExLLM.Adapters.Ollama.generate_config() do
      {:ok, yaml} ->
        IO.puts("✓ Generated configuration preview:")
        IO.puts("---")
        yaml |> String.split("\n") |> Enum.take(20) |> Enum.join("\n") |> IO.puts()
        IO.puts("... (truncated)\n")
        
      {:error, reason} ->
        IO.puts("✗ Failed to generate config: #{inspect(reason)}")
    end
    
    # 2. List current models
    IO.puts("2. Listing installed models...")
    case ExLLM.Adapters.Ollama.list_models() do
      {:ok, models} ->
        IO.puts("✓ Found #{length(models)} models:")
        models
        |> Enum.take(5)
        |> Enum.each(fn model ->
          caps = model.capabilities.features |> Enum.map(&to_string/1) |> Enum.join(", ")
          IO.puts("  - #{model.name} (context: #{model.context_window}, features: #{caps})")
        end)
        
        if length(models) > 5 do
          IO.puts("  ... and #{length(models) - 5} more")
        end
        
      {:error, reason} ->
        IO.puts("✗ Failed to list models: #{inspect(reason)}")
    end
    
    # 3. Update a specific model (if available)
    IO.puts("\n3. Updating configuration for a specific model...")
    test_model = "llama3.1"
    
    case ExLLM.Adapters.Ollama.show_model(test_model) do
      {:ok, _} ->
        case ExLLM.Adapters.Ollama.update_model_config(test_model, save: false) do
          {:ok, yaml} ->
            IO.puts("✓ Configuration for #{test_model}:")
            # Extract just the model's config from the YAML
            yaml
            |> String.split("\n")
            |> Enum.filter(&String.contains?(&1, test_model))
            |> Enum.take(10)
            |> Enum.each(&IO.puts("  #{&1}"))
            
          {:error, reason} ->
            IO.puts("✗ Failed to update config: #{inspect(reason)}")
        end
        
      {:error, _} ->
        IO.puts("✗ Model #{test_model} not found. Skipping update example.")
    end
    
    # 4. Save configuration (optional)
    IO.puts("\n4. Saving configuration...")
    
    # In automated contexts, skip the interactive prompt
    if System.get_env("SAVE_CONFIG") == "true" do
      case ExLLM.Adapters.Ollama.generate_config(save: true) do
        {:ok, path} ->
          IO.puts("✓ Configuration saved to: #{path}")
          
        {:error, reason} ->
          IO.puts("✗ Failed to save: #{inspect(reason)}")
      end
    else
      IO.puts("✓ Skipped saving configuration (set SAVE_CONFIG=true to save)")
      IO.puts("  You can manually save by running:")
      IO.puts("  {:ok, path} = ExLLM.Adapters.Ollama.generate_config(save: true)")
    end
    
    IO.puts("\n=== Example Complete ===")
  end
end

OllamaConfigExample.run()