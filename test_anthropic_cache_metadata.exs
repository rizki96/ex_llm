System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")
Application.put_env(:ex_llm, :debug_test_cache, true)

alias ExLLM.Providers.Anthropic

# Set test context to enable caching
test_context = %{
  module: TestAnthropicCache,
  test_name: "test_anthropic_cache",
  test: "test_anthropic_cache", 
  tags: %{live_api: true, provider: :anthropic}
}
ExLLM.Testing.TestCacheDetector.set_test_context(test_context)

IO.puts("Testing Anthropic Cache Metadata")
IO.puts("=" <> String.duplicate("=", 50))

messages = [
  %{role: "user", content: "Say 'CACHE_TEST' and nothing else."}
]

IO.puts("\nFirst call (should hit API):")
{:ok, response1} = Anthropic.chat(messages, max_tokens: 20)
IO.puts("  Content: #{response1.content}")
IO.puts("  ID: #{response1.id}")
IO.puts("  Metadata: #{inspect(response1.metadata)}")

# Small delay to ensure cache is written
:timer.sleep(100)

IO.puts("\nSecond call (should be cached):")
{:ok, response2} = Anthropic.chat(messages, max_tokens: 20)
IO.puts("  Content: #{response2.content}")
IO.puts("  ID: #{response2.id}") 
IO.puts("  Metadata: #{inspect(response2.metadata)}")

if response2.metadata && response2.metadata[:from_cache] do
  IO.puts("\n✅ Caching is working! Second response was served from cache.")
else
  IO.puts("\n❌ Caching not working - second response was not from cache.")
end