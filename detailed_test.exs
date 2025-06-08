Application.ensure_all_started(:ex_llm)
Process.sleep(200)

alias ExLLM.Adapters.Bumblebee

case Bumblebee.list_models() do
  {:ok, models} ->
    cached_models = Enum.filter(models, fn m -> String.contains?(m.description, "Cached") end)
    default_models = Enum.filter(models, fn m -> String.contains?(m.description, "Available") end)
    
    IO.puts("=== Your Cached Models (#{length(cached_models)}) ===")
    Enum.each(cached_models, fn model ->
      IO.puts("• #{model.id}")
      IO.puts("  Context: #{model.context_window} tokens")
      IO.puts("  Features: #{Enum.join(model.capabilities.features, ", ")}")
      IO.puts("")
    end)
    
    IO.puts("=== Available Models (#{length(default_models)}) ===")
    Enum.each(default_models, fn model ->
      IO.puts("• #{model.id}")
    end)
    
  {:error, reason} ->
    IO.puts("ERROR: #{inspect(reason)}")
end