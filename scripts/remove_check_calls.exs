#!/usr/bin/env elixir

# Script to remove check_test_requirements! calls

defmodule CheckRemover do
  def remove_from_file(file_path) do
    content = File.read!(file_path)
    
    # Remove lines that contain check_test_requirements!
    new_content = 
      content
      |> String.split("\n")
      |> Enum.reject(fn line ->
        String.contains?(line, "check_test_requirements!(context)")
      end)
      |> Enum.join("\n")
    
    # Also fix any double newlines created
    new_content = String.replace(new_content, ~r/\n\n\n+/, "\n\n")
    
    File.write!(file_path, new_content)
    IO.puts("Removed check calls from #{file_path}")
  end
end

# Get file path from command line argument
case System.argv() do
  [file_path] ->
    CheckRemover.remove_from_file(file_path)
  _ ->
    IO.puts("Usage: elixir remove_check_calls.exs <file_path>")
    System.halt(1)
end