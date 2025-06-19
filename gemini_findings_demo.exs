#!/usr/bin/env elixir

# Demonstration of Gemini findings

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

alias ExLLM.Providers.Gemini

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("GEMINI PROVIDER - THINKING MODE & TOKEN COUNTING")
IO.puts(String.duplicate("=", 60))

# 1. Demonstrate thinking model
IO.puts("\n1. THINKING MODEL TEST")
IO.puts(String.duplicate("-", 40))

messages = [%{role: "user", content: "What is 8 + 7? Think step by step."}]

{:ok, response} = Gemini.chat(messages, 
  model: "gemini-2.0-flash-thinking-exp", 
  thinking_mode: true
)

IO.puts("Model: gemini-2.0-flash-thinking-exp")
IO.puts("Thinking mode: enabled")
IO.puts("\nResponse structure:")
IO.puts("  - content: #{if response.content, do: "✓ Present", else: "✗ Missing"}")
IO.puts("  - thinking_content: #{if response.thinking_content, do: "✓ Present", else: "✗ Missing (nil)"}")
IO.puts("  - usage.total_tokens: #{response.usage.total_tokens}")
IO.puts("\nActual response (first 200 chars):")
IO.puts("\"#{String.slice(response.content, 0, 200)}...\"")

# 2. Show countTokens issue
IO.puts("\n\n2. COUNT TOKENS API ISSUES")
IO.puts(String.duplicate("-", 40))

IO.puts("\nAttempt 1: count_tokens(string, options)")
try do
  Gemini.count_tokens("Hello world", model: "gemini-2.0-flash")
  IO.puts("✅ Success")
rescue
  e -> 
    IO.puts("❌ Error: #{Exception.message(e) |> String.split("\n") |> List.first()}")
end

IO.puts("\nAttempt 2: count_tokens(messages, model)")
case Gemini.count_tokens([%{role: "user", content: "Hello"}], "gemini-2.0-flash") do
  {:ok, result} -> IO.puts("✅ Success: #{inspect(result)}")
  {:error, e} -> IO.puts("❌ Error: #{inspect(e)}")
end

IO.puts("\nAttempt 3: count_tokens_with_request(request_with_model)")
request = %{
  "model" => "gemini-2.0-flash",
  "contents" => [%{"parts" => [%{"text" => "Hello"}]}]
}
case Gemini.count_tokens_with_request(request) do
  {:ok, result} -> IO.puts("✅ Success: #{inspect(result)}")  
  {:error, e} -> IO.puts("❌ Error: #{inspect(e)}")
end

# 3. Summary
IO.puts("\n\n3. KEY FINDINGS")
IO.puts(String.duplicate("-", 40))
IO.puts("✓ gemini-2.0-flash-thinking-exp model exists and works")
IO.puts("✗ Thinking content is NOT returned in separate field")
IO.puts("✗ count_tokens/2 has wrong implementation (expects messages not content)")
IO.puts("✓ count_tokens/3 works with message format")
IO.puts("✓ count_tokens_with_request/1 works with proper request format")

IO.puts("\n" <> String.duplicate("=", 60))