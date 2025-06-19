#!/usr/bin/env elixir

# Test running example app with different providers
# Tests the non-interactive demo mode

IO.puts("\n=== Testing Example App (Non-Interactive) ===\n")

providers = [
  {"anthropic", "claude-3-haiku-20240307"},
  {"openai", "gpt-4o-mini"},
  {"gemini", "gemini-1.5-flash"},
  {"groq", "llama-3.3-70b-versatile"},
  {"openrouter", "openai/gpt-4o-mini"}
]

# Test basic chat demo with each provider
Enum.each(providers, fn {provider, model} ->
  IO.puts("\n--- Testing #{provider} with basic demo ---")
  
  env = [
    {"PROVIDER", provider},
    {"MODEL", model}
  ]
  
  # Run the example app with basic-chat demo
  case System.cmd("elixir", ["examples/example_app.exs", "basic-chat"], env: env) do
    {output, 0} ->
      IO.puts("✅ Success!")
      # Show first few lines of output
      output
      |> String.split("\n")
      |> Enum.take(10)
      |> Enum.each(&IO.puts("  #{&1}"))
      
    {error_output, exit_code} ->
      IO.puts("❌ Failed with exit code: #{exit_code}")
      IO.puts("Error: #{error_output}")
  end
end)

IO.puts("\n✅ Example app tests complete!")