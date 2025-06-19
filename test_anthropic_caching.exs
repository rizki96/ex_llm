System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")
Application.put_env(:ex_llm, :debug_test_cache, true)

# Check if API key is set
if System.get_env("ANTHROPIC_API_KEY") == nil do
  IO.puts("WARNING: ANTHROPIC_API_KEY not set, some tests may fail")
end

alias ExLLM.Providers.Anthropic

# Set test context
test_context = %{
  module: TestAnthropicCaching,
  test_name: "test_anthropic_caching",
  test: "test_anthropic_caching",
  tags: %{live_api: true, provider: :anthropic}
}
ExLLM.Testing.TestCacheDetector.set_test_context(test_context)

IO.puts("Testing Anthropic APIs Caching")
IO.puts("=" <> String.duplicate("=", 50))

# Test messages
test_messages = [
  %{role: "user", content: "Hi, just say 'test' and nothing else."}
]

# 1. Test Chat API
IO.puts("\n1. Chat API:")
try do
  {:ok, response1} = Anthropic.chat(test_messages, max_tokens: 10)
  IO.puts("  First call - Response type: #{inspect(response1.__struct__)}")
  
  {:ok, response2} = Anthropic.chat(test_messages, max_tokens: 10)
  
  # Structured responses don't have metadata, but check if they're identical
  if response1.id == response2.id and response1.content == response2.content do
    IO.puts("  ✅ Responses are identical - likely cached")
  else
    IO.puts("  ❌ Responses are different - not cached")
  end
rescue
  e ->
    IO.puts("  ❌ Error: #{inspect(e)}")
end

# 2. Test List Models
IO.puts("\n2. List Models:")
try do
  {:ok, models1} = Anthropic.list_models()
  
  # Check what type of response we get
  cond do
    is_list(models1) ->
      IO.puts("  Returns list of models (#{length(models1)} models)")
      {:ok, models2} = Anthropic.list_models()
      
      if models1 == models2 do
        IO.puts("  ✅ Model lists are identical - likely cached")
      else
        IO.puts("  ❌ Model lists are different - not cached")
      end
      
    is_map(models1) ->
      metadata1 = Map.get(models1, "metadata", %{})
      IO.puts("  First call - from cache: #{Map.get(metadata1, :from_cache, false)}")
      
      {:ok, models2} = Anthropic.list_models()
      metadata2 = Map.get(models2, "metadata", %{})
      IO.puts("  Second call - from cache: #{Map.get(metadata2, :from_cache, false)}")
      
      if Map.get(metadata2, :from_cache, false) do
        IO.puts("  ✅ Caching working correctly")
      else
        IO.puts("  ❌ Caching not working")
      end
      
    true ->
      IO.puts("  Unknown response type: #{inspect(models1)}")
  end
rescue
  e ->
    IO.puts("  ❌ Error: #{inspect(e)}")
end

# 3. Test Embeddings
IO.puts("\n3. Embeddings API:")
result = Anthropic.embeddings("test")
IO.puts("  Result: #{inspect(result)}")

# Check cache directories
IO.puts("\n4. Cache Summary:")
case File.ls("test/cache") do
  {:ok, providers} ->
    if "anthropic" in providers do
      case File.ls("test/cache/anthropic") do
        {:ok, dirs} ->
          IO.puts("  Anthropic cache directories: #{Enum.join(Enum.sort(dirs), ", ")}")
          
          # Count entries
          for dir <- dirs do
            path = Path.join("test/cache/anthropic", dir)
            case File.ls(path) do
              {:ok, entries} -> 
                IO.puts("    #{dir}: #{length(entries)} entries")
              _ -> 
                :ok
            end
          end
        {:error, _} ->
          IO.puts("  No Anthropic cache directories found")
      end
    else
      IO.puts("  No Anthropic provider cache directory")
    end
  {:error, _} ->
    IO.puts("  No cache directory found")
end