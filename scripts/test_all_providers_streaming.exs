#!/usr/bin/env elixir

# Test streaming functionality for all providers
Mix.install([
  {:ex_llm, path: "."}
])

defmodule AllProvidersStreamingTest do
  require Logger

  def test_provider(provider, model, enabled \\ true) do
    if enabled do
      IO.puts("\n" <> String.duplicate("=", 60))
      IO.puts("Testing #{provider} with model #{model}")
      IO.puts(String.duplicate("=", 60))
      
      try do
        # Create a simple callback that collects chunks
        chunks = []
        callback = fn chunk ->
          case chunk do
            %{done: true} = final ->
              IO.puts("\n✅ Stream complete")
              {:ok, final}
            %{} = chunk ->
              content = get_content_from_chunk(chunk)
              if content && String.trim(content) != "" do
                IO.write(content)
                chunks ++ [content]
              end
          end
        end

        messages = [
          %{role: "system", content: "You are a helpful assistant. Respond in 5 words or less."},
          %{role: "user", content: "Say hello to ExLLM."}
        ]

        start_time = System.monotonic_time(:millisecond)
        
        result = ExLLM.ChatBuilder.new(provider, messages)
          |> ExLLM.ChatBuilder.with_model(model)
          |> ExLLM.ChatBuilder.stream(callback)

        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        case result do
          :ok ->
            IO.puts("✅ #{provider} streaming: SUCCESS (#{duration}ms)")
            {:ok, provider}
          {:error, reason} ->
            IO.puts("\n❌ #{provider} streaming: FAILED")
            IO.puts("   Error: #{inspect(reason)}")
            {:error, provider}
        end
      rescue
        e ->
          IO.puts("\n💥 #{provider} streaming: CRASHED")
          IO.puts("   Exception: #{Exception.message(e)}")
          {:crash, provider}
      end
    else
      IO.puts("\n⏭️  Skipping #{provider} (disabled for this test)")
      {:skip, provider}
    end
  end

  defp get_content_from_chunk(chunk) do
    cond do
      # OpenAI format
      is_map(chunk) && Map.has_key?(chunk, "choices") ->
        case chunk["choices"] do
          [%{"delta" => %{"content" => content}} | _] -> content
          _ -> nil
        end
      
      # Anthropic format  
      is_map(chunk) && Map.has_key?(chunk, "delta") ->
        chunk["delta"]["text"]
        
      # Gemini format
      is_map(chunk) && Map.has_key?(chunk, "candidates") ->
        case chunk["candidates"] do
          [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _] -> text
          _ -> nil
        end
        
      # Ollama format
      Map.has_key?(chunk, :content) ->
        chunk.content
        
      # Generic format
      true -> 
        nil
    end
  end

  def run_all_tests() do
    # Provider configurations
    # Set enabled to false to skip providers you don't have API keys for
    providers = [
      # Cloud providers
      {:openai, "gpt-4o-mini", true},
      {:anthropic, "claude-3-haiku-20240307", true},
      {:gemini, "gemini-2.0-flash", true},
      {:groq, "llama-3.1-8b-instant", true},
      {:xai, "grok-2-1212", System.get_env("XAI_API_KEY") != nil || System.get_env("GROK_API_KEY") != nil},
      {:mistral, "mistral-small-latest", System.get_env("MISTRAL_API_KEY") != nil},
      {:openrouter, "meta-llama/llama-3.2-3b-instruct:free", System.get_env("OPENROUTER_API_KEY") != nil},
      {:perplexity, "llama-3.1-sonar-small-128k-online", System.get_env("PERPLEXITY_API_KEY") != nil},
      {:bedrock, "anthropic.claude-v2", System.get_env("AWS_ACCESS_KEY_ID") != nil},
      
      # Local providers
      {:ollama, "llama3.2", check_ollama_running()},
      {:lmstudio, "local-model", check_lmstudio_running()},
      {:bumblebee, "llama2", false}  # Bumblebee doesn't support streaming yet
    ]

    IO.puts("\n🚀 Testing streaming for all ExLLM providers")
    IO.puts(String.duplicate("=", 60))

    results = Enum.map(providers, fn {provider, model, enabled} ->
      test_provider(provider, model, enabled)
    end)

    # Summary
    IO.puts("\n\n📊 STREAMING TEST SUMMARY")
    IO.puts(String.duplicate("=", 60))
    
    success_count = Enum.count(results, fn {status, _} -> status == :ok end)
    error_count = Enum.count(results, fn {status, _} -> status == :error end)
    crash_count = Enum.count(results, fn {status, _} -> status == :crash end)
    skip_count = Enum.count(results, fn {status, _} -> status == :skip end)
    
    Enum.each(results, fn {status, provider} ->
      emoji = case status do
        :ok -> "✅"
        :error -> "❌"
        :crash -> "💥"
        :skip -> "⏭️"
      end
      IO.puts("#{emoji} #{provider}")
    end)
    
    IO.puts("\nResults: #{success_count} passed, #{error_count} failed, #{crash_count} crashed, #{skip_count} skipped")
  end

  defp check_ollama_running() do
    case System.cmd("curl", ["-s", "http://localhost:11434/api/tags"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp check_lmstudio_running() do
    case System.cmd("curl", ["-s", "http://localhost:1234/v1/models"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end

AllProvidersStreamingTest.run_all_tests()