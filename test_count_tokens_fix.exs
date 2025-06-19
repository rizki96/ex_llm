#!/usr/bin/env elixir

# Test the count_tokens issue and verify fix

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

alias ExLLM.Providers.Gemini

IO.puts("\n=== Testing Current count_tokens Implementation ===\n")

# Test case 1: Simple string (this should fail)
IO.puts("Test 1: Simple string")
result = try do
  Gemini.count_tokens("Hello, world!", model: "gemini-2.0-flash")
rescue
  e -> {:error, Exception.message(e)}
end
IO.inspect(result)

# Test case 2: Message list (this might work)
IO.puts("\nTest 2: Message list")
messages = [%{role: "user", content: "Hello, world!"}]
result = try do
  Gemini.count_tokens(messages, "gemini-2.0-flash")
rescue
  e -> {:error, Exception.message(e)}
end
IO.inspect(result)

# Test case 3: Using the request format directly
IO.puts("\nTest 3: Direct request format")
request = %{
  "contents" => [
    %{
      "parts" => [
        %{"text" => "Hello, world!"}
      ]
    }
  ]
}
result = try do
  Gemini.count_tokens_with_request(request)
rescue
  e -> {:error, Exception.message(e)}
end
IO.inspect(result)

IO.puts("\n=== Summary ===")
IO.puts("The issue is that count_tokens/2 expects (content, options) but count_tokens/3 expects (messages, model, options)")
IO.puts("This causes a mismatch when the public API calls it with a string.")