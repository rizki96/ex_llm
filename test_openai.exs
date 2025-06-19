#!/usr/bin/env elixir

# OpenAI Provider Test
Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

IO.puts("\n=== OpenAI Provider Test ===\n")

# 1. Test provider configuration
IO.puts("1. Testing provider configuration...")
if ExLLM.Providers.OpenAI.configured?() do
  IO.puts("✓ OpenAI provider is configured")
else
  IO.puts("❌ OpenAI provider is not configured")
  IO.puts("Make sure OPENAI_API_KEY is set in environment")
  System.halt(1)
end

# 2. Test basic chat
IO.puts("\n2. Testing basic chat...")
case ExLLM.chat(:openai, [
  %{role: "user", content: "Reply with just the word 'hello'"}
], model: "gpt-4o-mini") do
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
case ExLLM.list_models(:openai) do
  {:ok, models} ->
    IO.puts("✓ Model listing successful!")
    IO.puts("Found #{length(models)} models")
    
    # Show first few models
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
  "gpt-4o-mini",
  "gpt-4o", 
  "gpt-3.5-turbo"
]

for model <- test_models do
  IO.write("Testing #{model}: ")
  case ExLLM.chat(:openai, [
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

case ExLLM.stream(:openai, [
  %{role: "user", content: "Count 1, 2, 3"}
], callback, model: "gpt-4o-mini") do
  :ok ->
    IO.puts("\n✓ Streaming successful!")
    
  {:error, reason} ->
    IO.puts("❌ Streaming failed: #{inspect(reason)}")
end

# 6. Test o1 models (reasoning models)
IO.puts("\n6. Testing o1 reasoning models...")
reasoning_models = [
  "o1-mini",
  "o1-preview"
]

for model <- reasoning_models do
  IO.write("Testing #{model}: ")
  case ExLLM.chat(:openai, [
    %{role: "user", content: "What is 2+2?"}
  ], model: model, timeout: 60000) do
    {:ok, response} ->
      IO.puts("✓ Success - #{String.slice(response.content || "", 0..50)}...")
      
    {:error, reason} ->
      IO.puts("❌ Failed - #{inspect(reason)}")
  end
end

IO.puts("\n✅ OpenAI provider tests complete!")