#!/usr/bin/env elixir

# Test streaming functionality after field mismatch fix
Mix.install([
  {:ex_llm, path: "."}
])

defmodule StreamingTest do
  require Logger

  def test_streaming(provider, model) do
    IO.puts("Testing streaming for #{provider} with model #{model}")
    
    try do
      # Create a simple callback that prints chunks
      callback = fn chunk ->
        case chunk do
          %{done: true} = final ->
            IO.puts("Stream complete: #{inspect(final)}")
          %{} = chunk ->
            content = get_content_from_chunk(chunk)
            if content && String.trim(content) != "" do
              IO.write(content)
            end
        end
      end

      # Build messages
      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Say hello world in exactly 5 words."}
      ]

      # Test streaming
      result = ExLLM.ChatBuilder.new(provider, messages)
        |> ExLLM.ChatBuilder.with_model(model)
        |> ExLLM.ChatBuilder.stream(callback)

      case result do
        :ok ->
          IO.puts("\n✅ #{provider} streaming completed successfully")
          :ok
        {:error, reason} ->
          IO.puts("\n❌ #{provider} streaming failed: #{inspect(reason)}")
          :error
        other ->
          IO.puts("\n⚠️ #{provider} unexpected result: #{inspect(other)}")
          :unknown
      end
    rescue
      e ->
        IO.puts("\n💥 #{provider} streaming crashed: #{Exception.message(e)}")
        :crash
    end
  end

  defp get_content_from_chunk(%{"choices" => [%{"delta" => %{"content" => content}} | _]}), do: content
  defp get_content_from_chunk(%{"candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]}), do: text
  defp get_content_from_chunk(%{"content" => [%{"text" => text} | _]}), do: text
  defp get_content_from_chunk(_), do: nil

  def run_all_tests() do
    # Test different providers
    tests = [
      {:openai, "gpt-4o-mini"},
      {:groq, "llama-3.1-8b-instant"},
      {:anthropic, "claude-3-haiku-20240307"},
      {:gemini, "gemini-2.0-flash"}
    ]

    IO.puts("Testing streaming functionality after field mismatch fix\n")

    results = Enum.map(tests, fn {provider, model} ->
      result = test_streaming(provider, model)
      IO.puts("")
      {provider, result}
    end)

    IO.puts("\n=== STREAMING TEST RESULTS ===")
    Enum.each(results, fn {provider, result} ->
      status = case result do
        :ok -> "✅ PASS"
        :error -> "❌ FAIL"
        :crash -> "💥 CRASH"
        :unknown -> "⚠️ UNKNOWN"
      end
      IO.puts("#{provider}: #{status}")
    end)

    # Count successes
    successes = Enum.count(results, fn {_, result} -> result == :ok end)
    total = length(results)
    IO.puts("\nSummary: #{successes}/#{total} providers working")
  end
end

StreamingTest.run_all_tests()