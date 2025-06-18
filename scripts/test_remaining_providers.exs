#!/usr/bin/env elixir

# Test remaining providers systematically

defmodule RemainingProviderTests do
  def run_tests do
    IO.puts("🔧 Testing Remaining ExLLM v1.0 Providers")
    IO.puts("==========================================\n")

    # Test each provider individually
    test_anthropic()
    test_gemini() 
    test_streaming()
    
    IO.puts("\n✅ Remaining provider testing completed!")
  end

  defp test_anthropic do
    IO.puts("🤖 Testing Anthropic...")
    
    # Test 1: Basic chat
    IO.write("  Basic chat: ")
    try do
      {:ok, result} = ExLLM.chat(:anthropic, [%{role: "user", content: "Hi"}])
      IO.puts("✅ (Model: #{result.model})")
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end

    # Test 2: ChatBuilder
    IO.write("  ChatBuilder: ")
    try do
      {:ok, result} = ExLLM.build(:anthropic, [%{role: "user", content: "Hi"}])
                      |> ExLLM.with_temperature(0.1)
                      |> ExLLM.execute()
      IO.puts("✅")
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end

    # Test 3: Pipeline inspection
    IO.write("  Pipeline: ")
    try do
      pipeline = ExLLM.Providers.get_pipeline(:anthropic, :chat)
      IO.puts("✅ (#{length(pipeline)} plugs)")
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end
  end

  defp test_gemini do
    IO.puts("\n🧠 Testing Gemini...")
    
    # Test 1: Basic chat
    IO.write("  Basic chat: ")
    try do
      {:ok, result} = ExLLM.chat(:gemini, [%{role: "user", content: "Hi"}])
      IO.puts("✅ (Model: #{result.model})")
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end

    # Test 2: ChatBuilder
    IO.write("  ChatBuilder: ")
    try do
      {:ok, result} = ExLLM.build(:gemini, [%{role: "user", content: "Hi"}])
                      |> ExLLM.with_temperature(0.1)
                      |> ExLLM.execute()
      IO.puts("✅")
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end

    # Test 3: Pipeline inspection
    IO.write("  Pipeline: ")
    try do
      pipeline = ExLLM.Providers.get_pipeline(:gemini, :chat)
      IO.puts("✅ (#{length(pipeline)} plugs)")
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end
  end

  defp test_streaming do
    IO.puts("\n📡 Testing Streaming...")
    
    # Test with working provider (OpenAI)
    IO.write("  OpenAI streaming: ")
    try do
      result = ExLLM.build(:openai, [%{role: "user", content: "Say hi"}])
                |> ExLLM.with_temperature(0.1)
                |> ExLLM.stream(fn _chunk -> :ok end)
      
      case result do
        :ok -> IO.puts("✅")
        {:error, reason} -> IO.puts("❌ #{inspect(reason)}")
      end
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end

    # Test with Groq
    IO.write("  Groq streaming: ")
    try do
      result = ExLLM.build(:groq, [%{role: "user", content: "Say hi"}])
                |> ExLLM.with_temperature(0.1)
                |> ExLLM.stream(fn _chunk -> :ok end)
      
      case result do
        :ok -> IO.puts("✅")
        {:error, reason} -> IO.puts("❌ #{inspect(reason)}")
      end
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end
  end
end

# Run the tests
RemainingProviderTests.run_tests()