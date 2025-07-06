#!/usr/bin/env elixir

# Capability Matrix Example
# 
# This script demonstrates how to use the Provider Capability Matrix
# to understand which features are supported by each provider.

# First, let's display the basic capability matrix
IO.puts("=== Basic Capability Matrix ===\n")
ExLLM.CapabilityMatrix.display()

# Generate the matrix data programmatically
IO.puts("\n\n=== Programmatic Access ===\n")
{:ok, matrix_data} = ExLLM.CapabilityMatrix.generate()

IO.puts("Providers analyzed: #{inspect(matrix_data.providers)}")
IO.puts("Capabilities tracked: #{inspect(matrix_data.capabilities)}")

# Check specific provider capabilities
IO.puts("\n=== OpenAI Capabilities ===")
openai_caps = matrix_data.matrix[:openai]
for {capability, status} <- openai_caps do
  IO.puts("  #{capability}: #{status.indicator} (#{status.reason})")
end

# Find providers that support specific capabilities
IO.puts("\n=== Providers with Vision Support ===")
vision_providers = for {provider, caps} <- matrix_data.matrix,
                      caps[:vision].indicator == "✅",
                      do: provider
IO.puts("Providers supporting vision: #{inspect(vision_providers)}")

# Export to markdown
IO.puts("\n=== Exporting to Markdown ===")
case ExLLM.CapabilityMatrix.export(:markdown) do
  {:ok, filename} ->
    IO.puts("Matrix exported to: #{filename}")
    IO.puts("\nMarkdown preview:")
    content = File.read!(filename)
    content |> String.split("\n") |> Enum.take(10) |> Enum.join("\n") |> IO.puts()
  {:error, reason} ->
    IO.puts("Export failed: #{reason}")
end

# Show extended capability information
IO.puts("\n\n=== Extended Provider Information ===")

# Use Infrastructure modules for detailed info
for provider <- [:openai, :anthropic, :gemini] do
  IO.puts("\n#{String.upcase(to_string(provider))}:")
  
  case ExLLM.Infrastructure.Config.ProviderCapabilities.get_capabilities(provider) do
    {:ok, info} ->
      IO.puts("  Full name: #{info.name}")
      IO.puts("  Endpoints: #{inspect(info.endpoints)}")
      IO.puts("  Features: #{info.features |> Enum.take(5) |> inspect()} ...")
      IO.puts("  Auth methods: #{inspect(info.authentication)}")
      
      if map_size(info.limitations) > 0 do
        IO.puts("  Limitations:")
        info.limitations 
        |> Enum.take(3)
        |> Enum.each(fn {key, value} ->
          IO.puts("    - #{key}: #{inspect(value)}")
        end)
      end
      
    {:error, _} ->
      IO.puts("  Provider information not found")
  end
end

# Demonstrate capability detection in code
IO.puts("\n\n=== Using Capabilities in Code ===")

defmodule CapabilityDemo do
  def process_with_best_provider(required_capabilities) do
    providers = ExLLM.Capabilities.supported_providers()
    
    suitable_providers = 
      providers
      |> Enum.filter(fn provider ->
        Enum.all?(required_capabilities, fn cap ->
          ExLLM.Capabilities.supports?(provider, cap)
        end)
      end)
      |> Enum.filter(&ExLLM.configured?/1)
    
    case suitable_providers do
      [] ->
        {:error, "No configured provider supports all required capabilities"}
      [provider | _] ->
        {:ok, provider}
    end
  end
end

# Example: Find a provider for vision + streaming
case CapabilityDemo.process_with_best_provider([:vision, :streaming]) do
  {:ok, provider} ->
    IO.puts("Best provider for vision + streaming: #{provider}")
  {:error, msg} ->
    IO.puts("Error: #{msg}")
end

# Show test result integration (if available)
IO.puts("\n\n=== Test Result Summary ===")
summary = ExLLM.TestResultAggregator.generate_summary()

if map_size(summary.providers) > 0 do
  for {provider, stats} <- summary.providers do
    total = stats.total
    if total > 0 do
      IO.puts("\n#{provider}:")
      IO.puts("  Passed: #{stats.passed}/#{total}")
      IO.puts("  Failed: #{stats.failed}/#{total}")
      IO.puts("  Skipped: #{stats.skipped}/#{total}")
    end
  end
else
  IO.puts("No test results available. Run tests with aggregation enabled.")
end

IO.puts("\n✅ Capability matrix demonstration complete!")