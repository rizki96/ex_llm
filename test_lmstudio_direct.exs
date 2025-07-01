#!/usr/bin/env elixir

# Direct test of LM Studio
IO.puts("Testing LM Studio connection...")

# Start httpc
:inets.start()

# First check if server is reachable
case :httpc.request(:get, {~c"http://localhost:1234/v1/models", []}, [], []) do
  {:ok, {{_, 200, _}, _, body}} ->
    IO.puts("✅ LM Studio server is running")
    IO.puts("Response: #{inspect(body)}")
    
  {:ok, {{_, status, _}, _, body}} ->
    IO.puts("❌ LM Studio returned status: #{status}")
    IO.puts("Response: #{inspect(body)}")
    
  {:error, {:failed_connect, _}} ->
    IO.puts("❌ Cannot connect to LM Studio on localhost:1234")
    
  {:error, reason} ->
    IO.puts("❌ Error: #{inspect(reason)}")
end

# Now test with ExLLM
IO.puts("\nTesting with ExLLM...")

# Change to examples directory for the test
File.cd!("examples")

# Run the provider test
System.cmd("elixir", ["example_app.exs", "basic-chat", "Hello! What's 2+2?"], 
  env: [{"PROVIDER", "lmstudio"}],
  into: IO.stream(:stdio, :line)
)