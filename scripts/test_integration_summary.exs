#!/usr/bin/env elixir

# Script to run integration tests and provide a summary

IO.puts("\n🧪 Running Integration Tests Summary\n")

# Test files to check
test_files = [
  {"Instructor", "test/ex_llm_instructor_integration_test.exs"},
  {"Session", "test/ex_llm_session_integration_test.exs"},
  {"Context", "test/ex_llm_context_integration_test.exs"},
  {"Gemini Content", "test/ex_llm/adapters/gemini/content_test.exs"},
  {"Gemini Chunk", "test/ex_llm/adapters/gemini/chunk_integration_test.exs"},
  {"LM Studio", "test/ex_llm/adapters/lmstudio_integration_test.exs"},
  {"OpenAI Files", "test/ex_llm/adapters/openai_file_integration_test.exs"}
]

results = Enum.map(test_files, fn {name, file} ->
  IO.write("Testing #{name}... ")
  
  # Run the test with a timeout
  task = Task.async(fn ->
    System.cmd("mix", ["test", file, "--only", "integration", "--exclude", "oauth2"], 
      env: [{"MIX_ENV", "test"}], 
      stderr_to_stdout: true
    )
  end)
  
  case Task.yield(task, 30_000) || Task.shutdown(task) do
    {:ok, {output, exit_code}} ->
      # Parse the output for results
      if String.contains?(output, "Finished in") do
        case Regex.run(~r/(\d+) tests?, (\d+) failures?(?:, (\d+) excluded)?(?:, (\d+) skipped)?/, output) do
          [_match, tests, failures | rest] ->
            excluded = List.first(rest) || "0"
            skipped = List.first(Enum.drop(rest, 1)) || "0"
            
            status = if failures == "0", do: "✅", else: "❌"
            IO.puts("#{status} #{tests} tests, #{failures} failures (#{excluded} excluded, #{skipped} skipped)")
            {name, String.to_integer(tests), String.to_integer(failures)}
          
          _ ->
            IO.puts("⚠️  Could not parse results")
            {name, 0, 0}
        end
      else
        IO.puts("❌ No test output")
        {name, 0, 1}
      end
      
    nil ->
      IO.puts("⏱️  Timeout!")
      {name, 0, 1}
  end
end)

IO.puts("\n📊 Summary:")
IO.puts("=" <> String.duplicate("=", 50))

total_tests = Enum.sum(Enum.map(results, fn {_, tests, _} -> tests end))
total_failures = Enum.sum(Enum.map(results, fn {_, _, failures} -> failures end))

IO.puts("Total: #{total_tests} tests, #{total_failures} failures")

if total_failures > 0 do
  IO.puts("\n❌ Failed test suites:")
  Enum.each(results, fn {name, _, failures} ->
    if failures > 0, do: IO.puts("  - #{name}")
  end)
end

IO.puts("")