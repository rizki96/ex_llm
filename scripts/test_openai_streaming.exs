#!/usr/bin/env elixir

# Test just OpenAI streaming after access fix
Mix.install([
  {:ex_llm, path: "."}
])

defmodule OpenAIStreamingTest do
  require Logger

  def test_openai() do
    IO.puts("Testing OpenAI streaming after access fix")
    
    try do
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

      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Count from 1 to 5, one number per response."}
      ]

      result = ExLLM.ChatBuilder.new(:openai, messages)
        |> ExLLM.ChatBuilder.with_model("gpt-4o-mini")
        |> ExLLM.ChatBuilder.stream(callback)

      case result do
        :ok ->
          IO.puts("\n✅ OpenAI streaming completed successfully")
        {:error, reason} ->
          IO.puts("\n❌ OpenAI streaming failed: #{inspect(reason)}")
      end
    rescue
      e ->
        IO.puts("\n💥 OpenAI streaming crashed: #{Exception.message(e)}")
        IO.puts("#{Exception.format_stacktrace(__STACKTRACE__)}")
    end
  end

  defp get_content_from_chunk(%{"choices" => [%{"delta" => %{"content" => content}} | _]}), do: content
  defp get_content_from_chunk(_), do: nil
end

OpenAIStreamingTest.test_openai()