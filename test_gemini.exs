#!/usr/bin/env elixir

# Test Gemini provider directly
Mix.install([{:ex_llm, path: "."}])

# Enable debug logging
Application.put_env(:ex_llm, :log_level, :debug)

# Test basic chat
IO.puts("Testing Gemini provider...")

messages = [%{role: "user", content: "Hello! What's 2+2?"}]

case ExLLM.chat(:gemini, messages) do
  {:ok, response} ->
    IO.puts("Success!")
    IO.inspect(response, label: "Response")
    
  {:error, error} ->
    IO.puts("Error!")
    IO.inspect(error, label: "Error")
    
    # Try to get more details
    Process.info(self(), :messages)
    |> elem(1)
    |> IO.inspect(label: "Process messages")
end