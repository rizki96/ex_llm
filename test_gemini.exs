#!/usr/bin/env elixir

# Gemini Provider Test
Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

IO.puts("\n=== Gemini Provider Test ===\n")

# 1. Test provider configuration
IO.puts("1. Testing provider configuration...")
if ExLLM.Providers.Gemini.configured?() do
  IO.puts("✓ Gemini provider is configured")
else
  IO.puts("❌ Gemini provider is not configured")
  IO.puts("Make sure GEMINI_API_KEY is set in environment")
  System.halt(1)
end

# 2. Test basic chat
IO.puts("\n2. Testing basic chat...")
case ExLLM.chat(:gemini, [
  %{role: "user", content: "Reply with just the word 'hello'"}
], model: "gemini-1.5-flash") do
  {:ok, response} ->
    IO.puts("✓ Chat successful!")
    IO.puts("Response: #{inspect(response.content)}")
    IO.puts("Model: #{response.model}")
    if response.usage do
      IO.puts("Tokens: #{response.usage.total_tokens}")
    end
    if response.cost do
      IO.puts("Cost: $#{response.cost.total}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Chat failed: #{inspect(reason)}")
end

# 3. Test model listing
IO.puts("\n3. Testing model listing...")
case ExLLM.list_models(:gemini) do
  {:ok, models} ->
    IO.puts("✓ Model listing successful!")
    IO.puts("Found #{length(models)} models")
    
    # Show available models
    models
    |> Enum.take(10)
    |> Enum.each(fn model ->
      IO.puts("  - #{model.id}")
    end)
    
  {:error, reason} ->
    IO.puts("❌ Model listing failed: #{inspect(reason)}")
end

# 4. Test different models
IO.puts("\n4. Testing different models...")
test_models = [
  "gemini-1.5-flash",
  "gemini-1.5-pro", 
  "gemini-2.0-flash-exp"
]

for model <- test_models do
  IO.write("Testing #{model}: ")
  case ExLLM.chat(:gemini, [
    %{role: "user", content: "Say 'OK'"}
  ], model: model, timeout: 30000) do
    {:ok, response} ->
      IO.puts("✓ Success - #{String.trim(response.content || "")}")
      
    {:error, reason} ->
      IO.puts("❌ Failed - #{inspect(reason)}")
  end
end

# 5. Test streaming
IO.puts("\n5. Testing streaming...")
callback = fn chunk ->
  case chunk do
    %{content: content} when is_binary(content) -> IO.write(content)
    _ -> :ok
  end
end

case ExLLM.stream(:gemini, [
  %{role: "user", content: "Count 1, 2, 3"}
], callback, model: "gemini-1.5-flash") do
  :ok ->
    IO.puts("\n✓ Streaming successful!")
    
  {:error, reason} ->
    IO.puts("❌ Streaming failed: #{inspect(reason)}")
end

IO.puts("\n✅ Gemini provider tests complete!")