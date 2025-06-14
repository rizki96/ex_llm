#!/usr/bin/env elixir

# Example demonstrating unified streaming across different providers

Mix.install([
  {:ex_llm, path: "."}
])

defmodule StreamingExample do
  @doc """
  Demonstrates streaming with different providers
  """
  def run do
    IO.puts("ExLLM Unified Streaming Example")
    IO.puts("================================\n")
    
    messages = [
      %{role: "user", content: "Count from 1 to 5, one number per line"}
    ]
    
    # Try different providers
    providers = [
      {:openai, "gpt-4.1-nano"},
      {:anthropic, "claude-3-5-haiku-latest"},
      {:gemini, "gemini-2.0-flash"},
      {:ollama, "llama3.2:latest"},
      {:groq, "llama-3.3-70b-versatile"}
    ]
    
    Enum.each(providers, fn {provider, model} ->
      IO.puts("\n#{String.upcase(to_string(provider))} (#{model}):")
      IO.puts(String.duplicate("-", 50))
      
      case stream_with_provider(provider, model, messages) do
        {:ok, content} ->
          IO.puts("Response: #{content}")
        {:error, reason} ->
          IO.puts("Error: #{inspect(reason)}")
      end
    end)
  end
  
  defp stream_with_provider(provider, model, messages) do
    try do
      case ExLLM.stream_chat(provider, messages, model: model) do
        {:ok, stream} ->
          content = 
            stream
            |> Enum.map(& &1.content)
            |> Enum.filter(& &1)
            |> Enum.join("")
          
          {:ok, content}
          
        {:error, reason} ->
          {:error, reason}
      end
    catch
      error -> {:error, error}
    end
  end
end

StreamingExample.run()