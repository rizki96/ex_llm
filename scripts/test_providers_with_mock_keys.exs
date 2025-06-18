#!/usr/bin/env elixir

# Test streaming with mock API keys for providers without real keys
Mix.install([
  {:ex_llm, path: "."}
])

defmodule MockKeyStreamingTest do
  require Logger

  def test_mistral() do
    IO.puts("\n============================================================")
    IO.puts("Testing Mistral with mock API key")
    IO.puts("============================================================")
    
    # Set a mock API key
    System.put_env("MISTRAL_API_KEY", "test-mistral-key")
    
    callback = fn chunk ->
      IO.write(".")
    end

    messages = [
      %{role: "user", content: "Hello"}
    ]

    try do
      result = ExLLM.ChatBuilder.new(:mistral, messages)
        |> ExLLM.ChatBuilder.with_model("mistral-small-latest")
        |> ExLLM.ChatBuilder.with_options(%{api_key: "test-mistral-key"})
        |> ExLLM.ChatBuilder.stream(callback)

      case result do
        :ok -> IO.puts("\n✅ Mistral streaming pipeline configured correctly")
        {:error, reason} -> IO.puts("\n❌ Mistral error: #{inspect(reason)}")
      end
    rescue
      e -> IO.puts("\n💥 Mistral crashed: #{Exception.message(e)}")
    end
  end

  def test_perplexity() do
    IO.puts("\n============================================================")
    IO.puts("Testing Perplexity with mock API key")
    IO.puts("============================================================")
    
    # Set a mock API key
    System.put_env("PERPLEXITY_API_KEY", "test-perplexity-key")
    
    callback = fn chunk ->
      IO.write(".")
    end

    messages = [
      %{role: "user", content: "Hello"}
    ]

    try do
      result = ExLLM.ChatBuilder.new(:perplexity, messages)
        |> ExLLM.ChatBuilder.with_model("llama-3.1-sonar-small-128k-online")
        |> ExLLM.ChatBuilder.with_options(%{api_key: "test-perplexity-key"})
        |> ExLLM.ChatBuilder.stream(callback)

      case result do
        :ok -> IO.puts("\n✅ Perplexity streaming pipeline configured correctly")
        {:error, reason} -> IO.puts("\n❌ Perplexity error: #{inspect(reason)}")
      end
    rescue
      e -> IO.puts("\n💥 Perplexity crashed: #{Exception.message(e)}")
    end
  end

  def run() do
    IO.puts("Testing providers without real API keys...")
    test_mistral()
    test_perplexity()
    IO.puts("\nNote: These tests verify pipeline configuration, not actual API calls.")
  end
end

MockKeyStreamingTest.run()