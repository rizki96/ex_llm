# Set up environment for test cache debugging
System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")
System.put_env("EX_LLM_LOG_LEVEL", "debug")
Application.put_env(:ex_llm, :debug_test_cache, true)

alias ExLLM.Providers.OpenAI

IO.puts("Testing Beta Header Impact on Caching\n")

# Check environment
IO.puts("Current environment:")
IO.puts("Mix.env: #{Mix.env()}")
IO.puts("EX_LLM_TEST_CACHE_ENABLED: #{System.get_env("EX_LLM_TEST_CACHE_ENABLED")}")
IO.puts("EX_LLM_LOG_LEVEL: #{System.get_env("EX_LLM_LOG_LEVEL")}")
IO.puts("debug_test_cache: #{Application.get_env(:ex_llm, :debug_test_cache)}")

# Set test context to enable caching
test_context = %{
  module: TestBetaHeaderCaching,
  test_name: "test_beta_header_caching",
  test: "test_beta_header_caching",
  tags: %{
    live_api: true,
    provider: :openai
  }
}
ExLLM.Testing.TestCacheDetector.set_test_context(test_context)
IO.puts("Test context set: #{inspect(test_context)}")
IO.puts("\n")

# Test 1: List assistants (with beta header) - raw response
IO.puts("Test 1: List assistants (with beta header)")
case OpenAI.list_assistants() do
  {:ok, response} when is_map(response) -> 
    metadata = Map.get(response, "metadata", %{})
    IO.puts("Response has metadata: #{inspect(Map.keys(metadata))}")
    IO.puts("From cache: #{inspect(Map.get(metadata, :from_cache, false))}")
  error -> 
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\n" <> String.duplicate("-", 80) <> "\n")

# Test 2: List fine-tuning jobs (no beta header) - raw response
IO.puts("Test 2: List fine-tuning jobs (no beta header)")
case OpenAI.list_fine_tuning_jobs() do
  {:ok, response} when is_map(response) -> 
    metadata = Map.get(response, "metadata", %{})
    IO.puts("Response has metadata: #{inspect(Map.keys(metadata))}")
    IO.puts("From cache: #{inspect(Map.get(metadata, :from_cache, false))}")
  error -> 
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\n" <> String.duplicate("-", 80) <> "\n")

# Test 3: List vector stores (with beta header) - raw response
IO.puts("Test 3: List vector stores (with beta header)")
case OpenAI.list_vector_stores() do
  {:ok, response} when is_map(response) -> 
    metadata = Map.get(response, "metadata", %{})
    IO.puts("Response has metadata: #{inspect(Map.keys(metadata))}")
    IO.puts("From cache: #{inspect(Map.get(metadata, :from_cache, false))}")
  error -> 
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\n" <> String.duplicate("-", 80) <> "\n")

# Test 4: Run the same requests again to check if they're cached
IO.puts("Test 4: Running same requests again...\n")

IO.puts("List assistants (2nd call):")
case OpenAI.list_assistants() do
  {:ok, response} when is_map(response) -> 
    metadata = Map.get(response, "metadata", %{})
    IO.puts("From cache: #{inspect(Map.get(metadata, :from_cache, false))}")
  error -> 
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\nList fine-tuning jobs (2nd call):")
case OpenAI.list_fine_tuning_jobs() do
  {:ok, response} when is_map(response) -> 
    metadata = Map.get(response, "metadata", %{})
    IO.puts("From cache: #{inspect(Map.get(metadata, :from_cache, false))}")
  error -> 
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\nList vector stores (2nd call):")
case OpenAI.list_vector_stores() do
  {:ok, response} when is_map(response) -> 
    metadata = Map.get(response, "metadata", %{})
    IO.puts("From cache: #{inspect(Map.get(metadata, :from_cache, false))}")
  error -> 
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\n" <> String.duplicate("-", 80) <> "\n")

# Test 5: Check cache stats
IO.puts("Test 5: Checking cache stats...")
if Code.ensure_loaded?(Mix.Tasks.ExLlm.Cache) do
  Mix.Tasks.ExLlm.Cache.run(["stats"])
end