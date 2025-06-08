Application.ensure_all_started(:ex_llm)
Process.sleep(200)

alias ExLLM.Adapters.Bumblebee

IO.puts("Testing Bumblebee model discovery...")

case Bumblebee.list_models() do
  {:ok, models} ->
    IO.puts("SUCCESS: Found #{length(models)} models")
    
    Enum.each(models, fn model ->
      IO.puts("#{model.id} - #{model.name}")
      if String.contains?(model.description, "Cached") do
        IO.puts("  ^ This is a cached model!")
      end
    end)
    
  {:error, reason} ->
    IO.puts("ERROR: #{inspect(reason)}")
end