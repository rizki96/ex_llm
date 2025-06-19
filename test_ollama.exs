#!/usr/bin/env elixir

# Ollama Provider Test
Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

IO.puts("\n=== Ollama Provider Test ===\n")

# 1. Test provider configuration (Ollama doesn't require API keys)
IO.puts("1. Testing provider configuration...")
if ExLLM.Providers.Ollama.configured?() do
  IO.puts("✓ Ollama provider is configured")
else
  IO.puts("⚠️  Ollama provider is not configured (this is normal if Ollama is not installed)")
  IO.puts("To test Ollama:")
  IO.puts("1. Install Ollama from https://ollama.ai")
  IO.puts("2. Run: ollama pull llama2")
  IO.puts("3. Make sure Ollama is running on http://localhost:11434")
  System.halt(0)
end

# 2. Test model listing first to see what's available
IO.puts("\n2. Testing model listing...")
case ExLLM.list_models(:ollama) do
  {:ok, models} ->
    if length(models) == 0 do
      IO.puts("⚠️  No models found locally")
      IO.puts("To pull a model: ollama pull llama2")
      System.halt(0)
    else
      IO.puts("✓ Model listing successful!")
      IO.puts("Found #{length(models)} local models:")
      
      models
      |> Enum.take(5)
      |> Enum.each(fn model ->
        IO.puts("  - #{model.id}")
      end)
    end
    
  {:error, reason} ->
    IO.puts("❌ Model listing failed: #{inspect(reason)}")
    IO.puts("Make sure Ollama is running: ollama serve")
    System.halt(1)
end

# 3. Get the first available model for testing
{:ok, models} = ExLLM.list_models(:ollama)
test_model = List.first(models).id

IO.puts("\n3. Testing basic chat with model: #{test_model}")
case ExLLM.chat(:ollama, [
  %{role: "user", content: "Reply with just the word 'hello'"}
], model: test_model) do
  {:ok, response} ->
    IO.puts("✓ Chat successful!")
    IO.puts("Response: #{inspect(response.content)}")
    IO.puts("Model: #{response.model}")
    if response.usage do
      IO.puts("Tokens: #{response.usage.total_tokens}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Chat failed: #{inspect(reason)}")
end

# 4. Test streaming
IO.puts("\n4. Testing streaming...")
callback = fn chunk ->
  case chunk do
    %{content: content} when is_binary(content) -> IO.write(content)
    _ -> :ok
  end
end

case ExLLM.stream(:ollama, [
  %{role: "user", content: "Count 1, 2, 3"}
], callback, model: test_model) do
  :ok ->
    IO.puts("\n✓ Streaming successful!")
    
  {:error, reason} ->
    IO.puts("❌ Streaming failed: #{inspect(reason)}")
end

IO.puts("\n✅ Ollama provider tests complete!")