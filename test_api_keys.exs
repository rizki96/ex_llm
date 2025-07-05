# Start the application first
{:ok, _} = Application.ensure_all_started(:ex_llm)

# Test API keys directly
providers = [:anthropic, :openai, :gemini, :groq]

for provider <- providers do
  IO.puts("\nTesting #{provider}...")
  
  case ExLLM.chat(provider, [%{role: "user", content: "Say hello"}], max_tokens: 10) do
    {:ok, response} ->
      IO.puts("✅ #{provider}: #{response.content}")
    {:error, error} ->
      IO.puts("❌ #{provider}: #{inspect(error)}")
  end
end
