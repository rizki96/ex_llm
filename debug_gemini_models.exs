#!/usr/bin/env elixir

# Simple script to list Gemini models

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

alias ExLLM.Providers.Gemini

case Gemini.list_models() do
  {:ok, models} ->
    IO.puts("\nFound #{length(models)} models:\n")
    
    # Sort and display all models
    models
    |> Enum.sort_by(& &1.id)
    |> Enum.each(fn model ->
      IO.puts("#{model.id}")
      IO.puts("  Context: #{model.context_window}")
      if String.contains?(model.id, ["thinking", "exp"]) do
        IO.puts("  *** Potential thinking/reasoning model ***")
      end
      IO.puts("")
    end)
    
  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end