#!/usr/bin/env elixir

# Response Capture Example
# 
# This example demonstrates how to use the response capture functionality
# to debug and inspect API responses during development.
#
# Usage:
#   # Enable capture without display
#   EX_LLM_CAPTURE_RESPONSES=true elixir examples/response_capture_example.exs
#
#   # Enable capture with display
#   EX_LLM_CAPTURE_RESPONSES=true EX_LLM_SHOW_CAPTURED=true elixir examples/response_capture_example.exs
#
#   # Then view captures:
#   mix captures.list
#   mix captures.stats

Mix.install([
  {:ex_llm, path: ".", env: :dev}
])

# Configure logging
Application.put_env(:ex_llm, :log_level, :info)

IO.puts("""
ExLLM Response Capture Example
==============================

This example shows how to use response capture for debugging.

Current settings:
- Capture enabled: #{System.get_env("EX_LLM_CAPTURE_RESPONSES") == "true"}
- Display enabled: #{System.get_env("EX_LLM_SHOW_CAPTURED") == "true"}
""")

# Check if we have an API key configured
provider = :openai
api_key = System.get_env("OPENAI_API_KEY")

if api_key do
  IO.puts("\nUsing OpenAI provider...")
  
  # Simple chat example
  messages = [
    %{role: "system", content: "You are a helpful assistant."},
    %{role: "user", content: "What is 2 + 2?"}
  ]
  
  IO.puts("\nSending chat request...")
  
  case ExLLM.chat(messages, provider: provider, model: "gpt-4.1-nano") do
    {:ok, response} ->
      IO.puts("\n✅ Success!")
      IO.puts("Response: #{response.content}")
      IO.puts("Tokens: #{response.usage.input_tokens} in / #{response.usage.output_tokens} out")
      IO.puts("Cost: $#{Float.round(response.cost, 4)}")
      
      if System.get_env("EX_LLM_CAPTURE_RESPONSES") == "true" do
        IO.puts("\n📸 Response captured! View with:")
        IO.puts("  mix captures.list")
        IO.puts("  mix captures.list --provider openai")
      end
      
    {:error, reason} ->
      IO.puts("\n❌ Error: #{inspect(reason)}")
  end
  
  # Streaming example
  if System.get_env("EX_LLM_SHOW_CAPTURED") == "true" do
    IO.puts("\n\nTrying streaming request...")
    
    stream_callback = fn chunk ->
      # Just collect chunks, don't print
      :ok
    end
    
    case ExLLM.stream(messages, stream_callback, provider: provider, model: "gpt-4.1-nano") do
      {:ok, _response} ->
        IO.puts("✅ Streaming completed!")
        
      {:error, reason} ->
        IO.puts("❌ Streaming error: #{inspect(reason)}")
    end
  end
  
else
  IO.puts("""
  
  ⚠️  No OpenAI API key found!
  
  To run this example with real API calls:
  1. Set your OpenAI API key:
     export OPENAI_API_KEY="your-key-here"
  
  2. Enable response capture:
     export EX_LLM_CAPTURE_RESPONSES=true
     export EX_LLM_SHOW_CAPTURED=true  # Optional: display in console
  
  3. Run this example:
     elixir examples/response_capture_example.exs
  
  4. View captured responses:
     mix captures.list
     mix captures.show <timestamp>
  """)
end

IO.puts("\n\n✨ Example complete!")