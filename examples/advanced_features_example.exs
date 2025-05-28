# Advanced Features Example with ExLLM
#
# This example demonstrates advanced features including:
# - Function calling
# - Error recovery and retries
# - Mock adapter for testing
# - Model capability discovery
#
# Run with: mix run examples/advanced_features_example.exs

defmodule AdvancedExamples do
  # Example function implementations
  def get_weather(location, unit \\ "celsius") do
    # Simulate weather API call
    %{
      location: location,
      temperature: 22,
      unit: unit,
      condition: "partly cloudy",
      humidity: 65,
      wind_speed: 12
    }
  end
  
  def search_products(query, category \\ nil) do
    # Simulate product search
    products = [
      %{name: "iPhone 15 Pro", price: 999, category: "electronics"},
      %{name: "MacBook Air M3", price: 1299, category: "electronics"},
      %{name: "AirPods Pro", price: 249, category: "electronics"}
    ]
    
    products
    |> Enum.filter(fn p -> 
      String.contains?(String.downcase(p.name), String.downcase(query)) and
      (is_nil(category) or p.category == category)
    end)
    |> Enum.take(3)
  end
  
  def run do
    IO.puts("\n🚀 ExLLM Advanced Features Examples\n")
    
    # Example 1: Function Calling
    IO.puts("1️⃣ Function Calling Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    functions = [
      %{
        name: "get_weather",
        description: "Get the current weather for a location",
        parameters: %{
          type: "object",
          properties: %{
            location: %{
              type: "string", 
              description: "City, State or Country"
            },
            unit: %{
              type: "string", 
              enum: ["celsius", "fahrenheit"],
              description: "Temperature unit"
            }
          },
          required: ["location"]
        }
      },
      %{
        name: "search_products",
        description: "Search for products",
        parameters: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description: "Search query"
            },
            category: %{
              type: "string",
              description: "Product category filter"
            }
          },
          required: ["query"]
        }
      }
    ]
    
    messages = [
      %{role: "user", content: "What's the weather like in Paris, France? Also, can you find me some Apple products?"}
    ]
    
    # Check if we're using a real provider
    provider = if ExLLM.configured?(:anthropic), do: :anthropic, else: :mock
    
    # Configure mock response if using mock adapter
    mock_options = if provider == :mock do
      [
        mock_response: %{
          content: "I'll help you with that. Let me check the weather in Paris and search for Apple products.",
          function_calls: [
            %{
              name: "get_weather",
              arguments: %{location: "Paris, France", unit: "celsius"}
            },
            %{
              name: "search_products",
              arguments: %{query: "Apple", category: "electronics"}
            }
          ]
        }
      ]
    else
      []
    end
    
    case ExLLM.chat(provider, messages, Keyword.merge([functions: functions], mock_options)) do
      {:ok, response} ->
        IO.puts("Assistant: #{response.content}")
        
        # Parse function calls
        case ExLLM.parse_function_calls(response, functions) do
          {:ok, calls} when length(calls) > 0 ->
            IO.puts("\nFunction calls detected:")
            
            Enum.each(calls, fn call ->
              IO.puts("\n  Executing: #{call.name}(#{inspect(call.arguments)})")
              
              # Execute the function
              result = case call.name do
                "get_weather" -> 
                  get_weather(call.arguments.location, call.arguments[:unit] || "celsius")
                "search_products" ->
                  search_products(call.arguments.query, call.arguments[:category])
                _ ->
                  %{error: "Unknown function"}
              end
              
              IO.puts("  Result: #{inspect(result)}")
              
              # Format result for conversation
              function_message = ExLLM.format_function_result(call.name, result)
              IO.puts("  Formatted for LLM: #{inspect(function_message)}")
            end)
            
          _ ->
            IO.puts("\nNo function calls detected")
        end
        
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    # Example 2: Error Recovery and Retries
    IO.puts("\n\n2️⃣ Error Recovery and Retry Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Simulate retries with mock adapter
    retry_messages = [
      %{role: "user", content: "Tell me a story about resilience"}
    ]
    
    # First attempt will fail, second will succeed
    attempt = :persistent_term.get({__MODULE__, :retry_attempt}, 0)
    :persistent_term.put({__MODULE__, :retry_attempt}, attempt + 1)
    
    mock_retry_options = [
      mock_handler: fn _messages ->
        current_attempt = :persistent_term.get({__MODULE__, :retry_attempt}, 1)
        if current_attempt <= 1 do
          {:error, {:api_error, %{status: 503, body: "Service temporarily unavailable"}}}
        else
          {:ok, "Here's a story about resilience: Once upon a time..."}
        end
      end,
      retry_count: 3,
      retry_delay: 100,
      retry_backoff: :exponential
    ]
    
    IO.puts("Attempting API call with automatic retry...")
    
    case ExLLM.chat(:mock, retry_messages, mock_retry_options) do
      {:ok, response} ->
        IO.puts("Success after retries!")
        IO.puts("Response: #{response.content}")
        
      {:error, reason} ->
        IO.puts("Failed after all retries: #{inspect(reason)}")
    end
    
    # Reset retry counter
    :persistent_term.put({__MODULE__, :retry_attempt}, 0)
    
    # Example 3: Stream Recovery
    IO.puts("\n\n3️⃣ Stream Recovery Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    stream_messages = [
      %{role: "user", content: "Write a haiku about Elixir programming"}
    ]
    
    # Simulate interrupted stream
    chunks = [
      "Elixir flows like",
      " water through pipes,",
      " concurrent and pure—",
      " Functions transform state"
    ]
    
    IO.puts("Starting stream with recovery enabled...")
    
    # Track chunks received
    chunk_count = 0
    
    stream_options = [
      mock_chunks: chunks,
      chunk_delay: 50,
      stream_recovery: true,
      recovery_strategy: :paragraph
    ]
    
    case ExLLM.stream_chat(:mock, stream_messages, stream_options, fn chunk ->
      IO.write(chunk.content)
      chunk_count = chunk_count + 1
      
      # Simulate interruption after 2 chunks
      if chunk_count == 2 do
        IO.puts("\n[Stream interrupted!]")
        throw(:stream_interrupted)
      end
    end) do
      {:ok, stream_id} ->
        IO.puts("\n[Stream completed with ID: #{stream_id}]")
        
      {:error, :stream_interrupted} ->
        IO.puts("\n[Attempting to recover stream...]")
        
        # In a real scenario, you would use ExLLM.resume_stream(stream_id)
        # For this example, we'll simulate recovery
        IO.puts("[Resuming from: ' concurrent and pure—']")
        IO.puts(" Functions transform state")
        IO.puts("[Stream recovery successful!]")
    end
    
    # Example 4: Model Discovery and Capabilities
    IO.puts("\n\n4️⃣ Model Discovery Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # List available models
    {:ok, models} = ExLLM.list_models(:anthropic)
    IO.puts("Available Anthropic models:")
    Enum.each(models, fn model ->
      IO.puts("  - #{model.name} (context: #{model.context_window} tokens)")
    end)
    
    # Find models with specific features
    IO.puts("\nModels with function calling:")
    function_models = ExLLM.find_models_with_features([:function_calling])
    Enum.each(function_models, fn {provider, model} ->
      IO.puts("  - #{provider}: #{model}")
    end)
    
    # Get recommendations
    IO.puts("\nRecommended models for large context + function calling:")
    recommendations = ExLLM.recommend_models(%{
      min_context_window: 100_000,
      required_features: [:function_calling],
      max_cost_per_million_tokens: 20.0
    })
    
    Enum.take(recommendations, 3) |> Enum.each(fn rec ->
      IO.puts("  - #{rec.provider}: #{rec.model}")
      IO.puts("    Context: #{rec.context_window}, Cost: $#{rec.cost_per_million}/M tokens")
      IO.puts("    Score: #{Float.round(rec.score, 2)}")
    end)
    
    # Compare models
    IO.puts("\nModel comparison:")
    comparison = ExLLM.compare_models([
      {:anthropic, "claude-3-5-sonnet-20241022"},
      {:openai, "gpt-4-turbo"},
      {:ollama, "llama2"}
    ])
    
    IO.puts("Feature support matrix:")
    IO.puts("                          | Streaming | Functions | Vision |")
    IO.puts("--------------------------|-----------|-----------|--------|")
    Enum.each(comparison, fn {model_key, info} ->
      {provider, model} = model_key
      row = String.pad_trailing("#{provider}/#{model}", 25)
      row = row <> " | " <> String.pad_trailing(to_string(info.capabilities.streaming), 9)
      row = row <> " | " <> String.pad_trailing(to_string(info.capabilities.function_calling), 9)
      row = row <> " | " <> String.pad_trailing(to_string(info.capabilities.vision), 6) <> " |"
      IO.puts(row)
    end)
    
    # Example 5: Testing with Mock Adapter
    IO.puts("\n\n5️⃣ Mock Adapter Testing Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Clear any previous captures
    ExLLM.Adapters.Mock.clear_captured_requests()
    
    # Test different scenarios
    test_messages = [
      %{role: "user", content: "What is 2 + 2?"}
    ]
    
    # Simple mock
    IO.puts("Test 1: Simple mock response")
    {:ok, response} = ExLLM.chat(:mock, test_messages,
      mock_response: "2 + 2 equals 4",
      capture_requests: true
    )
    IO.puts("Response: #{response.content}")
    
    # Dynamic mock based on input
    IO.puts("\nTest 2: Dynamic mock handler")
    math_handler = fn messages ->
      last_msg = List.last(messages).content
      cond do
        String.contains?(last_msg, "2 + 2") -> "The answer is 4"
        String.contains?(last_msg, "meaning of life") -> "42"
        true -> "I need more information"
      end
    end
    
    {:ok, response} = ExLLM.chat(:mock, test_messages,
      mock_handler: math_handler,
      capture_requests: true
    )
    IO.puts("Response: #{response.content}")
    
    # Verify captured requests
    IO.puts("\nCaptured requests:")
    requests = ExLLM.Adapters.Mock.get_captured_requests()
    Enum.each(requests, fn req ->
      IO.puts("  - Provider: #{req.provider}")
      IO.puts("    Messages: #{length(req.messages)}")
      IO.puts("    Options: #{inspect(Map.keys(req.options))}")
    end)
    
    IO.puts("\n\n✅ All advanced examples completed!")
  end
end

# Run the examples
AdvancedExamples.run()