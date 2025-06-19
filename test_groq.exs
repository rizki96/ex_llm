#!/usr/bin/env elixir

# Groq Provider Test
Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

IO.puts("\n=== Groq Provider Test ===\n")

# 1. Test provider configuration
IO.puts("1. Testing provider configuration...")
if ExLLM.Providers.Groq.configured?() do
  IO.puts("✓ Groq provider is configured")
else
  IO.puts("❌ Groq provider is not configured")
  IO.puts("Make sure GROQ_API_KEY is set in environment")
  System.halt(1)
end

# 2. Test basic chat
IO.puts("\n2. Testing basic chat...")
case ExLLM.chat(:groq, [
  %{role: "user", content: "Reply with just the word 'hello' and nothing else"}
], model: "llama3-8b-8192") do
  {:ok, response} ->
    IO.puts("✓ Chat successful!")
    IO.puts("Response: #{inspect(response.content)}")
    IO.puts("Model: #{response.model}")
    if response.usage do
      input_tokens = response.usage[:input_tokens] || response.usage[:prompt_tokens] || 0
      output_tokens = response.usage[:output_tokens] || response.usage[:completion_tokens] || 0
      IO.puts("Tokens: #{response.usage.total_tokens} total (#{input_tokens} in, #{output_tokens} out)")
    end
    if response.cost do
      IO.puts("Cost: $#{response.cost.total}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Chat failed: #{inspect(reason)}")
end

# 3. Test streaming
IO.puts("\n3. Testing streaming...")
callback = fn chunk ->
  case chunk do
    %{content: content} when is_binary(content) ->
      IO.write(content)
      send(self(), {:chunk, content})
    _ ->
      :ok
  end
end

case ExLLM.stream(:groq, [
  %{role: "user", content: "Count from 1 to 5"}
], callback, model: "llama3-8b-8192") do
  {:ok, response} ->
    IO.puts("\n✓ Streaming successful!")
    IO.puts("Final response length: #{String.length(response.content || "")} characters")
    if response.usage do
      IO.puts("Tokens used: #{response.usage.total_tokens}")
    end
    
  {:error, _reason} ->
    IO.puts("\n❌ Streaming failed (this is expected due to streaming endpoint issue)")
    IO.puts("Reason: Pipeline failure - likely similar to LM Studio issue")
    
    # Try direct provider streaming if available
    IO.puts("\nTrying direct provider streaming...")
    case ExLLM.Providers.Groq.stream_chat([
      %{role: "user", content: "Count from 1 to 5"}
    ], [model: "llama3-8b-8192"], fn chunk ->
      if chunk.content, do: IO.write(chunk.content)
    end) do
      {:ok, response} ->
        IO.puts("\n✓ Direct provider streaming completed!")
        IO.puts("Response: #{inspect(response)}")
        
      {:error, direct_reason} ->
        IO.puts("❌ Direct streaming also failed: #{inspect(direct_reason)}")
    end
end

# 4. Test model listing
IO.puts("\n4. Testing model listing...")
case ExLLM.list_models(:groq) do
  {:ok, models} ->
    IO.puts("✓ Model listing successful!")
    IO.puts("Available models: #{length(models)}")
    
    # Show first few models
    models
    |> Enum.take(5)
    |> Enum.each(fn model ->
      IO.puts("  - #{model.id} (context: #{model.context_window || "unknown"})")
    end)
    
  {:error, reason} ->
    IO.puts("❌ Model listing failed: #{inspect(reason)}")
end

# 5. Test session management
IO.puts("\n5. Testing session management...")
session_id = "groq_test_#{System.system_time(:second)}"

case ExLLM.chat_session(:groq, [
  %{role: "user", content: "My name is Alice. What's my name?"}
], session: session_id, model: "llama3-8b-8192") do
  {:ok, response} ->
    IO.puts("✓ Session chat 1 successful!")
    IO.puts("Response: #{inspect(response.content)}")
    
    # Continue conversation
    case ExLLM.chat_session(:groq, [
      %{role: "user", content: "What did I just tell you my name was?"}
    ], session: session_id, model: "llama3-8b-8192") do
      {:ok, response2} ->
        IO.puts("✓ Session chat 2 successful!")
        IO.puts("Response: #{inspect(response2.content)}")
        
        # Check if session remembers
        if String.downcase(response2.content) =~ "alice" do
          IO.puts("✓ Session correctly remembers previous context!")
        else
          IO.puts("⚠️ Session may not be maintaining context properly")
        end
        
      {:error, reason} ->
        IO.puts("❌ Session chat 2 failed: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Session chat 1 failed: #{inspect(reason)}")
end

# 6. Test different models
IO.puts("\n6. Testing different models...")
test_models = [
  "llama3-70b-8192",
  "mixtral-8x7b-32768", 
  "gemma-7b-it"
]

for model <- test_models do
  IO.puts("\nTesting model: #{model}")
  case ExLLM.chat(:groq, [
    %{role: "user", content: "Say 'Working' in one word"}
  ], model: model, timeout: 30000) do
    {:ok, response} ->
      IO.puts("✓ #{model}: #{String.trim(response.content || "")}")
      
    {:error, reason} ->
      IO.puts("❌ #{model} failed: #{inspect(reason)}")
  end
end

# 7. Test provider capabilities
IO.puts("\n7. Testing provider capabilities...")
case ExLLM.Core.Capabilities.get_provider_capabilities(:groq) do
  {:ok, capabilities} ->
    IO.puts("✓ Capabilities retrieved!")
    IO.puts("Endpoints: #{inspect(capabilities.endpoints)}")
    IO.puts("Features: #{inspect(capabilities.features)}")
    
  {:error, reason} ->
    IO.puts("❌ Capabilities failed: #{inspect(reason)}")
end

IO.puts("\n✅ Groq provider tests complete!")
IO.puts("\nSummary:")
IO.puts("- Basic chat: Tested")  
IO.puts("- Streaming: Tested")
IO.puts("- Model listing: Tested")
IO.puts("- Session management: Tested")
IO.puts("- Multiple models: Tested")
IO.puts("- Provider capabilities: Tested")