#!/usr/bin/env elixir

# Test Example App with Multiple Providers
Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

defmodule TestExampleApp do
  @providers [
    {:anthropic, "claude-3-haiku-20240307"},
    {:openai, "gpt-4o-mini"},
    {:gemini, "gemini-1.5-flash"},
    {:groq, "llama-3.3-70b-versatile"},
    {:openrouter, "openai/gpt-4o-mini"},
    {:ollama, nil}  # Will use whatever model is available locally
  ]
  
  def run do
    IO.puts("\n=== Testing Example App with Multiple Providers ===\n")
    
    # Test each provider
    for {provider, model} <- @providers do
      test_provider(provider, model)
    end
    
    IO.puts("\n✅ All provider tests complete!")
  end
  
  defp test_provider(provider, model) do
    IO.puts("\n--- Testing #{provider} ---")
    
    # Check if provider is configured
    provider_module = get_provider_module(provider)
    
    case provider_module.configured?() do
      true ->
        IO.puts("✓ #{provider} is configured")
        
        # For Ollama, check if any models are available
        if provider == :ollama do
          case ExLLM.list_models(:ollama) do
            {:ok, [_ | _] = models} ->
              model = List.first(models).id
              IO.puts("  Using local model: #{model}")
              run_basic_tests(provider, model)
              
            _ ->
              IO.puts("❌ No Ollama models found locally")
              IO.puts("  Run: ollama pull llama2")
          end
        else
          run_basic_tests(provider, model)
        end
        
      false ->
        IO.puts("⚠️  #{provider} is not configured")
        IO.puts("  See setup instructions in example_app.exs")
    end
  end
  
  defp run_basic_tests(provider, model) do
    # Test 1: Basic chat
    IO.write("  Testing basic chat... ")
    
    opts = if model, do: [model: model], else: []
    
    case ExLLM.chat(provider, [
      %{role: "user", content: "Say 'OK'"}
    ], opts) do
      {:ok, _response} ->
        IO.puts("✓ Success")
        
      {:error, reason} ->
        IO.puts("❌ Failed: #{inspect(reason)}")
    end
    
    # Test 2: Streaming
    IO.write("  Testing streaming... ")
    
    result = ExLLM.stream(provider, [
      %{role: "user", content: "Count 1, 2"}
    ], fn _chunk -> :ok end, opts)
    
    case result do
      :ok ->
        IO.puts("✓ Success")
        
      {:error, reason} ->
        IO.puts("❌ Failed: #{inspect(reason)}")
    end
    
    # Test 3: Context validation  
    IO.write("  Testing context validation... ")
    
    messages = [
      %{role: "user", content: "Hello"},
      %{role: "assistant", content: "Hi there!"},
      %{role: "user", content: "How are you?"}
    ]
    
    case ExLLM.Core.Context.validate_context(messages, provider, model) do
      {:ok, token_count} ->
        IO.puts("✓ Success (#{token_count} tokens)")
        
      {:error, reason} ->
        IO.puts("❌ Failed: #{inspect(reason)}")
    end
  end
  
  defp get_provider_module(:anthropic), do: ExLLM.Providers.Anthropic
  defp get_provider_module(:openai), do: ExLLM.Providers.OpenAI
  defp get_provider_module(:gemini), do: ExLLM.Providers.Gemini
  defp get_provider_module(:groq), do: ExLLM.Providers.Groq
  defp get_provider_module(:openrouter), do: ExLLM.Providers.OpenRouter
  defp get_provider_module(:ollama), do: ExLLM.Providers.Ollama
  defp get_provider_module(:xai), do: ExLLM.Providers.XAI
end

# Run the tests
TestExampleApp.run()