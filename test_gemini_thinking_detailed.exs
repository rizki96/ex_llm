#!/usr/bin/env elixir

# Test thinking mode in detail

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

alias ExLLM.Providers.Gemini

model = "gemini-2.0-flash-thinking-exp"
messages = [
  %{role: "user", content: "What is 25 * 37? Show your thinking process."}
]

IO.puts("\n=== Testing #{model} ===\n")

# Test with thinking mode enabled
case Gemini.chat(messages, model: model, thinking_mode: true) do
  {:ok, response} ->
    IO.puts("Success!")
    IO.puts("\nFull response structure:")
    IO.inspect(response, pretty: true, limit: :infinity)
    
    IO.puts("\n\nContent:")
    IO.puts(response.content)
    
    if response.thinking_content do
      IO.puts("\n\nThinking content:")
      IO.puts(response.thinking_content)
    else
      IO.puts("\n\nNo thinking content found in response")
    end
    
  {:error, error} ->
    IO.puts("Error:")
    IO.inspect(error, pretty: true)
end

# Now test countTokens
IO.puts("\n\n=== Testing countTokens ===\n")

content = "Hello, world!"

# Try different formats
formats = [
  {"Simple string", content},
  {"Message list", messages},
  {"Contents format", %{"contents" => [%{"parts" => [%{"text" => content}]}]}},
  {"Direct parts", %{"parts" => [%{"text" => content}]}}
]

for {desc, data} <- formats do
  IO.puts("\nTesting #{desc}:")
  case Gemini.count_tokens(data, model: "gemini-2.0-flash") do
    {:ok, result} ->
      IO.puts("  ✓ Success: #{inspect(result)}")
    {:error, error} ->
      IO.puts("  ✗ Error:")
      IO.inspect(error, pretty: true, limit: :infinity)
  end
end