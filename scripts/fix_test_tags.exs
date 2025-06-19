#!/usr/bin/env elixir

# Script to add missing tags to test files

defmodule TestTagFixer do
  @moduledoc """
  Adds missing tags to test files based on test content and names.
  """

  def fix_tags(file_path) do
    content = File.read!(file_path)
    lines = String.split(content, "\n")
    
    # Check if file needs specific tags
    needs_vision_tag = Regex.match?(~r/vision|image|multimodal/i, content) &&
                      !String.contains?(content, "@tag :vision")
    
    needs_streaming_tag = Regex.match?(~r/stream|streaming/i, content) &&
                         !String.contains?(content, "@tag :streaming")
    
    needs_function_tag = Regex.match?(~r/function_calling|tool|tools/i, content) &&
                        !String.contains?(content, "@tag :function_calling")
    
    needs_embedding_tag = Regex.match?(~r/embedding|embed/i, content) &&
                         !String.contains?(content, "@tag :embedding")
    
    if needs_vision_tag || needs_streaming_tag || needs_function_tag || needs_embedding_tag do
      IO.puts("Fixing tags in #{file_path}")
      fixed_lines = add_tags_to_tests(lines, file_path)
      File.write!(file_path, Enum.join(fixed_lines, "\n"))
    end
  end
  
  defp add_tags_to_tests(lines, _file_path) do
    Enum.map_reduce(lines, false, fn line, in_test ->
      cond do
        # Start of a test
        String.match?(line, ~r/^\s*test\s+".*vision.*"/) && !in_test ->
          {"    @tag :vision\n" <> line, true}
          
        String.match?(line, ~r/^\s*test\s+".*stream.*"/) && !in_test ->
          {"    @tag :streaming\n" <> line, true}
          
        String.match?(line, ~r/^\s*test\s+".*function.*|.*tool.*"/) && !in_test ->
          {"    @tag :function_calling\n" <> line, true}
          
        String.match?(line, ~r/^\s*test\s+".*embed.*"/) && !in_test ->
          {"    @tag :embedding\n" <> line, true}
          
        # End of test block
        String.match?(line, ~r/^\s*end\s*$/) && in_test ->
          {line, false}
          
        true ->
          {line, in_test}
      end
    end)
    |> elem(0)
  end
end

# Find all test files
{output, 0} = System.cmd("find", ["test", "-name", "*.exs", "-type", "f"])
test_files = output |> String.trim() |> String.split("\n")

# Process each test file
Enum.each(test_files, fn file ->
  if file != "" && !String.contains?(file, "test_helper.exs") do
    TestTagFixer.fix_tags(file)
  end
end)

IO.puts("Tag fixing complete!")