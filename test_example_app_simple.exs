#!/usr/bin/env elixir

# Simple test to verify example app works with different providers
Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

defmodule TestProviders do
  def get_provider_module(:anthropic), do: ExLLM.Providers.Anthropic
  def get_provider_module(:openai), do: ExLLM.Providers.OpenAI
  def get_provider_module(:gemini), do: ExLLM.Providers.Gemini
  def get_provider_module(:groq), do: ExLLM.Providers.Groq
  def get_provider_module(:openrouter), do: ExLLM.Providers.OpenRouter
  def get_provider_module(:ollama), do: ExLLM.Providers.Ollama
end

IO.puts("\n=== Testing Example App with Different Providers ===\n")

# Test providers
providers = [:anthropic, :openai, :gemini, :groq, :openrouter, :ollama]

# Quick test with each provider
Enum.each(providers, fn provider ->
  IO.puts("\n--- Testing #{provider} ---")
  
  # Check if configured
  provider_module = TestProviders.get_provider_module(provider)
  
  if provider_module.configured?() do
    IO.puts("✓ #{provider} is configured")
    
    # Test basic chat
    case ExLLM.chat(provider, [
      %{role: "user", content: "Reply with 'OK'"}
    ]) do
      {:ok, response} ->
        IO.puts("✓ Chat successful: #{String.trim(response.content || "")}")
        
      {:error, reason} ->
        IO.puts("❌ Chat failed: #{inspect(reason)}")
    end
  else
    IO.puts("⚠️  #{provider} is not configured")
  end
end)

IO.puts("\n✅ All tests complete!")