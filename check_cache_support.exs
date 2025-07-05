{:ok, _} = Application.ensure_all_started(:ex_llm)

IO.puts("\nChecking Gemini models that support createCachedContent...")
case ExLLM.list_models(:gemini) do
  {:ok, models} ->
    models
    |> Enum.filter(fn model ->
      # Check if model supports createCachedContent
      case model do
        %{capabilities: %{supported_generation_methods: methods}} when is_list(methods) ->
          "createCachedContent" in methods
        %{supported_generation_methods: methods} when is_list(methods) ->
          "createCachedContent" in methods
        _ ->
          false
      end
    end)
    |> Enum.each(fn model ->
      IO.puts("  ✅ #{model.id} supports createCachedContent")
    end)
  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end
