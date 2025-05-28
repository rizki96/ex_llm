# Testing with Mock Adapter Example
#
# This example shows how to use the mock adapter for testing your LLM integrations

defmodule WeatherBot do
  @moduledoc """
  Example bot that uses ExLLM to answer weather questions.
  """
  
  def get_weather_response(location, provider \\ :openai) do
    messages = [
      %{
        role: "system",
        content: "You are a helpful weather assistant. Be concise."
      },
      %{
        role: "user",
        content: "What's the weather like in #{location}?"
      }
    ]
    
    case ExLLM.chat(provider, messages) do
      {:ok, response} -> {:ok, response.content}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def get_weather_with_function_call(location, provider \\ :openai) do
    messages = [
      %{
        role: "user",
        content: "What's the current weather in #{location}?"
      }
    ]
    
    functions = [
      %{
        name: "get_current_weather",
        description: "Get the current weather for a location",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "location" => %{
              "type" => "string",
              "description" => "City name"
            },
            "unit" => %{
              "type" => "string",
              "enum" => ["celsius", "fahrenheit"]
            }
          },
          "required" => ["location"]
        }
      }
    ]
    
    ExLLM.chat(provider, messages, functions: functions, function_call: "auto")
  end
end

defmodule WeatherBotTest do
  @moduledoc """
  Example test module showing different mock adapter patterns.
  """
  
  use ExUnit.Case
  alias ExLLM.Adapters.Mock
  
  setup do
    Mock.start_link()
    Mock.reset()
    :ok
  end
  
  describe "basic weather responses" do
    test "returns weather information" do
      # Set up mock response
      Mock.set_response(%{
        content: "The weather in Paris is sunny and 22°C.",
        model: "gpt-4",
        usage: %{input_tokens: 15, output_tokens: 12}
      })
      
      # Test the function
      assert {:ok, response} = WeatherBot.get_weather_response("Paris", :mock)
      assert response == "The weather in Paris is sunny and 22°C."
      
      # Verify the request
      request = Mock.get_last_request()
      assert request.type == :chat
      assert length(request.messages) == 2
      assert List.last(request.messages).content =~ "Paris"
    end
    
    test "handles API errors gracefully" do
      # Simulate API error
      Mock.set_error({:api_error, %{status: 503, body: "Service unavailable"}})
      
      assert {:error, {:api_error, %{status: 503}}} = 
        WeatherBot.get_weather_response("London", :mock)
    end
    
    test "uses dynamic responses based on input" do
      # Set up dynamic handler
      Mock.set_response_handler(fn messages, _options ->
        user_message = List.last(messages).content
        location = extract_location(user_message)
        
        weather_data = %{
          "Tokyo" => "rainy and 18°C",
          "Sydney" => "sunny and 25°C",
          "New York" => "cloudy and 10°C"
        }
        
        weather = Map.get(weather_data, location, "unknown")
        
        %{
          content: "The weather in #{location} is #{weather}.",
          model: "gpt-4"
        }
      end)
      
      # Test different locations
      assert {:ok, response1} = WeatherBot.get_weather_response("Tokyo", :mock)
      assert response1 =~ "rainy and 18°C"
      
      assert {:ok, response2} = WeatherBot.get_weather_response("Sydney", :mock)
      assert response2 =~ "sunny and 25°C"
    end
  end
  
  describe "function calling" do
    test "returns function call for weather request" do
      # Set up function call response
      Mock.set_response(%{
        content: nil,
        function_call: %{
          name: "get_current_weather",
          arguments: Jason.encode!(%{
            "location" => "Berlin",
            "unit" => "celsius"
          })
        }
      })
      
      assert {:ok, response} = WeatherBot.get_weather_with_function_call("Berlin", :mock)
      assert response.function_call
      assert response.function_call.name == "get_current_weather"
      
      # Parse arguments
      {:ok, args} = Jason.decode(response.function_call.arguments)
      assert args["location"] == "Berlin"
      assert args["unit"] == "celsius"
    end
    
    test "validates function calling flow" do
      # Step 1: Initial request returns function call
      Mock.set_response(%{
        content: nil,
        function_call: %{
          name: "get_current_weather",
          arguments: ~s({"location": "Madrid", "unit": "celsius"})
        }
      })
      
      {:ok, response1} = WeatherBot.get_weather_with_function_call("Madrid", :mock)
      assert response1.function_call
      
      # Step 2: Set response for after function execution
      Mock.set_response(%{
        content: "The current weather in Madrid is sunny and 28°C."
      })
      
      # Simulate continuing conversation with function result
      function_result = %{
        role: "function",
        name: "get_current_weather",
        content: Jason.encode!(%{temperature: 28, condition: "sunny", unit: "celsius"})
      }
      
      messages = [
        %{role: "user", content: "What's the current weather in Madrid?"},
        response1,
        function_result
      ]
      
      {:ok, final_response} = ExLLM.chat(:mock, messages)
      assert final_response.content =~ "sunny and 28°C"
    end
  end
  
  describe "request analysis" do
    test "analyzes multiple requests" do
      locations = ["Paris", "London", "Rome", "Berlin"]
      
      # Make multiple requests
      Enum.each(locations, fn location ->
        WeatherBot.get_weather_response(location, :mock)
      end)
      
      # Analyze requests
      requests = Mock.get_requests()
      assert length(requests) == 4
      
      # Check each request contains the expected location
      Enum.zip(requests, locations)
      |> Enum.each(fn {request, location} ->
        assert request.type == :chat
        user_message = List.last(request.messages).content
        assert user_message =~ location
      end)
    end
  end
  
  # Helper function
  defp extract_location(message) do
    # Simple extraction - in real code would be more robust
    cond do
      message =~ "Tokyo" -> "Tokyo"
      message =~ "Sydney" -> "Sydney"
      message =~ "New York" -> "New York"
      true -> "Unknown"
    end
  end
end

# Run the example tests
ExUnit.start()

IO.puts("""
Testing with Mock Adapter
========================

This example demonstrates how to use the mock adapter for testing.

Key features demonstrated:
1. Static responses for predictable testing
2. Dynamic responses based on input
3. Error simulation
4. Function calling mocks
5. Request capture and analysis

The mock adapter is perfect for:
- Unit testing your LLM integrations
- CI/CD pipelines (no API keys needed)
- Development without API costs
- Testing error handling
- Validating request/response flow

To run these tests in your project:
1. Add ExLLM to your test dependencies
2. Use Mock.set_response() in your test setup
3. Test with provider: :mock
4. Analyze captured requests with Mock.get_requests()
""")