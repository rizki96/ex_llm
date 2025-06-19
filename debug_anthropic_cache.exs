System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")
Application.put_env(:ex_llm, :debug_test_cache, true)

alias ExLLM.Providers.Anthropic
alias ExLLM.Testing.TestCacheDetector

# Check if we're in test environment
IO.puts("MIX_ENV: #{System.get_env("MIX_ENV")}")
IO.puts("EX_LLM_TEST_CACHE_ENABLED: #{System.get_env("EX_LLM_TEST_CACHE_ENABLED")}")

# Set test context
test_context = %{
  module: DebugAnthropicCache,
  test_name: "debug_anthropic_cache",
  test: "debug_anthropic_cache",
  tags: %{live_api: true, provider: :anthropic, cache_test: true}
}

IO.puts("\nSetting test context...")
TestCacheDetector.set_test_context(test_context)

# Verify context is set
case TestCacheDetector.get_current_test_context() do
  {:ok, ctx} -> 
    IO.puts("Context set: #{inspect(ctx.module)}")
    IO.puts("Tags: #{inspect(ctx.tags)}")
  :error -> 
    IO.puts("ERROR: No context found!")
end

IO.puts("Should cache: #{TestCacheDetector.should_cache_responses?()}")

messages = [
  %{role: "user", content: "Say 'CACHE_DEBUG_TEST' and nothing else."}
]

IO.puts("\n=== First API Call ===")
start1 = System.monotonic_time(:millisecond)
{:ok, response1} = Anthropic.chat(messages, max_tokens: 20)
duration1 = System.monotonic_time(:millisecond) - start1
IO.puts("Duration: #{duration1}ms")
IO.puts("Content: #{response1.content}")
IO.puts("ID: #{response1.id}")

:timer.sleep(200)

IO.puts("\n=== Second API Call (should be cached) ===")
start2 = System.monotonic_time(:millisecond)
{:ok, response2} = Anthropic.chat(messages, max_tokens: 20)
duration2 = System.monotonic_time(:millisecond) - start2
IO.puts("Duration: #{duration2}ms")
IO.puts("Content: #{response2.content}")
IO.puts("ID: #{response2.id}")

IO.puts("\n=== Cache Verification ===")
IO.puts("First call: #{duration1}ms")
IO.puts("Second call: #{duration2}ms")
IO.puts("Speed improvement: #{Float.round(duration1 / duration2, 2)}x")

if duration2 < duration1 / 5 do
  IO.puts("✅ Caching appears to be working")
else
  IO.puts("❌ Caching not working as expected")
end

# Check cache stats
IO.puts("\n=== Checking Cache Stats ===")
{output, _} = System.cmd("mix", ["ex_llm.cache", "stats"], env: [{"MIX_ENV", "test"}])
IO.puts(output)