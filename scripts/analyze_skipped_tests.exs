#!/usr/bin/env elixir

# Script to analyze all tests with @tag :skip and generate migration recommendations

defmodule TestAnalyzer do
  def run do
    IO.puts("Analyzing skipped tests...\n")
    
    # Find all test files
    test_files = Path.wildcard("test/**/*_test.exs")
    
    skipped_tests = 
      test_files
      |> Enum.flat_map(&analyze_file/1)
      |> Enum.sort_by(& &1.file)
    
    IO.puts("Found #{length(skipped_tests)} skipped tests\n")
    
    # Group by reason patterns
    grouped = group_by_pattern(skipped_tests)
    
    # Print analysis
    print_analysis(grouped)
    
    # Generate CSV for migration tracking
    generate_csv(skipped_tests)
  end
  
  defp analyze_file(file) do
    content = File.read!(file)
    lines = String.split(content, "\n")
    
    # Find all @tag :skip lines first
    skip_indices = 
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} -> String.contains?(line, "@tag :skip") end)
      |> Enum.map(fn {_, idx} -> idx end)
    
    # For each skip tag, analyze the surrounding context
    skip_indices
    |> Enum.map(fn line_num ->
      # Get surrounding lines (5 before, 5 after)
      start_idx = max(0, line_num - 6)
      end_idx = min(length(lines) - 1, line_num + 4)
      
      context_lines = 
        lines
        |> Enum.slice(start_idx..end_idx)
        |> Enum.with_index(start_idx + 1)
      
      # Find test name (looking forward from skip tag)
      test_line = 
        context_lines
        |> Enum.drop_while(fn {_, idx} -> idx < line_num end)
        |> Enum.find(fn {line, _} -> String.contains?(line, "test \"") end)
      
      test_name = extract_test_name(test_line)
      
      # Find comments (looking backward from skip tag)
      comment_lines = 
        context_lines
        |> Enum.take_while(fn {_, idx} -> idx <= line_num end)
        |> Enum.filter(fn {line, _} -> String.contains?(line, "#") end)
        |> Enum.map(fn {line, _} -> String.trim(line) end)
        |> Enum.join(" ")
      
      %{
        file: file,
        line: line_num,
        test_name: test_name,
        comments: comment_lines,
        provider: infer_provider(file)
      }
    end)
  end
  
  defp extract_test_name(nil), do: "Unknown test"
  defp extract_test_name({line, _}) do
    case Regex.run(~r/test\s+"([^"]+)"/, line) do
      [_, name] -> name
      _ -> "Unknown test"
    end
  end
  
  defp infer_provider(file) do
    cond do
      String.contains?(file, "anthropic") -> :anthropic
      String.contains?(file, "openai") -> :openai
      String.contains?(file, "gemini") -> :gemini
      String.contains?(file, "ollama") -> :ollama
      String.contains?(file, "lmstudio") -> :lmstudio
      String.contains?(file, "openrouter") -> :openrouter
      String.contains?(file, "mistral") -> :mistral
      String.contains?(file, "perplexity") -> :perplexity
      String.contains?(file, "groq") -> :groq
      String.contains?(file, "xai") -> :xai
      true -> :unknown
    end
  end
  
  defp group_by_pattern(tests) do
    tests
    |> Enum.group_by(fn test ->
      cond do
        String.contains?(test.comments, ["API key", "api key", "API_KEY"]) -> :requires_api_key
        String.contains?(test.comments, ["OAuth", "oauth", "token"]) -> :requires_oauth
        String.contains?(test.comments, ["running", "service", "localhost"]) -> :requires_service
        String.contains?(test.comments, ["mock", "Mock", "stub"]) -> :requires_mock
        String.contains?(test.comments, ["network", "Network"]) -> :network_related
        String.contains?(test.comments, ["not implemented", "TODO"]) -> :not_implemented
        String.contains?(test.comments, ["quota", "rate limit"]) -> :quota_sensitive
        String.contains?(test.comments, ["corpus", "document", "tuned model"]) -> :requires_resource
        true -> :other
      end
    end)
  end
  
  defp print_analysis(grouped) do
    IO.puts("## Analysis by Pattern\n")
    
    Enum.each(grouped, fn {pattern, tests} ->
      IO.puts("### #{pattern} (#{length(tests)} tests)")
      
      # Show first 3 examples
      tests
      |> Enum.take(3)
      |> Enum.each(fn test ->
        IO.puts("  - #{Path.relative_to_cwd(test.file)}:#{test.line}")
        IO.puts("    Test: #{test.test_name}")
        if test.comments != "" do
          IO.puts("    Comment: #{test.comments}")
        end
      end)
      
      if length(tests) > 3 do
        IO.puts("  ... and #{length(tests) - 3} more")
      end
      
      IO.puts("")
    end)
  end
  
  defp generate_csv(tests) do
    csv_path = "test_migration_data.csv"
    
    header = "File,Line,Test Name,Provider,Comments,Suggested Tags\n"
    
    rows = Enum.map(tests, fn test ->
      tags = suggest_tags(test)
      escaped_test_name = String.replace(test.test_name, "\"", "\"\"")
      escaped_comments = String.replace(test.comments, "\"", "\"\"")
      
      [
        test.file,
        to_string(test.line),
        "\"#{escaped_test_name}\"",
        to_string(test.provider),
        "\"#{escaped_comments}\"",
        Enum.join(tags, " ")
      ]
      |> Enum.join(",")
    end)
    
    File.write!(csv_path, header <> Enum.join(rows, "\n"))
    IO.puts("\nCSV file generated: #{csv_path}")
  end
  
  defp suggest_tags(test) do
    tags = []
    
    # Add provider tag
    tags = if test.provider != :unknown, do: ["provider:#{test.provider}" | tags], else: tags
    
    # Analyze comments for requirements
    cond do
      String.contains?(test.comments, ["API key", "api key", "API_KEY"]) ->
        [":requires_api_key" | tags]
      
      String.contains?(test.comments, ["OAuth", "oauth", "token"]) ->
        [":requires_oauth" | tags]
      
      String.contains?(test.comments, ["running", "service", "localhost"]) ->
        service = infer_service(test)
        [":requires_service", "requires_service:#{service}" | tags]
      
      String.contains?(test.comments, ["mock", "Mock", "stub"]) ->
        [":unit", ":requires_mock" | tags]
      
      String.contains?(test.comments, ["network", "Network"]) ->
        [":unit", ":requires_mock" | tags]
      
      String.contains?(test.comments, ["corpus", "document", "tuned model"]) ->
        resource = infer_resource(test.comments)
        [":integration", ":requires_resource", "requires_resource:#{resource}" | tags]
      
      true ->
        tags
    end
  end
  
  defp infer_service(test) do
    cond do
      test.provider == :ollama -> :ollama
      test.provider == :lmstudio -> :lmstudio
      true -> :unknown
    end
  end
  
  defp infer_resource(comments) do
    cond do
      String.contains?(comments, "corpus") -> :corpus
      String.contains?(comments, "document") -> :document
      String.contains?(comments, "tuned model") -> :tuned_model
      true -> :unknown
    end
  end
end

TestAnalyzer.run()