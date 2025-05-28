# Function Calling Example for ExLLM
# 
# This example demonstrates how to use function calling with different providers

# Define our functions
defmodule WeatherFunctions do
  def get_weather(%{"location" => location} = args) do
    # Simulate weather API call
    unit = Map.get(args, "unit", "fahrenheit")
    
    weather_data = %{
      "San Francisco" => %{temperature: 65, condition: "cloudy"},
      "New York" => %{temperature: 45, condition: "rainy"},
      "Miami" => %{temperature: 85, condition: "sunny"}
    }
    
    case Map.get(weather_data, location) do
      nil -> 
        %{error: "Unknown location: #{location}"}
      data ->
        temp = if unit == "celsius" do
          round((data.temperature - 32) * 5/9)
        else
          data.temperature
        end
        
        %{
          location: location,
          temperature: temp,
          unit: unit,
          condition: data.condition
        }
    end
  end
  
  def get_time(%{"timezone" => timezone}) do
    # Simulate timezone API
    now = DateTime.utc_now()
    
    offset = case timezone do
      "PST" -> -8
      "EST" -> -5
      "GMT" -> 0
      _ -> 0
    end
    
    time = DateTime.add(now, offset * 3600, :second)
    %{
      timezone: timezone,
      time: DateTime.to_string(time)
    }
  end
end

# Define available functions for the LLM
functions = [
  %{
    name: "get_weather",
    description: "Get the current weather for a given location",
    parameters: %{
      "type" => "object",
      "properties" => %{
        "location" => %{
          "type" => "string",
          "description" => "The city name, e.g. San Francisco"
        },
        "unit" => %{
          "type" => "string",
          "enum" => ["celsius", "fahrenheit"],
          "description" => "Temperature unit"
        }
      },
      "required" => ["location"]
    },
    handler: &WeatherFunctions.get_weather/1
  },
  %{
    name: "get_time",
    description: "Get the current time in a timezone",
    parameters: %{
      "type" => "object",
      "properties" => %{
        "timezone" => %{
          "type" => "string",
          "description" => "Timezone abbreviation (PST, EST, GMT)"
        }
      },
      "required" => ["timezone"]
    },
    handler: &WeatherFunctions.get_time/1
  }
]

# Example conversation with function calling
defmodule FunctionCallingDemo do
  def run(provider \\ :openai) do
    IO.puts("\n=== Function Calling Demo with #{provider} ===\n")
    
    messages = [
      %{
        role: "user",
        content: "What's the weather like in San Francisco and what time is it there?"
      }
    ]
    
    # First request with functions
    IO.puts("User: #{messages |> List.first() |> Map.get(:content)}")
    
    case ExLLM.chat(provider, messages, functions: functions, function_call: "auto") do
      {:ok, response} ->
        handle_response(response, provider, messages, functions)
        
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end
  
  defp handle_response(response, provider, messages, functions) do
    # Check if there are function calls
    case ExLLM.parse_function_calls(response, provider) do
      {:ok, []} ->
        # No function calls, just print the response
        IO.puts("Assistant: #{response.content}")
        
      {:ok, function_calls} ->
        IO.puts("Assistant wants to call functions: #{Enum.map(function_calls, & &1.name) |> Enum.join(", ")}")
        
        # Execute all function calls
        results = Enum.map(function_calls, fn call ->
          IO.puts("\nExecuting function: #{call.name}")
          IO.puts("Arguments: #{inspect(call.arguments)}")
          
          case ExLLM.execute_function(call, functions) do
            {:ok, result} ->
              IO.puts("Result: #{inspect(result.result)}")
              result
              
            {:error, result} ->
              IO.puts("Error: #{inspect(result.error)}")
              result
          end
        end)
        
        # Format results and continue conversation
        updated_messages = messages ++ 
          [response] ++
          Enum.map(results, fn result ->
            ExLLM.format_function_result(result, provider)
          end)
        
        # Get final response
        IO.puts("\nGetting final response with function results...")
        
        case ExLLM.chat(provider, updated_messages) do
          {:ok, final_response} ->
            IO.puts("Assistant: #{final_response.content}")
            
          {:error, reason} ->
            IO.puts("Error getting final response: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("Error parsing function calls: #{inspect(reason)}")
    end
  end
end

# Run the demo
# Note: You'll need to have API keys configured for the providers
IO.puts("""
Function Calling Example
========================

This example demonstrates function calling with ExLLM.
Make sure you have configured API keys for the providers you want to test.

Available providers:
- :openai (requires OPENAI_API_KEY)
- :anthropic (requires ANTHROPIC_API_KEY)
- :gemini (requires GOOGLE_API_KEY)
""")

# Uncomment to run with different providers:
# FunctionCallingDemo.run(:openai)
# FunctionCallingDemo.run(:anthropic)
# FunctionCallingDemo.run(:gemini)

IO.puts("\nTo run the demo, uncomment one of the demo lines at the end of the file.")