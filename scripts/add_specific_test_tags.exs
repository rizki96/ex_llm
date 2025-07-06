#!/usr/bin/env elixir

# Script to add specific missing test tags to identified files

defmodule SpecificTestTagger do
  @moduledoc """
  Adds specific missing tags to identified test files.
  """

  # Define specific files and their missing tags
  @files_to_tag %{
    "test/ex_llm/providers/mock_test.exs" => [":mock", "provider:mock"],
    "test/ex_llm/embedding_test.exs" => ["capability:embeddings"],
    "test/ex_llm/function_calling_test.exs" => ["capability:function_calling"],
    "test/ex_llm/core/vision_test.exs" => ["capability:vision"],
    "test/integration/ex_llm_api_integration_test.exs" => [],  # Already has moduletag
    "test/integration/batch_processing_comprehensive_test.exs" => [":integration", ":comprehensive"],
    "test/integration/fine_tuning_comprehensive_test.exs" => [":integration", ":comprehensive"],
    "test/integration/knowledge_base_comprehensive_test.exs" => [":integration", ":comprehensive"],
    "test/integration/vector_store_comprehensive_test.exs" => [":integration", ":comprehensive"],
    "test/integration/assistants_comprehensive_test.exs" => [":integration", ":comprehensive"],
    "test/integration/context_caching_comprehensive_test.exs" => [":integration", ":comprehensive"],
    "test/ex_llm/response_capture_test.exs" => [":unit"],
    "test/ex_llm/pipeline/request_test.exs" => [":unit"],
    "test/ex_llm/providers/anthropic/pipeline_plugs_test.exs" => ["provider:anthropic", ":unit"],
    "test/ex_llm/providers/gemini/pipeline_plugs_test.exs" => ["provider:gemini", ":unit"],
    "test/ex_llm/providers/groq/pipeline_plugs_test.exs" => ["provider:groq", ":unit"],
    "test/ex_llm/providers/ollama/pipeline_plugs_test.exs" => ["provider:ollama", ":unit"],
    "test/ex_llm/providers/openai/pipeline_plugs_test.exs" => ["provider:openai", ":unit"]
  }

  def run do
    IO.puts("Adding specific missing test tags...\n")
    
    Enum.each(@files_to_tag, fn {file, tags} ->
      if File.exists?(file) && tags != [] do
        add_tags_to_file(file, tags)
      end
    end)
    
    IO.puts("\nSpecific test tagging complete!")
  end

  defp add_tags_to_file(file, tags) do
    content = File.read!(file)
    
    # Check which tags are actually missing
    missing_tags = Enum.filter(tags, fn tag ->
      !has_tag?(content, tag)
    end)
    
    if missing_tags != [] do
      updated_content = add_tags_to_content(content, missing_tags)
      File.write!(file, updated_content)
      IO.puts("✓ Updated #{file}")
      IO.puts("  Added tags: #{inspect(missing_tags)}")
    else
      IO.puts("✓ #{file} already has all required tags")
    end
  end

  defp has_tag?(content, tag) do
    formatted_tag = format_tag(tag)
    String.contains?(content, "@tag #{formatted_tag}") ||
    String.contains?(content, "@moduletag #{formatted_tag}")
  end

  defp add_tags_to_content(content, tags) do
    lines = String.split(content, "\n")
    
    # Find the best insertion point
    insertion_index = find_insertion_point(lines)
    
    if insertion_index do
      {before, after_line} = Enum.split(lines, insertion_index)
      
      # Create tag lines
      tag_lines = Enum.map(tags, fn tag ->
        "  @moduletag #{format_tag(tag)}"
      end)
      
      # Reassemble with tags
      new_lines = before ++ tag_lines ++ after_line
      Enum.join(new_lines, "\n")
    else
      content
    end
  end

  defp find_insertion_point(lines) do
    # Find the line after "use ExUnit.Case"
    use_index = Enum.find_index(lines, fn line ->
      String.contains?(line, "use ExUnit.Case")
    end)
    
    if use_index do
      # Check if there's already a blank line after
      if Enum.at(lines, use_index + 1, "") == "" do
        use_index + 2
      else
        use_index + 1
      end
    else
      # Find the line after defmodule
      defmodule_index = Enum.find_index(lines, fn line ->
        String.starts_with?(String.trim(line), "defmodule")
      end)
      
      if defmodule_index do
        defmodule_index + 1
      else
        nil
      end
    end
  end

  defp format_tag(tag) do
    cond do
      String.starts_with?(tag, ":") ->
        tag
      
      String.contains?(tag, ":") ->
        # Handle capability:feature format
        ":#{tag}"
      
      true ->
        ":#{tag}"
    end
  end
end

# Run the script
SpecificTestTagger.run()