#!/usr/bin/env elixir

# Debug script to test Gemini function calling and examine raw response format

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"},
  {:req, "~> 0.5"}
])

defmodule GeminiFunctionCallingDebug do
  def run do
    # Define a simple weather function
    functions = [
      %{
        name: "get_weather",
        description: "Get the current weather in a given location",
        parameters: %{
          type: "object",
          properties: %{
            location: %{
              type: "string",
              description: "The city and state, e.g. San Francisco, CA"
            },
            unit: %{
              type: "string",
              enum: ["celsius", "fahrenheit"],
              description: "Temperature unit"
            }
          },
          required: ["location"]
        }
      }
    ]

    # Test message that should trigger function call
    messages = [
      %{
        role: "user",
        content: "What's the weather like in San Francisco?"
      }
    ]

    IO.puts("\n=== Testing Gemini Function Calling ===\n")
    IO.puts("Functions defined:")
    IO.inspect(functions, pretty: true, limit: :infinity)
    IO.puts("\nMessages:")
    IO.inspect(messages, pretty: true)

    # First, test with ExLLM to see what we get
    IO.puts("\n=== Testing with ExLLM ===")
    
    case ExLLM.Providers.Gemini.chat(messages,
      model: "gemini-1.5-flash",
      tools: functions
    ) do
      {:ok, response} ->
        IO.puts("\nExLLM Response:")
        IO.inspect(response, pretty: true, limit: :infinity)
      
      {:error, error} ->
        IO.puts("\nExLLM Error:")
        IO.inspect(error, pretty: true)
    end

    # Now make a direct API call to see the raw response
    IO.puts("\n=== Testing with Direct API Call ===")
    
    api_key = System.get_env("GEMINI_API_KEY")
    model = "gemini-1.5-flash"
    
    # Convert to Gemini format
    gemini_payload = %{
      contents: [
        %{
          role: "user",
          parts: [%{text: "What's the weather like in San Francisco?"}]
        }
      ],
      tools: [
        %{
          function_declarations: functions
        }
      ],
      tool_config: %{
        function_calling_config: %{
          mode: "AUTO"
        }
      }
    }

    url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}"
    
    IO.puts("\nRequest URL: #{url}")
    IO.puts("\nRequest payload:")
    IO.inspect(gemini_payload, pretty: true, limit: :infinity)

    case Req.post(url, json: gemini_payload) do
      {:ok, %{status: 200, body: body}} ->
        IO.puts("\n=== Raw API Response ===")
        IO.puts("\nFormatted JSON:")
        IO.puts(Jason.encode!(body, pretty: true))
        
        IO.puts("\n=== Response Structure Analysis ===")
        analyze_response(body)
        
      {:ok, %{status: status, body: body}} ->
        IO.puts("\nAPI Error (status #{status}):")
        IO.inspect(body, pretty: true, limit: :infinity)
        
      {:error, error} ->
        IO.puts("\nRequest Error:")
        IO.inspect(error, pretty: true)
    end

    # Also test with a message that shouldn't trigger function call
    IO.puts("\n\n=== Testing Non-Function Call ===")
    
    non_function_payload = %{
      contents: [
        %{
          role: "user",
          parts: [%{text: "Tell me a joke"}]
        }
      ],
      tools: [
        %{
          function_declarations: functions
        }
      ]
    }

    case Req.post(url, json: non_function_payload) do
      {:ok, %{status: 200, body: body}} ->
        IO.puts("\nNon-function call response:")
        IO.puts(Jason.encode!(body, pretty: true))
        
      {:ok, %{status: status, body: body}} ->
        IO.puts("\nAPI Error (status #{status}):")
        IO.inspect(body, pretty: true)
        
      {:error, error} ->
        IO.puts("\nRequest Error:")
        IO.inspect(error, pretty: true)
    end
  end

  defp analyze_response(body) do
    if candidates = body["candidates"] do
      Enum.each(Enum.with_index(candidates), fn {candidate, index} ->
        IO.puts("\nCandidate #{index}:")
        
        if content = candidate["content"] do
          IO.puts("  Role: #{content["role"]}")
          
          if parts = content["parts"] do
            Enum.each(Enum.with_index(parts), fn {part, part_index} ->
              IO.puts("  Part #{part_index}:")
              
              cond do
                Map.has_key?(part, "text") ->
                  IO.puts("    Type: text")
                  IO.puts("    Content: #{part["text"]}")
                  
                Map.has_key?(part, "functionCall") ->
                  IO.puts("    Type: function_call")
                  IO.puts("    Function: #{part["functionCall"]["name"]}")
                  IO.puts("    Arguments:")
                  IO.inspect(part["functionCall"]["args"], pretty: true, limit: :infinity, printable_limit: :infinity)
                  
                true ->
                  IO.puts("    Unknown part type:")
                  IO.inspect(part, pretty: true)
              end
            end)
          end
        end
        
        if finish_reason = candidate["finishReason"] do
          IO.puts("  Finish reason: #{finish_reason}")
        end
      end)
    end
  end
end

# Run the debug script
GeminiFunctionCallingDebug.run()