System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")

alias ExLLM.Providers.Anthropic

# Set test context
test_context = %{
  module: TestAnthropicRaw,
  test_name: "test_anthropic_raw",
  test: "test_anthropic_raw",
  tags: %{live_api: true, provider: :anthropic}
}
ExLLM.Testing.TestCacheDetector.set_test_context(test_context)

IO.puts("Testing Anthropic Raw API Responses")
IO.puts("=" <> String.duplicate("=", 50))

# Test the raw API call that list_models uses internally
config = %{api_key: System.get_env("ANTHROPIC_API_KEY")}
headers = [
  {"x-api-key", config.api_key},
  {"anthropic-version", "2023-06-01"},
  {"Content-Type", "application/json"}
]

IO.puts("\n1. Direct API call to /v1/models:")
alias ExLLM.Providers.Shared.HTTPClient

# First call
{:ok, response1} = HTTPClient.get_json("https://api.anthropic.com/v1/models", headers, provider: :anthropic)

# Check structure
IO.puts("  Response structure: #{inspect(Map.keys(response1))}")
body1 = Map.get(response1, :body, response1)
metadata1 = Map.get(body1, "metadata", %{})
IO.puts("  First call - from cache: #{Map.get(metadata1, :from_cache, false)}")

# Second call
{:ok, response2} = HTTPClient.get_json("https://api.anthropic.com/v1/models", headers, provider: :anthropic)
body2 = Map.get(response2, :body, response2)
metadata2 = Map.get(body2, "metadata", %{})
IO.puts("  Second call - from cache: #{Map.get(metadata2, :from_cache, false)}")

if Map.get(metadata2, :from_cache, false) do
  IO.puts("  ✅ Caching working correctly for models API")
else
  IO.puts("  ❌ Caching not working for models API")
end

# Test chat API with raw call
IO.puts("\n2. Direct API call to /v1/messages:")
body = %{
  "messages" => [%{"role" => "user", "content" => "Say test"}],
  "model" => "claude-3-haiku-20240307",
  "max_tokens" => 10
}

{:ok, chat1} = HTTPClient.post_json("https://api.anthropic.com/v1/messages", body, headers, provider: :anthropic)
body1 = Map.get(chat1, :body, chat1)
metadata1 = Map.get(body1, "metadata", %{})
IO.puts("  First call - from cache: #{Map.get(metadata1, :from_cache, false)}")

{:ok, chat2} = HTTPClient.post_json("https://api.anthropic.com/v1/messages", body, headers, provider: :anthropic)
body2 = Map.get(chat2, :body, chat2)
metadata2 = Map.get(body2, "metadata", %{})
IO.puts("  Second call - from cache: #{Map.get(metadata2, :from_cache, false)}")

if Map.get(metadata2, :from_cache, false) do
  IO.puts("  ✅ Caching working correctly for chat API")
else
  IO.puts("  ❌ Caching not working for chat API")
end