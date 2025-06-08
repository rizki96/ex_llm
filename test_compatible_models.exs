Application.ensure_all_started(:ex_llm)
Process.sleep(200)

alias ExLLM.Adapters.Bumblebee

IO.puts("=== Testing Compatible Qwen Models ===")

# Test some standard Qwen models that might work with Bumblebee
test_models = [
  "microsoft/phi-2",
  "microsoft/DialoGPT-medium",
  "google/flan-t5-base",
  "google/flan-t5-small"
]

IO.puts("Testing standard models that should work with Bumblebee...")

Enum.each(test_models, fn model ->
  IO.write("#{model}: ")
  
  case Bumblebee.chat([%{role: "user", content: "Hi"}], model: model) do
    {:ok, _response} ->
      IO.puts("✓ WORKS")
      
    {:error, reason} ->
      cond do
        String.contains?(reason, "not available") ->
          IO.puts("✗ Model not available in cache")
        String.contains?(reason, "MLX models") ->
          IO.puts("✗ MLX model (as expected)")
        String.contains?(reason, "could not match") ->
          IO.puts("✗ Architecture not supported")
        String.contains?(reason, "Failed to download") ->
          IO.puts("? Would download (not cached)")
        true ->
          IO.puts("✗ Other error: #{String.slice(reason, 0, 50)}...")
      end
  end
  
  Process.sleep(100)
end)

IO.puts("\n=== Summary ===")
IO.puts("MLX models are discovered but not loadable by Bumblebee.")
IO.puts("For actual inference, use standard Hugging Face models.")
IO.puts("Your MLX models remain valuable for MLX-compatible tools.")