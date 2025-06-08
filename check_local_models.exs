Application.ensure_all_started(:ex_llm)
Process.sleep(100)

alias ExLLM.Adapters.Bumblebee

IO.puts("\n=== Bumblebee Local Models Check ===")

# Check what Bumblebee lists as available
case Bumblebee.list_models() do
  {:ok, models} ->
    IO.puts("Bumblebee reports #{length(models)} available models:")
    Enum.each(models, fn model ->
      IO.puts("  - #{model.id}")
      IO.puts("    Name: #{model.name}")
      IO.puts("    Description: #{model.description}")
      IO.puts("    Context: #{model.context_window}")
    end)
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

# Check HuggingFace cache directory
hf_cache_home = System.get_env("HF_HOME") || Path.expand("~/.cache/huggingface")
hf_hub_cache = Path.join(hf_cache_home, "hub")

IO.puts("\n=== HuggingFace Cache Directory ===")
IO.puts("HF_HOME: #{hf_cache_home}")
IO.puts("Hub cache: #{hf_hub_cache}")

if File.exists?(hf_hub_cache) do
  IO.puts("Cache directory exists. Checking for models...")
  
  case File.ls(hf_hub_cache) do
    {:ok, files} ->
      # Filter for model directories (start with "models--")
      model_dirs = Enum.filter(files, &String.starts_with?(&1, "models--"))
      
      IO.puts("Found #{length(model_dirs)} cached models:")
      Enum.each(model_dirs, fn dir ->
        # Extract model name from directory format "models--org--name"
        model_name = dir
          |> String.replace_prefix("models--", "")
          |> String.replace("--", "/")
        
        IO.puts("  - #{model_name}")
        
        # Check if this model has snapshots (actual downloads)
        model_path = Path.join(hf_hub_cache, dir)
        snapshots_path = Path.join(model_path, "snapshots")
        
        if File.exists?(snapshots_path) do
          case File.ls(snapshots_path) do
            {:ok, snapshots} when snapshots != [] ->
              IO.puts("    ✓ Downloaded (#{length(snapshots)} snapshot(s))")
            _ ->
              IO.puts("    ⚠ Not downloaded")
          end
        else
          IO.puts("    ⚠ No snapshots directory")
        end
      end)
    {:error, reason} ->
      IO.puts("Error reading cache directory: #{inspect(reason)}")
  end
else
  IO.puts("Cache directory does not exist")
end

# Check ExLLM's model cache
exllm_cache = Path.expand("~/.ex_llm/models")
IO.puts("\n=== ExLLM Model Cache ===")
IO.puts("ExLLM cache: #{exllm_cache}")

if File.exists?(exllm_cache) do
  case File.ls(exllm_cache) do
    {:ok, files} ->
      IO.puts("Found #{length(files)} items in ExLLM cache:")
      Enum.each(files, fn file ->
        IO.puts("  - #{file}")
      end)
    {:error, reason} ->
      IO.puts("Error reading ExLLM cache: #{inspect(reason)}")
  end
else
  IO.puts("ExLLM cache directory does not exist")
end

IO.puts("\n=== Model Compatibility Test ===")
IO.puts("Testing if Bumblebee can load some common model formats...")

# Test loading a few common models that might be cached
test_models = [
  "microsoft/phi-2",
  "microsoft/DialoGPT-medium", 
  "google/flan-t5-base",
  "google/flan-t5-small",
  "sentence-transformers/all-MiniLM-L6-v2",
  "huggingface/distilbert-base-cased",
  "bert-base-uncased"
]

Enum.each(test_models, fn model ->
  IO.write("  #{model}: ")
  
  try do
    if Code.ensure_loaded?(Bumblebee) do
      # Try to load model info without actually loading the full model
      case apply(Bumblebee, :load_model, [{:hf, model}, []]) do
        {:ok, _} -> IO.puts("✓ Compatible")
        {:error, reason} -> IO.puts("✗ #{inspect(reason) |> String.slice(0, 60)}...")
      end
    else
      IO.puts("✗ Bumblebee not available")
    end
  rescue
    e -> IO.puts("✗ Exception: #{inspect(e) |> String.slice(0, 60)}...")
  end
  
  Process.sleep(100) # Small delay to avoid overwhelming
end)

IO.puts("\nCheck complete!")