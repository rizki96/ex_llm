#!/usr/bin/env elixir

# Comprehensive cache verification script
# This script tests each major API to verify caching integration

alias ExLLM.Providers.OpenAI

# Enable cache debugging
ExLLM.Testing.TestCacheHelpers.enable_cache_debug()

IO.puts("=== Comprehensive Cache Verification ===")
IO.puts("Testing each major OpenAI API for cache integration...\n")

# Test cases for each API
test_cases = [
  {
    "Fine-tuning Jobs", 
    fn -> OpenAI.list_fine_tuning_jobs() end,
    fn result -> 
      case result do
        {:ok, %{body: %{"metadata" => %{from_cache: true}}}} -> :cached
        {:ok, %{body: %{"metadata" => _}}} -> :not_cached
        {:ok, _} -> :no_metadata
        _ -> :error
      end
    end
  },
  {
    "Assistants List", 
    fn -> OpenAI.list_assistants() end,
    fn result ->
      case result do
        {:ok, %{"metadata" => %{from_cache: true}}} -> :cached
        {:ok, %{"metadata" => _}} -> :not_cached
        {:ok, _} -> :no_metadata
        _ -> :error
      end
    end
  },
  {
    "Models List", 
    fn -> OpenAI.list_models() end,
    fn result ->
      case result do
        {:ok, models} when is_list(models) -> :structured_response
        _ -> :error
      end
    end
  },
  {
    "Embeddings", 
    fn -> OpenAI.embeddings("test", model: "text-embedding-3-small") end,
    fn result ->
      case result do
        {:ok, result} when is_map(result) and is_map_key(result, :embeddings) -> :structured_response
        _ -> :error
      end
    end
  },
  {
    "Vector Stores List", 
    fn -> OpenAI.list_vector_stores() end,
    fn result ->
      case result do
        {:ok, %{"metadata" => %{from_cache: true}}} -> :cached
        {:ok, %{"metadata" => _}} -> :not_cached
        {:ok, _} -> :no_metadata
        _ -> :error
      end
    end
  },
  {
    "Create Thread", 
    fn -> OpenAI.create_thread() end,
    fn result ->
      case result do
        {:ok, %{"id" => id}} when is_binary(id) -> :success
        _ -> :error
      end
    end
  }
]

# Run each test
results = Enum.map(test_cases, fn {name, test_fn, check_fn} ->
  IO.write("Testing #{name}... ")
  
  try do
    result = test_fn.()
    status = check_fn.(result)
    IO.puts("#{status}")
    {name, status, result}
  rescue
    e -> 
      IO.puts("ERROR: #{inspect(e)}")
      {name, :exception, e}
  end
end)

IO.puts("\n=== Results Summary ===")
Enum.each(results, fn {name, status, _result} ->
  status_icon = case status do
    :cached -> "✅ CACHED"
    :not_cached -> "⚠️  NOT CACHED"
    :structured_response -> "🔄 STRUCTURED"
    :success -> "✅ SUCCESS"
    :no_metadata -> "❓ NO METADATA"
    :error -> "❌ ERROR"
    :exception -> "💥 EXCEPTION"
  end
  IO.puts("#{status_icon} - #{name}")
end)

# Check cache directories
IO.puts("\n=== Cache Directory Analysis ===")
cache_dirs = case File.ls("test/cache/openai") do
  {:ok, dirs} -> 
    dirs 
    |> Enum.filter(&File.dir?("test/cache/openai/#{&1}"))
    |> Enum.sort()
  {:error, _} -> []
end

IO.puts("Cache directories found: #{length(cache_dirs)}")
Enum.each(cache_dirs, fn dir ->
  count = case File.ls("test/cache/openai/#{dir}") do
    {:ok, files} -> 
      files |> Enum.filter(&String.ends_with?(&1, ".json")) |> length()
    {:error, _} -> 0
  end
  IO.puts("  #{dir}: #{count} cached requests")
end)

IO.puts("\n=== Cache Integration Assessment ===")
cached_count = results |> Enum.count(fn {_, status, _} -> status == :cached end)
total_testable = results |> Enum.count(fn {_, status, _} -> status != :exception end)
IO.puts("APIs with confirmed caching: #{cached_count}/#{total_testable}")

if cached_count < total_testable do
  IO.puts("⚠️  Some APIs may not be fully integrated with caching system")
else
  IO.puts("✅ All testable APIs are properly cached")
end