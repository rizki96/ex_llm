#!/usr/bin/env elixir

# Start the application
Application.ensure_all_started(:ex_llm)
Process.sleep(100)

alias ExLLM.Adapters.Bumblebee

IO.puts("=== Testing Bumblebee Model Discovery ===")

case Bumblebee.list_models() do
  {:ok, models} ->
    IO.puts("Found #{length(models)} total models:")
    
    Enum.each(models, fn model ->
      IO.puts("")
      IO.puts("• #{model.id}")
      IO.puts("  Name: #{model.name}")
      IO.puts("  Description: #{model.description}")
      IO.puts("  Context Window: #{model.context_window}")
      IO.puts("  Features: #{inspect(model.capabilities.features)}")
    end)
    
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("")
IO.puts("=== Checking Configuration ===")
IO.puts("Bumblebee configured: #{Bumblebee.configured?()}")
IO.puts("Default model: #{Bumblebee.default_model()}")