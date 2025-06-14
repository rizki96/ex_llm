#!/usr/bin/env elixir

# Script to remove @tag :skip lines from test files

defmodule SkipTagRemover do
  def remove_from_file(file_path) do
    content = File.read!(file_path)
    
    # Remove lines that only contain @tag :skip (with optional whitespace)
    new_content = 
      content
      |> String.split("\n")
      |> Enum.reject(fn line ->
        String.trim(line) == "@tag :skip"
      end)
      |> Enum.join("\n")
    
    File.write!(file_path, new_content)
    IO.puts("Removed @tag :skip from #{file_path}")
  end
end

# Get file path from command line argument
case System.argv() do
  [file_path] ->
    SkipTagRemover.remove_from_file(file_path)
  _ ->
    IO.puts("Usage: elixir remove_skip_tags.exs <file_path>")
    System.halt(1)
end