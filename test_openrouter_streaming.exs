#!/usr/bin/env elixir

# OpenRouter Streaming Test
Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

IO.puts("\n=== OpenRouter Streaming Test ===\n")

# Test direct provider streaming
IO.puts("Testing direct provider streaming...")
case ExLLM.Providers.OpenRouter.stream_chat([
  %{role: "user", content: "Count 1, 2, 3"}
], model: "openai/gpt-4o-mini") do
  {:ok, stream} ->
    IO.puts("✓ Direct streaming successful!")
    IO.write("Response: ")
    
    stream
    |> Enum.take(10)  # Limit to first 10 chunks for testing
    |> Enum.each(fn chunk ->
      if chunk.content, do: IO.write(chunk.content)
    end)
    
    IO.puts("\n")
    
  {:error, reason} ->
    IO.puts("❌ Direct streaming failed: #{inspect(reason)}")
end

# Test high-level streaming 
IO.puts("\nTesting high-level streaming API...")
case ExLLM.stream(:openrouter, [
  %{role: "user", content: "Say hello"}
], fn chunk ->
  if chunk.content, do: IO.write(chunk.content)
end, model: "openai/gpt-4o-mini") do
  :ok ->
    IO.puts("\n✓ High-level streaming successful!")
    
  {:error, reason} ->
    IO.puts("\n❌ High-level streaming failed: #{inspect(reason)}")
end

IO.puts("\n✅ OpenRouter streaming tests complete!")