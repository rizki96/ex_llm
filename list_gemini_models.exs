{:ok, _} = Application.ensure_all_started(:ex_llm)

IO.puts("\nListing Gemini models...")
case ExLLM.list_models(:gemini) do
  {:ok, models} ->
    models
    |> Enum.sort_by(& &1.id)
    |> Enum.each(fn model ->
      IO.puts("  - #{model.id}")
    end)
  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end
