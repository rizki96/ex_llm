#!/usr/bin/env elixir

Mix.install([
  {:ex_llm, path: "."}
])

defmodule ProviderTester do
  def test_providers do
    IO.puts("\n🔌 Testing Provider Connectivity\n")
    
    providers = [
      {:openai, "OPENAI_API_KEY", fn -> 
        ExLLM.chat([%{role: "user", content: "Hi"}], model: "gpt-4o-mini", max_tokens: 1)
      end},
      {:anthropic, "ANTHROPIC_API_KEY", fn ->
        ExLLM.chat([%{role: "user", content: "Hi"}], model: "claude-3-haiku-20240307", max_tokens: 1)
      end},
      {:gemini, "GEMINI_API_KEY", fn ->
        ExLLM.chat([%{role: "user", content: "Hi"}], model: "gemini-1.5-flash", max_tokens: 1)
      end},
      {:groq, "GROQ_API_KEY", fn ->
        ExLLM.chat([%{role: "user", content: "Hi"}], model: "llama-3.3-70b-specdec", max_tokens: 1)
      end},
      {:openrouter, "OPENROUTER_API_KEY", fn ->
        ExLLM.chat([%{role: "user", content: "Hi"}], model: "openai/gpt-3.5-turbo", max_tokens: 1)
      end}
    ]
    
    results = Enum.map(providers, fn {name, env_var, test_fn} ->
      IO.write("Testing #{name}... ")
      
      if System.get_env(env_var) do
        case test_fn.() do
          {:ok, _response} ->
            IO.puts("✅ Connected")
            {name, :ok}
          {:error, error} ->
            IO.puts("❌ Error: #{inspect(error)}")
            {name, :error}
        end
      else
        IO.puts("⚠️  #{env_var} not set")
        {name, :missing}
      end
    end)
    
    IO.puts("\n📊 Summary:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    working = Enum.count(results, fn {_, status} -> status == :ok end)
    failed = Enum.count(results, fn {_, status} -> status == :error end)
    missing = Enum.count(results, fn {_, status} -> status == :missing end)
    
    IO.puts("✅ Working: #{working}")
    IO.puts("❌ Failed: #{failed}")
    IO.puts("⚠️  Missing: #{missing}")
  end
end

ProviderTester.test_providers()