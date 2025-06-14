#!/usr/bin/env elixir

# Script to add context parameter and check_test_requirements! call to tests

defmodule TestUpdater do
  def update_file(file_path) do
    content = File.read!(file_path)
    
    # Pattern to match test definitions
    # Captures: indentation, test name
    pattern = ~r/^(\s*)test\s+"([^"]+)"\s+do\s*$/m
    
    new_content = 
      Regex.replace(pattern, content, fn full_match, indent, test_name ->
        "#{indent}test \"#{test_name}\", context do\n#{indent}  check_test_requirements!(context)"
      end)
    
    if new_content != content do
      File.write!(file_path, new_content)
      IO.puts("Updated #{file_path}")
    else
      IO.puts("No changes needed for #{file_path}")
    end
  end
end

# Get file path from command line argument
case System.argv() do
  [file_path] ->
    TestUpdater.update_file(file_path)
  _ ->
    IO.puts("Usage: elixir add_test_checks.exs <file_path>")
    System.halt(1)
end