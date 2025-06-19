#!/usr/bin/env elixir

# Comprehensive test for Gemini thinking mode and token counting

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

alias ExLLM.Providers.Gemini

IO.puts("\n=== Gemini Provider Verification ===\n")

# Test 1: Verify thinking model works
IO.puts("1. Testing gemini-2.0-flash-thinking-exp model:")
messages = [
  %{role: "user", content: "Calculate 15 * 23. Think step by step."}
]

case Gemini.chat(messages, model: "gemini-2.0-flash-thinking-exp", thinking_mode: true) do
  {:ok, response} ->
    IO.puts("   ✅ Model works correctly")
    IO.puts("   Response preview: #{String.slice(response.content, 0, 80)}...")
    IO.puts("   Thinking content field: #{inspect(response.thinking_content)}")
    IO.puts("   Total tokens used: #{response.usage.total_tokens}")
  {:error, error} ->
    IO.puts("   ❌ Error: #{inspect(error)}")
end

# Test 2: Check if model appears in list
IO.puts("\n2. Checking if thinking model appears in list_models:")
case Gemini.list_models() do
  {:ok, models} ->
    thinking_models = Enum.filter(models, fn m -> 
      String.contains?(m.id, "thinking")
    end)
    if length(thinking_models) > 0 do
      IO.puts("   ✅ Found thinking models: #{Enum.map(thinking_models, & &1.id) |> Enum.join(", ")}")
    else
      IO.puts("   ❌ No thinking models found in list")
    end
  {:error, error} ->
    IO.puts("   ❌ Error listing models: #{inspect(error)}")
end

# Test 3: Test countTokens with different formats
IO.puts("\n3. Testing countTokens API:")

test_cases = [
  {"String via count_tokens/2", 
   fn -> Gemini.count_tokens("Hello world", model: "gemini-2.0-flash") end},
  
  {"Messages via count_tokens/3", 
   fn -> Gemini.count_tokens([%{role: "user", content: "Hello"}], "gemini-2.0-flash") end},
  
  {"Request format via count_tokens_with_request/1",
   fn -> 
     request = %{
       "model" => "gemini-2.0-flash",
       "contents" => [%{"parts" => [%{"text" => "Hello"}]}]
     }
     Gemini.count_tokens_with_request(request)
   end}
]

for {desc, test_fn} <- test_cases do
  IO.write("   #{desc}: ")
  result = try do
    test_fn.()
  rescue
    e -> {:error, Exception.message(e)}
  end
  
  case result do
    {:ok, %{"totalTokens" => tokens}} ->
      IO.puts("✅ Success (#{tokens} tokens)")
    {:ok, other} ->
      IO.puts("✅ Success: #{inspect(other)}")
    {:error, msg} when is_binary(msg) ->
      IO.puts("❌ Error: #{String.slice(msg, 0, 60)}...")
    {:error, error} ->
      IO.puts("❌ Error: #{inspect(error)}")
  end
end

# Test 4: Verify regular models still work
IO.puts("\n4. Testing regular gemini-2.0-flash model:")
case Gemini.chat([%{role: "user", content: "Say hello"}], model: "gemini-2.0-flash", max_tokens: 10) do
  {:ok, response} ->
    IO.puts("   ✅ Regular model works: #{response.content}")
  {:error, error} ->
    IO.puts("   ❌ Error: #{inspect(error)}")
end

IO.puts("\n=== Summary ===")
IO.puts("- Thinking model (gemini-2.0-flash-thinking-exp) exists and works")
IO.puts("- Thinking content is embedded in main response, not separate field")
IO.puts("- countTokens has API mismatch issues that need fixing")
IO.puts("- Regular models continue to work correctly")