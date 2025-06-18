#!/usr/bin/env elixir

# Test X.AI (Grok) streaming
Mix.install([
  {:ex_llm, path: "."}
])

defmodule XAIStreamingTest do
  require Logger

  def test_xai() do
    IO.puts("\n============================================================")
    IO.puts("Testing X.AI (Grok) streaming")
    IO.puts("============================================================")
    
    callback = fn chunk ->
      case chunk do
        %{done: true} = final ->
          IO.puts("\n✅ Stream complete: #{inspect(final)}")
        %{} = chunk ->
          content = get_content_from_chunk(chunk)
          if content && String.trim(content) != "" do
            IO.write(content)
          end
      end
    end

    messages = [
      %{role: "system", content: "You are a helpful assistant. Respond in 10 words or less."},
      %{role: "user", content: "What is X.AI's mission?"}
    ]

    api_key = System.get_env("XAI_API_KEY") || System.get_env("GROK_API_KEY")
    
    if api_key do
      try do
        result = ExLLM.ChatBuilder.new(:xai, messages)
          |> ExLLM.ChatBuilder.with_model("grok-2-1212")
          |> ExLLM.ChatBuilder.with_options(%{api_key: api_key})
          |> ExLLM.ChatBuilder.stream(callback)

        case result do
          :ok ->
            IO.puts("\n✅ X.AI streaming completed successfully")
          {:error, reason} ->
            IO.puts("\n❌ X.AI streaming failed: #{inspect(reason)}")
        end
      rescue
        e ->
          IO.puts("\n💥 X.AI streaming crashed: #{Exception.message(e)}")
          IO.puts("#{Exception.format_stacktrace(__STACKTRACE__)}")
      end
    else
      IO.puts("⏭️  Skipping X.AI (no API key found in XAI_API_KEY or GROK_API_KEY)")
    end
  end

  defp get_content_from_chunk(%{"choices" => [%{"delta" => %{"content" => content}} | _]}), do: content
  defp get_content_from_chunk(_), do: nil

  def run() do
    test_xai()
  end
end

XAIStreamingTest.run()