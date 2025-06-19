System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")
alias ExLLM.Providers.OpenAI

# Set test context
test_context = %{
  module: TestCacheFix,
  test_name: "test_cache_fix",
  test: "test_cache_fix",
  tags: %{live_api: true, provider: :openai}
}
ExLLM.Testing.TestCacheDetector.set_test_context(test_context)

IO.puts("Testing Cache Fix\n")

# Test 1: Assistants API
IO.puts("1. Assistants API:")
{:ok, r1} = OpenAI.list_assistants()
IO.puts("  First call - has metadata: #{Map.has_key?(r1, "metadata")}")

{:ok, r2} = OpenAI.list_assistants()  
metadata = Map.get(r2, "metadata", %{})
IO.puts("  Second call - from cache: #{Map.get(metadata, :from_cache, false)}")

# Test 2: Fine-tuning API
IO.puts("\n2. Fine-tuning API:")
{:ok, f1} = OpenAI.list_fine_tuning_jobs()
IO.puts("  First call - has metadata: #{Map.has_key?(f1, "metadata")}")

{:ok, f2} = OpenAI.list_fine_tuning_jobs()
metadata = Map.get(f2, "metadata", %{})
IO.puts("  Second call - from cache: #{Map.get(metadata, :from_cache, false)}")

# Test 3: Vector Stores API
IO.puts("\n3. Vector Stores API:")
{:ok, v1} = OpenAI.list_vector_stores()
IO.puts("  First call - has metadata: #{Map.has_key?(v1, "metadata")}")

{:ok, v2} = OpenAI.list_vector_stores()
metadata = Map.get(v2, "metadata", %{})
IO.puts("  Second call - from cache: #{Map.get(metadata, :from_cache, false)}")

# Check cache directories
IO.puts("\n4. Cache directories:")
{:ok, dirs} = File.ls("test/cache/openai")
IO.puts("  Found: #{Enum.join(dirs, ", ")}")