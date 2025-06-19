#!/usr/bin/env elixir

# Debug script to investigate Gemini models with thinking/reasoning features

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

alias ExLLM.Providers.Gemini

IO.puts("\n=== Listing Available Gemini Models ===\n")

case Gemini.list_models() do
  {:ok, models} ->
    IO.puts("Found #{length(models)} models:\n")
    
    # Group models by base name
    models_by_base = Enum.group_by(models, fn model ->
      model.id
      |> String.split("-")
      |> Enum.take(2)
      |> Enum.join("-")
    end)
    
    # Display models grouped
    for {base, group} <- models_by_base do
      IO.puts("#{base} variants:")
      for model <- group do
        IO.puts("  - #{model.id}")
        IO.puts("    Context: #{model.context_window}")
        IO.puts("    Capabilities: #{inspect(model.capabilities)}")
        # Gemini models don't have metadata field in Types.Model
      end
      IO.puts("")
    end
    
    # Look for models that might support thinking
    thinking_models = Enum.filter(models, fn model ->
      String.contains?(model.id, ["thinking", "reason", "exp"])
    end)
    
    if length(thinking_models) > 0 do
      IO.puts("\nPotential thinking/reasoning models:")
      for model <- thinking_models do
        IO.puts("  - #{model.id}")
      end
    else
      IO.puts("\nNo models with explicit thinking/reasoning support found.")
    end
    
  {:error, error} ->
    IO.puts("Error listing models: #{inspect(error)}")
end

IO.puts("\n=== Testing Thinking Mode with Different Models ===\n")

# Test models that might support thinking
test_models = [
  "gemini-2.0-flash-exp",
  "gemini-2.0-flash-thinking-exp",
  "gemini-2.0-flash-thinking-exp-1219",
  "gemini-exp-1206",
  "gemini-2.0-flash-thinking-1219"
]

messages = [
  %{role: "user", content: "What is 2+2? Think step by step."}
]

for model <- test_models do
  IO.puts("\nTesting model: #{model}")
  
  # Try with thinking mode enabled
  case Gemini.chat(messages, model: model, thinking_mode: true) do
    {:ok, response} ->
      IO.puts("  ✓ Success with thinking_mode: true")
      IO.puts("  Response: #{String.slice(response.content, 0, 100)}...")
      if response.thinking_content do
        IO.puts("  Thinking content: #{String.slice(response.thinking_content, 0, 100)}...")
      end
      
    {:error, error} ->
      IO.puts("  ✗ Error with thinking_mode: true")
      IO.puts("  Error: #{inspect(error)}")
  end
  
  # Try without thinking mode
  case Gemini.chat(messages, model: model) do
    {:ok, response} ->
      IO.puts("  ✓ Success without thinking_mode")
      IO.puts("  Response: #{String.slice(response.content, 0, 100)}...")
      
    {:error, error} ->
      IO.puts("  ✗ Error without thinking_mode")
      IO.puts("  Error: #{inspect(error)}")
  end
end

IO.puts("\n=== Testing countTokens API ===\n")

# Test the countTokens issue
test_content = "Hello, world! This is a test message for token counting."

IO.puts("Testing token counting with different approaches...")

# Try the raw API
case Gemini.count_tokens(test_content, model: "gemini-2.0-flash-exp") do
  {:ok, count} ->
    IO.puts("  ✓ count_tokens success: #{inspect(count)}")
  {:error, error} ->
    IO.puts("  ✗ count_tokens error: #{inspect(error)}")
end

# Try with different content formats
test_cases = [
  {"String content", test_content},
  {"Message format", [%{role: "user", content: test_content}]},
  {"Content struct", %{parts: [%{text: test_content}]}},
  {"GenerateContentRequest format", %{contents: [%{parts: [%{text: test_content}]}]}}
]

for {desc, content} <- test_cases do
  IO.puts("\nTesting with #{desc}:")
  case Gemini.count_tokens(content, model: "gemini-2.0-flash-exp") do
    {:ok, count} ->
      IO.puts("  ✓ Success: #{inspect(count)}")
    {:error, error} ->
      IO.puts("  ✗ Error: #{inspect(error)}")
  end
end

IO.puts("\n=== Done ===\n")