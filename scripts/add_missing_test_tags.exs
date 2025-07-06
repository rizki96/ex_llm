#!/usr/bin/env elixir

# Script to add missing test tags to ExLLM test files

defmodule TestTagger do
  @moduledoc """
  Adds missing tags to test files based on their content and location.
  """

  def run do
    IO.puts("Adding missing test tags to ExLLM test files...\n")
    
    test_files = find_test_files()
    
    Enum.each(test_files, fn file ->
      process_file(file)
    end)
    
    IO.puts("\nTest tagging complete!")
  end

  defp find_test_files do
    Path.wildcard("test/**/*_test.exs")
    |> Enum.sort()
  end

  defp process_file(file) do
    content = File.read!(file)
    original_content = content
    
    # Detect what tags should be added
    tags_to_add = detect_missing_tags(file, content)
    
    if tags_to_add != [] do
      # Add the tags after the module definition
      updated_content = add_tags_to_content(content, tags_to_add)
      
      if updated_content != original_content do
        File.write!(file, updated_content)
        IO.puts("✓ Updated #{file}")
        IO.puts("  Added tags: #{inspect(tags_to_add)}")
      end
    end
  end

  defp detect_missing_tags(file, content) do
    tags = []
    
    # Check for mock usage
    if uses_mock?(content) && !has_tag?(content, ":mock") do
      tags = tags ++ [":mock"]
    end
    
    # Check for specific capabilities
    capability = detect_capability(file, content)
    if capability && !has_tag?(content, "capability:#{capability}") do
      tags = tags ++ ["capability:#{capability}"]
    end
    
    # Check for provider-specific tests
    provider = detect_provider(file, content)
    if provider && !has_tag?(content, "provider:#{provider}") do
      tags = tags ++ ["provider:#{provider}"]
    end
    
    # Check for test type
    test_type = detect_test_type(file, content)
    if test_type && !has_tag?(content, test_type) do
      tags = tags ++ [test_type]
    end
    
    tags
  end

  defp uses_mock?(content) do
    String.contains?(content, "Mock.set_response") ||
    String.contains?(content, "Mock.set_error") ||
    String.contains?(content, "Mock.reset") ||
    String.contains?(content, "ExLLM.Providers.Mock")
  end

  defp has_tag?(content, tag) do
    String.contains?(content, "@tag #{tag}") ||
    String.contains?(content, "@tag :#{tag}") ||
    String.contains?(content, "@moduletag #{tag}") ||
    String.contains?(content, "@moduletag :#{tag}")
  end

  defp detect_capability(file, content) do
    cond do
      String.contains?(file, "embedding") || String.contains?(content, "embeddings") ->
        "embeddings"
      
      String.contains?(file, "function_calling") || String.contains?(content, "function_call") ->
        "function_calling"
      
      String.contains?(file, "vision") || String.contains?(content, "vision") ->
        "vision"
      
      String.contains?(file, "streaming") || String.contains?(content, "stream") ->
        "streaming"
      
      String.contains?(content, "list_models") ->
        "list_models"
      
      String.contains?(content, "cost_tracking") || String.contains?(content, "usage") ->
        "cost_tracking"
      
      String.contains?(content, "json_mode") || String.contains?(content, "response_format") ->
        "json_mode"
      
      String.contains?(content, "system_prompt") ->
        "system_prompt"
      
      String.contains?(content, "temperature") ->
        "temperature"
      
      true ->
        nil
    end
  end

  defp detect_provider(file, content) do
    # Check file path first
    provider_from_path = 
      cond do
        String.contains?(file, "/anthropic/") -> "anthropic"
        String.contains?(file, "/openai/") -> "openai"
        String.contains?(file, "/gemini/") -> "gemini"
        String.contains?(file, "/groq/") -> "groq"
        String.contains?(file, "/ollama/") -> "ollama"
        String.contains?(file, "/mistral/") -> "mistral"
        String.contains?(file, "/xai/") -> "xai"
        String.contains?(file, "/perplexity/") -> "perplexity"
        String.contains?(file, "/openrouter/") -> "openrouter"
        String.contains?(file, "/lmstudio/") -> "lmstudio"
        String.contains?(file, "/bumblebee/") -> "bumblebee"
        String.contains?(file, "/mock") -> "mock"
        true -> nil
      end
    
    # If not in path, check content
    provider_from_path || detect_provider_from_content(content)
  end

  defp detect_provider_from_content(content) do
    providers = [
      "anthropic", "openai", "gemini", "groq", "ollama",
      "mistral", "xai", "perplexity", "openrouter", "lmstudio", "bumblebee"
    ]
    
    Enum.find(providers, fn provider ->
      String.contains?(content, ":#{provider}") ||
      String.contains?(content, "provider: :#{provider}")
    end)
  end

  defp detect_test_type(file, content) do
    cond do
      String.contains?(file, "/unit/") || 
        (String.contains?(content, "use ExUnit.Case") && !String.contains?(file, "/integration/")) ->
        ":unit"
      
      String.contains?(file, "/integration/") ->
        ":integration"
      
      String.contains?(file, "comprehensive_test.exs") ->
        ":comprehensive"
      
      String.contains?(content, "performance") || String.contains?(file, "performance") ->
        ":performance"
      
      String.contains?(content, "@moduletag :oauth2") ->
        nil  # Already properly tagged
      
      true ->
        nil
    end
  end

  defp add_tags_to_content(content, tags) do
    lines = String.split(content, "\n")
    
    # Find where to insert tags (after defmodule line)
    {before_module, after_module} = 
      Enum.split_while(lines, fn line ->
        !String.starts_with?(String.trim(line), "defmodule")
      end)
    
    case after_module do
      [] ->
        # No module found, return original
        content
      
      [module_line | rest] ->
        # Check if use ExUnit.Case is on next line
        case rest do
          [use_line | remaining] when String.contains?(use_line, "use ExUnit.Case") ->
            # Insert tags after use ExUnit.Case
            tag_lines = Enum.map(tags, fn tag ->
              "  @moduletag #{format_tag(tag)}"
            end)
            
            new_lines = before_module ++ [module_line, use_line, ""] ++ tag_lines ++ [""] ++ remaining
            Enum.join(new_lines, "\n")
          
          _ ->
            # Insert tags after module line
            tag_lines = Enum.map(tags, fn tag ->
              "  @moduletag #{format_tag(tag)}"
            end)
            
            new_lines = before_module ++ [module_line, ""] ++ tag_lines ++ [""] ++ rest
            Enum.join(new_lines, "\n")
        end
    end
  end

  defp format_tag(tag) do
    if String.starts_with?(tag, ":") do
      tag
    else
      ":#{tag}"
    end
  end
end

# Run the script
TestTagger.run()