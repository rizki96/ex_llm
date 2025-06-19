#!/usr/bin/env elixir

# Test thinking mode with available models

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

alias ExLLM.Providers.Gemini

# Test models that might support thinking based on Google's announcements
test_models = [
  "gemini-2.0-flash-thinking-exp",
  "gemini-2.0-flash-thinking-exp-1219",
  "gemini-2.0-flash-thinking",
  "gemini-2.0-flash-exp",
  "gemini-exp-1206",
  "gemini-2.0-flash"
]

messages = [
  %{role: "user", content: "What is 25 * 37? Show your thinking process."}
]

IO.puts("\n=== Testing Thinking Mode ===\n")

for model <- test_models do
  IO.puts("Testing model: #{model}")
  
  # Try with thinking mode
  case Gemini.chat(messages, model: model, thinking_mode: true) do
    {:ok, response} ->
      IO.puts("  ✓ Success with thinking_mode")
      IO.puts("  Content: #{String.slice(response.content || "", 0, 100)}...")
      if response.thinking_content do
        IO.puts("  Thinking: #{String.slice(response.thinking_content, 0, 100)}...")
      end
      
    {:error, %{status: 404}} ->
      IO.puts("  ✗ Model not found (404)")
      
    {:error, error} ->
      IO.puts("  ✗ Error: #{inspect(error)}")
  end
  
  IO.puts("")
end

IO.puts("\n=== Testing countTokens API ===\n")

# Test the countTokens API with different content formats
test_content = "Hello, world! This is a test message."

# Test with the expected format from the API docs
request_body = %{
  "contents" => [
    %{
      "parts" => [
        %{"text" => test_content}
      ]
    }
  ]
}

IO.puts("Testing countTokens with proper request format...")
case Gemini.count_tokens(request_body, model: "gemini-2.0-flash") do
  {:ok, result} ->
    IO.puts("  ✓ Success: #{inspect(result)}")
  {:error, error} ->
    IO.puts("  ✗ Error: #{inspect(error)}")
end

# Also test with simple string
IO.puts("\nTesting countTokens with simple string...")
case Gemini.count_tokens(test_content, model: "gemini-2.0-flash") do
  {:ok, result} ->
    IO.puts("  ✓ Success: #{inspect(result)}")
  {:error, error} ->
    IO.puts("  ✗ Error: #{inspect(error)}")
end