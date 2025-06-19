System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")
Application.put_env(:ex_llm, :debug_test_cache, true)

# Set test context
test_context = %{
  module: DebugCacheFormat,
  test_name: "debug_cache_format",
  test: "debug_cache_format",
  tags: %{live_api: true, provider: :anthropic}
}
ExLLM.Testing.TestCacheDetector.set_test_context(test_context)

alias ExLLM.Providers.Shared.HTTPClient

config = %{api_key: System.get_env("ANTHROPIC_API_KEY")}
headers = [
  {"x-api-key", config.api_key},
  {"anthropic-version", "2023-06-01"},
  {"Content-Type", "application/json"}
]

IO.puts("Debug Cache Format")
IO.puts("=" <> String.duplicate("=", 50))

# Make a GET request
IO.puts("\nGET request to /v1/models:")
result = HTTPClient.get_json("https://api.anthropic.com/v1/models", headers, provider: :anthropic)

case result do
  {:ok, response} ->
    IO.puts("Response type: #{inspect(Map.keys(response) |> Enum.sort())}")
    
    if Map.has_key?(response, :status) do
      IO.puts("Has :status key")
    end
    
    if Map.has_key?(response, "status") do
      IO.puts("Has 'status' key")  
    end
    
    # Check for body
    body = Map.get(response, :body) || Map.get(response, "body") || response
    
    if is_map(body) and Map.has_key?(body, "metadata") do
      metadata = Map.get(body, "metadata")
      IO.puts("Body has metadata: #{inspect(metadata)}")
    end
    
    if Map.has_key?(response, "metadata") do
      metadata = Map.get(response, "metadata")
      IO.puts("Response has metadata: #{inspect(metadata)}")
    end
    
  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end