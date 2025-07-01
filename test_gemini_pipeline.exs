#!/usr/bin/env elixir

# Test Gemini pipeline issue
Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

# Set log level to debug to see what's happening
Logger.configure(level: :debug)

defmodule GeminiPipelineTest do
  def test_pipeline do
    IO.puts("\n=== Testing Gemini Pipeline ===\n")
    
    # Simple test message
    messages = [
      %{role: "user", content: "What is 2+2?"}
    ]
    
    # Test with minimal options
    options = [
      model: "gemini-2.0-flash"
    ]
    
    IO.puts("Sending request to Gemini...")
    
    case ExLLM.chat(:gemini, messages, options) do
      {:ok, response} ->
        IO.puts("\n✅ SUCCESS")
        IO.puts("Response: #{response.content}")
        IO.puts("Model: #{response.model}")
        
      {:error, error} ->
        IO.puts("\n❌ ERROR")
        IO.puts("Error details: #{inspect(error, pretty: true)}")
        
        # If it's a pipeline error, let's dig deeper
        case error do
          %{error: :unexpected_pipeline_state, details: details} ->
            IO.puts("\nPipeline state details:")
            IO.puts("  Request: #{inspect(Map.get(details, :request), pretty: true)}")
            IO.puts("  State: #{inspect(Map.get(details, :state), pretty: true)}")
            
          _ ->
            :ok
        end
    end
  end
end

GeminiPipelineTest.test_pipeline()