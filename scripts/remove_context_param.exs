#!/usr/bin/env elixir

# Script to remove context parameter from tests

defmodule ContextRemover do
  def remove_from_file(file_path) do
    content = File.read!(file_path)
    
    # Pattern to match test with context parameter
    pattern = ~r/test\s+"([^"]+)",\s*context\s+do/
    
    new_content = 
      Regex.replace(pattern, content, fn _full_match, test_name ->
        "test \"#{test_name}\" do"
      end)
    
    if new_content != content do
      File.write!(file_path, new_content)
      IO.puts("Removed context parameters from #{file_path}")
    else
      IO.puts("No changes needed for #{file_path}")
    end
  end
end

# Get file path from command line argument
case System.argv() do
  [file_path] ->
    ContextRemover.remove_from_file(file_path)
  _ ->
    IO.puts("Usage: elixir remove_context_param.exs <file_path>")
    System.halt(1)
end