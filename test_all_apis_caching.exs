System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")
alias ExLLM.Providers.OpenAI

# Set test context
test_context = %{
  module: TestAllAPIsCaching,
  test_name: "test_all_apis_caching", 
  test: "test_all_apis_caching",
  tags: %{live_api: true, provider: :openai}
}
ExLLM.Testing.TestCacheDetector.set_test_context(test_context)

IO.puts("Testing All OpenAI APIs Caching")
IO.puts("=" <> String.duplicate("=", 50))

# Test function
test_api = fn name, api_call ->
  IO.puts("\n#{name}:")
  
  # First call
  case api_call.() do
    {:ok, response} when is_map(response) ->
      metadata1 = Map.get(response, "metadata", %{})
      cached1 = Map.get(metadata1, :from_cache, false)
      IO.puts("  First call - from cache: #{cached1}")
      
      # Second call
      case api_call.() do
        {:ok, response2} when is_map(response2) ->
          metadata2 = Map.get(response2, "metadata", %{})
          cached2 = Map.get(metadata2, :from_cache, false)
          IO.puts("  Second call - from cache: #{cached2}")
          
          if cached2 and not cached1 do
            IO.puts("  ✅ Caching working correctly")
          elsif cached1 and cached2 do
            IO.puts("  ✅ Already cached from previous runs")
          else
            IO.puts("  ❌ Caching not working")
          end
          
        {:error, error} ->
          IO.puts("  ❌ Error on second call: #{inspect(error)}")
      end
      
    {:ok, _} ->
      IO.puts("  ⚠️  Returns structured data, not raw API response")
      
    {:error, error} ->
      IO.puts("  ❌ Error: #{inspect(error)}")
  end
end

# Test all APIs
test_api.("1. List Assistants", fn -> OpenAI.list_assistants() end)
test_api.("2. List Vector Stores", fn -> OpenAI.list_vector_stores() end)
test_api.("3. List Fine-tuning Jobs", fn -> OpenAI.list_fine_tuning_jobs() end)
test_api.("4. Create Thread", fn -> OpenAI.create_thread() end)
test_api.("5. List Files", fn -> OpenAI.list_files() end)
test_api.("6. List Models", fn -> OpenAI.list_models() end)
test_api.("7. Create Embeddings", fn -> OpenAI.embeddings("test") end)
test_api.("8. Moderate Content", fn -> OpenAI.moderate_content("test") end)

IO.puts("\nCache Summary:")
case File.ls("test/cache/openai") do
  {:ok, dirs} ->
    IO.puts("Cache directories: #{Enum.join(Enum.sort(dirs), ", ")}")
    
    # Count entries in each directory
    for dir <- dirs do
      path = Path.join("test/cache/openai", dir)
      case File.ls(path) do
        {:ok, entries} -> IO.puts("  #{dir}: #{length(entries)} entries")
        _ -> :ok
      end
    end
    
  {:error, _} ->
    IO.puts("No cache directory found")
end