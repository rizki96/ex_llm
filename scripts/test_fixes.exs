#!/usr/bin/env elixir

# Simple test script to validate our key fixes

defmodule FixValidationTest do
  def run_tests do
    IO.puts("🔧 Testing ExLLM v1.0 Pipeline Fixes")
    IO.puts("===================================\n")

    # Test 1: Cost tracking fix
    test_cost_tracking()
    
    # Test 2: OpenAI basic functionality
    test_openai_basic()
    
    # Test 3: Groq with correct model
    test_groq_basic()
    
    # Test 4: ChatBuilder API
    test_chatbuilder()
    
    IO.puts("\n✅ Fix validation completed!")
  end

  defp test_cost_tracking do
    IO.write("Cost tracking fix: ")
    
    try do
      {:ok, result} = ExLLM.chat(:openai, [%{role: "user", content: "Hi"}])
      
      if result.cost && result.cost.total && result.cost.total > 0 do
        IO.puts("✅ (Cost: $#{Float.round(result.cost.total, 6)})")
      else
        IO.puts("❌ No cost data")
      end
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end
  end

  defp test_openai_basic do
    IO.write("OpenAI basic chat: ")
    
    try do
      {:ok, result} = ExLLM.chat(:openai, [%{role: "user", content: "Say hi"}])
      
      if result.content && String.length(result.content) > 0 do
        IO.puts("✅")
      else
        IO.puts("❌ No content")
      end
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end
  end

  defp test_groq_basic do
    IO.write("Groq with correct model: ")
    
    try do
      {:ok, result} = ExLLM.chat(:groq, [%{role: "user", content: "Hi"}])
      
      if result.content && String.length(result.content) > 0 do
        IO.puts("✅ (Model: #{result.model})")
      else
        IO.puts("❌ No content")
      end
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end
  end

  defp test_chatbuilder do
    IO.write("ChatBuilder API: ")
    
    try do
      {:ok, result} = ExLLM.build(:openai, [%{role: "user", content: "Hi"}])
                      |> ExLLM.with_temperature(0.1)
                      |> ExLLM.without_cost_tracking()
                      |> ExLLM.execute()
      
      if result.content && String.length(result.content) > 0 do
        IO.puts("✅")
      else
        IO.puts("❌ No content")
      end
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end
  end
end

# Run the tests
FixValidationTest.run_tests()