#!/usr/bin/env elixir

# Test Groq streaming after adding stream pipeline
Mix.install([
  {:ex_llm, path: "."}
])

defmodule GroqStreamingTest do
  require Logger

  def test_groq() do
    IO.puts("Testing Groq streaming after adding stream pipeline")
    
    try do
      callback = fn chunk ->
        case chunk do
          %{done: true} = final ->
            IO.puts("\nStream complete: #{inspect(final)}")
          %{} = chunk ->
            content = get_content_from_chunk(chunk)
            if content && String.trim(content) != "" do
              IO.write(content)
            end
        end
      end

      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Count from 1 to 5, one number per response."}
      ]

      result = ExLLM.ChatBuilder.new(:groq, messages)
        |> ExLLM.ChatBuilder.with_model("llama-3.1-8b-instant")
        |> ExLLM.ChatBuilder.stream(callback)

      case result do
        :ok ->
          IO.puts("\n✅ Groq streaming completed successfully")
        {:error, reason} ->
          IO.puts("\n❌ Groq streaming failed: #{inspect(reason)}")
      end
    rescue
      e ->
        IO.puts("\n💥 Groq streaming crashed: #{Exception.message(e)}")
        IO.puts("#{Exception.format_stacktrace(__STACKTRACE__)}")
    end
  end

  defp get_content_from_chunk(%{"choices" => [%{"delta" => %{"content" => content}} | _]}), do: content
  defp get_content_from_chunk(_), do: nil
end

GroqStreamingTest.test_groq()